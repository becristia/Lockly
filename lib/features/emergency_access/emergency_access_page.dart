import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/emergency/emergency_crypto_service.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class EmergencyAccessPage extends StatefulWidget {
  const EmergencyAccessPage({super.key, required this.services});

  final AppServices services;

  @override
  State<EmergencyAccessPage> createState() => _EmergencyAccessPageState();
}

class _EmergencyAccessPageState extends State<EmergencyAccessPage> {
  static const int _maxPlaintextBytes = 64 * 1024;

  final EmergencyCryptoService _crypto = EmergencyCryptoService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _publicKeyController = TextEditingController();
  final TextEditingController _fingerprintController = TextEditingController();
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _grantPlaintextController =
      TextEditingController();
  final TextEditingController _waitingHoursController = TextEditingController(
    text: '24',
  );

  late Future<_EmergencySnapshot> _snapshot;
  EmergencyKeyPairBundle? _generatedKeyPair;
  String? _selectedContactId;
  bool _generatingKeyPair = false;
  bool _creatingContact = false;
  bool _creatingGrant = false;
  final Set<String> _busyGrantIds = <String>{};
  final Set<String> _busyContactIds = <String>{};

  @override
  void initState() {
    super.initState();
    _snapshot = _loadSnapshot();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _publicKeyController.dispose();
    _fingerprintController.dispose();
    _labelController.dispose();
    _grantPlaintextController.clear();
    _grantPlaintextController.dispose();
    _waitingHoursController.dispose();
    super.dispose();
  }

  Future<_EmergencySnapshot> _loadSnapshot() async {
    List<EmergencyContact>? contacts;
    Object? contactsError;
    List<EmergencyGrant>? grants;
    Object? grantsError;

    try {
      contacts = await widget.services.listEmergencyContacts();
    } catch (error) {
      contactsError = error;
    }

    try {
      grants = await widget.services.listEmergencyGrants();
    } catch (error) {
      grantsError = error;
    }

    final activeContacts =
        contacts?.where((contact) => contact.status == 'active').toList() ??
        const <EmergencyContact>[];
    if (_selectedContactId == null && activeContacts.isNotEmpty) {
      _selectedContactId = activeContacts.first.id;
    }
    if (_selectedContactId != null &&
        activeContacts.every((contact) => contact.id != _selectedContactId)) {
      _selectedContactId = activeContacts.isEmpty
          ? null
          : activeContacts.first.id;
    }

    return _EmergencySnapshot(
      contacts: contacts,
      contactsError: contactsError,
      grants: grants,
      grantsError: grantsError,
    );
  }

  Future<void> _refresh() async {
    widget.services.recordActivity();
    setState(() {
      _snapshot = _loadSnapshot();
    });
    await _snapshot;
  }

  Future<void> _generateKeyPair() async {
    if (_generatingKeyPair) {
      return;
    }
    widget.services.recordActivity();
    setState(() {
      _generatingKeyPair = true;
    });
    try {
      final keyPair = await _crypto.generateKeyPair();
      if (!mounted) return;
      setState(() {
        _generatedKeyPair = keyPair;
        _generatingKeyPair = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _generatingKeyPair = false;
      });
      _showSnack('Emergency key generation failed');
    }
  }

  Future<void> _createContact() async {
    if (_creatingContact) {
      return;
    }
    final request = EmergencyContactCreateRequest(
      recipientEmail: _emailController.text.trim(),
      recipientPublicKey: _publicKeyController.text.trim(),
      recipientKeyFingerprint: _fingerprintController.text.trim(),
      recipientLabel: _emptyToNull(_labelController.text.trim()),
    );
    if (request.recipientEmail.isEmpty ||
        request.recipientPublicKey.isEmpty ||
        request.recipientKeyFingerprint.isEmpty) {
      _showSnack('Email, public key, and fingerprint are required');
      return;
    }

    try {
      request.toJson();
    } catch (_) {
      _showSnack('Contact key details are not accepted');
      return;
    }

    widget.services.recordActivity();
    setState(() {
      _creatingContact = true;
    });
    try {
      await widget.services.createEmergencyContact(request: request);
      _emailController.clear();
      _publicKeyController.clear();
      _fingerprintController.clear();
      _labelController.clear();
      if (!mounted) return;
      setState(() {
        _creatingContact = false;
        _snapshot = _loadSnapshot();
      });
      await _snapshot;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creatingContact = false;
      });
      _showSnack('Contact creation failed');
    }
  }

  Future<void> _revokeContact(EmergencyContact contact) async {
    final confirmed = await _confirm(
      title: 'Revoke contact',
      message: 'Revoke emergency access setup for this contact?',
      action: 'Revoke',
    );
    if (!confirmed || _busyContactIds.contains(contact.id)) {
      return;
    }
    widget.services.recordActivity();
    setState(() {
      _busyContactIds.add(contact.id);
    });
    try {
      await widget.services.revokeEmergencyContact(contact.id);
      await _refresh();
    } catch (_) {
      _showSnack('Contact revoke failed');
    } finally {
      if (mounted) {
        setState(() {
          _busyContactIds.remove(contact.id);
        });
      }
    }
  }

  Future<void> _createGrant(List<EmergencyContact> contacts) async {
    if (_creatingGrant) {
      return;
    }
    final contact = contacts
        .where((candidate) => candidate.id == _selectedContactId)
        .firstOrNull;
    if (contact == null) {
      _showSnack('Choose an active contact');
      return;
    }
    final waitingHours = int.tryParse(_waitingHoursController.text.trim());
    if (waitingHours == null || waitingHours < 1 || waitingHours > 2160) {
      _showSnack('Waiting period must be 1 to 2160 hours');
      return;
    }
    final plaintext = _grantPlaintextController.text;
    if (plaintext.isEmpty) {
      _showSnack('Recovery package plaintext is required');
      return;
    }
    final plaintextBytes = utf8.encode(plaintext);
    if (plaintextBytes.length > _maxPlaintextBytes) {
      _showSnack('Recovery package plaintext must be 64 KiB or less');
      return;
    }

    widget.services.recordActivity();
    setState(() {
      _creatingGrant = true;
    });
    try {
      final encrypted = await _crypto.encryptPackage(
        plaintext: plaintextBytes,
        recipientPublicKey: contact.recipientPublicKey,
        recipientKeyFingerprint: contact.recipientKeyFingerprint,
      );
      _grantPlaintextController.clear();
      final request = EmergencyGrantCreateRequest(
        contactId: contact.id,
        waitingPeriodHours: waitingHours,
        encryptedRecoveryPackage: encrypted.encryptedRecoveryPackage,
        packageAad: encrypted.packageAad,
        packageFingerprint: encrypted.packageFingerprint,
      );
      await widget.services.createEmergencyGrant(request: request);
      if (!mounted) return;
      setState(() {
        _creatingGrant = false;
        _snapshot = _loadSnapshot();
      });
      await _snapshot;
    } catch (_) {
      _grantPlaintextController.clear();
      if (!mounted) return;
      setState(() {
        _creatingGrant = false;
      });
      _showSnack('Grant creation failed');
    }
  }

  Future<void> _acceptGrant(EmergencyGrant grant) async {
    final fingerprint = await _promptText(
      title: 'Accept emergency grant',
      label: 'Recipient key fingerprint',
      action: 'Accept',
      keyValue: 'emergency-accept-fingerprint-field',
    );
    if (fingerprint == null || fingerprint.trim().isEmpty) {
      return;
    }
    await _runGrantAction(
      grant.id,
      () => widget.services.acceptEmergencyGrant(
        grantId: grant.id,
        recipientKeyFingerprint: fingerprint.trim(),
      ),
      failureMessage: 'Grant accept failed',
    );
  }

  Future<void> _requestGrantAccess(EmergencyGrant grant) {
    return _runGrantAction(
      grant.id,
      () => widget.services.requestEmergencyGrantAccess(grantId: grant.id),
      failureMessage: 'Access request failed',
    );
  }

  Future<void> _cancelGrant(EmergencyGrant grant) async {
    final confirmed = await _confirm(
      title: 'Cancel request',
      message: 'Cancel the pending emergency access request?',
      action: 'Cancel request',
    );
    if (!confirmed) {
      return;
    }
    await _runGrantAction(
      grant.id,
      () => widget.services.cancelEmergencyGrant(grant.id),
      failureMessage: 'Cancel failed',
    );
  }

  Future<void> _revokeGrant(EmergencyGrant grant) async {
    final confirmed = await _confirm(
      title: 'Revoke grant',
      message: 'Revoke this emergency grant?',
      action: 'Revoke',
    );
    if (!confirmed) {
      return;
    }
    await _runGrantAction(
      grant.id,
      () => widget.services.revokeEmergencyGrant(grant.id),
      failureMessage: 'Grant revoke failed',
    );
  }

  Future<void> _downloadGrant(EmergencyGrant grant) async {
    if (_busyGrantIds.contains(grant.id)) {
      return;
    }
    widget.services.recordActivity();
    setState(() {
      _busyGrantIds.add(grant.id);
    });
    try {
      final package = await widget.services.downloadEmergencyAccessPackage(
        grant.id,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) =>
            _EmergencyPackageDialog(package: package, crypto: _crypto),
      );
    } catch (_) {
      _showSnack('Package download failed');
    } finally {
      if (mounted) {
        setState(() {
          _busyGrantIds.remove(grant.id);
        });
      }
    }
  }

  Future<void> _runGrantAction(
    String grantId,
    Future<EmergencyGrant> Function() action, {
    required String failureMessage,
  }) async {
    if (_busyGrantIds.contains(grantId)) {
      return;
    }
    widget.services.recordActivity();
    setState(() {
      _busyGrantIds.add(grantId);
    });
    try {
      await action();
      await _refresh();
    } catch (_) {
      _showSnack(failureMessage);
    } finally {
      if (mounted) {
        setState(() {
          _busyGrantIds.remove(grantId);
        });
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _promptText({
    required String title,
    required String label,
    required String action,
    required String keyValue,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: ValueKey(keyValue),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.clear();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text;
              controller.clear();
              Navigator.of(context).pop(value);
            },
            child: Text(action),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SecureVisualBackground(
      key: const ValueKey('emergency-access-page'),
      bottomInset: 64,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: FutureBuilder<_EmergencySnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              children: [
                SecureReplicaHeader(
                  title: 'Emergency Access',
                  subtitle:
                      'Manage recovery contacts, encrypted grants, and local recipient package decryption.',
                  leading: IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  trailing: IconButton(
                    tooltip: 'Refresh',
                    onPressed: snapshot.connectionState == ConnectionState.done
                        ? _refresh
                        : null,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
                const SizedBox(height: 18),
                if (data == null)
                  const _LoadingCard()
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 860;
                      final setupCards = [
                        _KeyPairCard(
                          keyPair: _generatedKeyPair,
                          isGenerating: _generatingKeyPair,
                          onGenerate: _generateKeyPair,
                          onCopy: _copyLocalValue,
                        ),
                        _CreateContactCard(
                          emailController: _emailController,
                          publicKeyController: _publicKeyController,
                          fingerprintController: _fingerprintController,
                          labelController: _labelController,
                          isCreating: _creatingContact,
                          onCreate: _createContact,
                        ),
                      ];
                      return Column(
                        children: [
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: setupCards.first),
                                const SizedBox(width: 12),
                                Expanded(child: setupCards.last),
                              ],
                            )
                          else
                            Column(
                              children: [
                                setupCards.first,
                                const SizedBox(height: 12),
                                setupCards.last,
                              ],
                            ),
                          const SizedBox(height: 12),
                          _CreateGrantCard(
                            contacts: data.activeContacts,
                            selectedContactId: _selectedContactId,
                            plaintextController: _grantPlaintextController,
                            waitingHoursController: _waitingHoursController,
                            isCreating: _creatingGrant,
                            onContactChanged: (value) {
                              setState(() {
                                _selectedContactId = value;
                              });
                            },
                            onCreate: () => _createGrant(data.activeContacts),
                          ),
                          const SizedBox(height: 12),
                          _ContactsCard(
                            contacts: data.contacts,
                            error: data.contactsError,
                            busyContactIds: _busyContactIds,
                            onRevoke: _revokeContact,
                          ),
                          const SizedBox(height: 12),
                          _GrantsCard(
                            grants: data.grants,
                            error: data.grantsError,
                            busyGrantIds: _busyGrantIds,
                            onAccept: _acceptGrant,
                            onRequestAccess: _requestGrantAccess,
                            onCancel: _cancelGrant,
                            onRevoke: _revokeGrant,
                            onDownload: _downloadGrant,
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _copyLocalValue(String value) async {
    try {
      final copied = await widget.services.copySensitiveTemporary(value);
      _showSnack(copied ? 'Copied locally' : 'Copy failed');
    } catch (_) {
      _showSnack('Copy unavailable');
    }
  }
}

class _EmergencySnapshot {
  const _EmergencySnapshot({
    required this.contacts,
    required this.contactsError,
    required this.grants,
    required this.grantsError,
  });

  final List<EmergencyContact>? contacts;
  final Object? contactsError;
  final List<EmergencyGrant>? grants;
  final Object? grantsError;

  List<EmergencyContact> get activeContacts =>
      contacts?.where((contact) => contact.status == 'active').toList() ??
      const <EmergencyContact>[];
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const SecureGlassCard(
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          SizedBox(width: 12),
          Text('Loading emergency access'),
        ],
      ),
    );
  }
}

class _KeyPairCard extends StatelessWidget {
  const _KeyPairCard({
    required this.keyPair,
    required this.isGenerating,
    required this.onGenerate,
    required this.onCopy,
  });

  final EmergencyKeyPairBundle? keyPair;
  final bool isGenerating;
  final VoidCallback onGenerate;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final keyPair = this.keyPair;
    return SecureGlassCard(
      borderRadius: 16,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.key_rounded,
            title: 'Recipient setup key',
            detail:
                'Generate locally for a recipient. Public key and fingerprint can be shared; private key stays local.',
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('emergency-generate-keypair-button'),
            onPressed: isGenerating ? null : onGenerate,
            icon: isGenerating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high_rounded),
            label: const Text('Generate local key pair'),
          ),
          if (keyPair != null) ...[
            const SizedBox(height: 14),
            _TokenRow(
              label: 'Public key',
              value: keyPair.publicKey,
              onCopy: () => onCopy(keyPair.publicKey),
            ),
            _TokenRow(
              label: 'Fingerprint',
              value: keyPair.fingerprint,
              onCopy: () => onCopy(keyPair.fingerprint),
            ),
            _TokenRow(
              label: 'Private key (local only)',
              value: keyPair.privateKey,
            ),
          ],
        ],
      ),
    );
  }
}

class _CreateContactCard extends StatelessWidget {
  const _CreateContactCard({
    required this.emailController,
    required this.publicKeyController,
    required this.fingerprintController,
    required this.labelController,
    required this.isCreating,
    required this.onCreate,
  });

  final TextEditingController emailController;
  final TextEditingController publicKeyController;
  final TextEditingController fingerprintController;
  final TextEditingController labelController;
  final bool isCreating;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SecureGlassCard(
      borderRadius: 16,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Create contact',
            detail:
                'Register recipient email, public key, and fingerprint. No master password or private key is collected.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('emergency-contact-email-field'),
            controller: emailController,
            decoration: const InputDecoration(labelText: 'Recipient email'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('emergency-contact-public-key-field'),
            controller: publicKeyController,
            decoration: const InputDecoration(
              labelText: 'Recipient public key',
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('emergency-contact-fingerprint-field'),
            controller: fingerprintController,
            decoration: const InputDecoration(
              labelText: 'Recipient key fingerprint',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('emergency-contact-label-field'),
            controller: labelController,
            decoration: const InputDecoration(labelText: 'Label (optional)'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('emergency-create-contact-button'),
              onPressed: isCreating ? null : onCreate,
              icon: isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded),
              label: const Text('Create contact'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateGrantCard extends StatelessWidget {
  const _CreateGrantCard({
    required this.contacts,
    required this.selectedContactId,
    required this.plaintextController,
    required this.waitingHoursController,
    required this.isCreating,
    required this.onContactChanged,
    required this.onCreate,
  });

  final List<EmergencyContact> contacts;
  final String? selectedContactId;
  final TextEditingController plaintextController;
  final TextEditingController waitingHoursController;
  final bool isCreating;
  final ValueChanged<String?> onContactChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SecureGlassCard(
      borderRadius: 16,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.enhanced_encryption_rounded,
            title: 'Create encrypted grant',
            detail:
                'Paste a local recovery package, encrypt to an active contact, then upload only the encrypted envelope.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('emergency-grant-contact-dropdown'),
            initialValue: selectedContactId,
            items: [
              for (final contact in contacts)
                DropdownMenuItem<String>(
                  value: contact.id,
                  child: Text(
                    _contactTitle(contact),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: isCreating || contacts.isEmpty ? null : onContactChanged,
            decoration: const InputDecoration(labelText: 'Active contact'),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('emergency-grant-wait-hours-field'),
            controller: waitingHoursController,
            decoration: const InputDecoration(
              labelText: 'Waiting period (hours)',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('emergency-grant-plaintext-field'),
            controller: plaintextController,
            decoration: const InputDecoration(
              labelText: 'Local recovery package plaintext',
              helperText: '64 KiB max. Cleared after submit.',
            ),
            minLines: 3,
            maxLines: 6,
            maxLength: _EmergencyAccessPageState._maxPlaintextBytes,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('emergency-create-grant-button'),
              onPressed: isCreating || contacts.isEmpty ? null : onCreate,
              icon: isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_rounded),
              label: const Text('Encrypt and create grant'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactsCard extends StatelessWidget {
  const _ContactsCard({
    required this.contacts,
    required this.error,
    required this.busyContactIds,
    required this.onRevoke,
  });

  final List<EmergencyContact>? contacts;
  final Object? error;
  final Set<String> busyContactIds;
  final ValueChanged<EmergencyContact> onRevoke;

  @override
  Widget build(BuildContext context) {
    final contacts = this.contacts;
    return SecureGlassCard(
      borderRadius: 16,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.contacts_rounded,
            title: 'Contacts',
            detail: 'Stored recipient metadata only.',
          ),
          const SizedBox(height: 12),
          if (contacts == null)
            const Text('Emergency contacts unavailable')
          else if (contacts.isEmpty)
            const Text('No emergency contacts')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: contacts.length,
              separatorBuilder: (context, index) => const Divider(height: 22),
              itemBuilder: (context, index) {
                final contact = contacts[index];
                final busy = busyContactIds.contains(contact.id);
                return _ContactListItem(
                  key: ValueKey('emergency-contact-${contact.id}'),
                  contact: contact,
                  busy: busy,
                  onRevoke: contact.status == 'revoked' || busy
                      ? null
                      : () => onRevoke(contact),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ContactListItem extends StatelessWidget {
  const _ContactListItem({
    super.key,
    required this.contact,
    required this.busy,
    required this.onRevoke,
  });

  final EmergencyContact contact;
  final bool busy;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SmallIcon(icon: Icons.contact_emergency_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contact.recipientEmail ?? contact.id,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: SecureVisualColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (contact.recipientLabel != null) contact.recipientLabel!,
                  contact.status,
                  contact.recipientKeyFingerprint,
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: SecureVisualColors.muted,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          key: ValueKey('emergency-revoke-contact-${contact.id}'),
          onPressed: onRevoke,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.block_rounded),
          label: const Text('Revoke'),
        ),
      ],
    );
  }
}

class _GrantsCard extends StatelessWidget {
  const _GrantsCard({
    required this.grants,
    required this.error,
    required this.busyGrantIds,
    required this.onAccept,
    required this.onRequestAccess,
    required this.onCancel,
    required this.onRevoke,
    required this.onDownload,
  });

  final List<EmergencyGrant>? grants;
  final Object? error;
  final Set<String> busyGrantIds;
  final ValueChanged<EmergencyGrant> onAccept;
  final ValueChanged<EmergencyGrant> onRequestAccess;
  final ValueChanged<EmergencyGrant> onCancel;
  final ValueChanged<EmergencyGrant> onRevoke;
  final ValueChanged<EmergencyGrant> onDownload;

  @override
  Widget build(BuildContext context) {
    final grants = this.grants;
    return SecureGlassCard(
      borderRadius: 16,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.assignment_turned_in_outlined,
            title: 'Grants',
            detail:
                'Metadata view only. Encrypted package bytes appear only after explicit download.',
          ),
          const SizedBox(height: 12),
          if (grants == null)
            const Text('Emergency grants unavailable')
          else if (grants.isEmpty)
            const Text('No emergency grants')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: grants.length,
              separatorBuilder: (context, index) => const Divider(height: 22),
              itemBuilder: (context, index) {
                final grant = grants[index];
                return _GrantListItem(
                  key: ValueKey('emergency-grant-${grant.id}'),
                  grant: grant,
                  busy: busyGrantIds.contains(grant.id),
                  onAccept: onAccept,
                  onRequestAccess: onRequestAccess,
                  onCancel: onCancel,
                  onRevoke: onRevoke,
                  onDownload: onDownload,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _GrantListItem extends StatelessWidget {
  const _GrantListItem({
    super.key,
    required this.grant,
    required this.busy,
    required this.onAccept,
    required this.onRequestAccess,
    required this.onCancel,
    required this.onRevoke,
    required this.onDownload,
  });

  final EmergencyGrant grant;
  final bool busy;
  final ValueChanged<EmergencyGrant> onAccept;
  final ValueChanged<EmergencyGrant> onRequestAccess;
  final ValueChanged<EmergencyGrant> onCancel;
  final ValueChanged<EmergencyGrant> onRevoke;
  final ValueChanged<EmergencyGrant> onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terminal = grant.status == 'revoked' || grant.status == 'cancelled';
    final canDownload = _canDownloadGrantPackage(grant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SmallIcon(icon: Icons.assignment_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${grant.id} · ${grant.status}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: SecureVisualColors.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${grant.waitingPeriodHours}h wait · ${grant.packageFingerprint}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: SecureVisualColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (grant.status == 'pending_acceptance')
              OutlinedButton.icon(
                key: ValueKey('emergency-accept-grant-${grant.id}'),
                onPressed: busy ? null : () => onAccept(grant),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Accept'),
              ),
            if (grant.status == 'active')
              OutlinedButton.icon(
                key: ValueKey('emergency-request-grant-${grant.id}'),
                onPressed: busy ? null : () => onRequestAccess(grant),
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Request access'),
              ),
            if (grant.status == 'access_requested')
              OutlinedButton.icon(
                key: ValueKey('emergency-cancel-grant-${grant.id}'),
                onPressed: busy ? null : () => onCancel(grant),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel'),
              ),
            if (canDownload)
              FilledButton.icon(
                key: ValueKey('emergency-download-grant-${grant.id}'),
                onPressed: busy ? null : () => onDownload(grant),
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('Download'),
              ),
            if (!terminal)
              TextButton.icon(
                key: ValueKey('emergency-revoke-grant-${grant.id}'),
                onPressed: busy ? null : () => onRevoke(grant),
                icon: const Icon(Icons.block_rounded),
                label: const Text('Revoke'),
              ),
          ],
        ),
      ],
    );
  }
}

bool _canDownloadGrantPackage(EmergencyGrant grant) {
  final readyAtValue = grant.readyAt;
  if (readyAtValue != null) {
    final readyAt = DateTime.tryParse(readyAtValue)?.toUtc();
    if (readyAt == null || readyAt.isAfter(DateTime.now().toUtc())) {
      return false;
    }
  }

  if (grant.status == 'ready_for_download') {
    return true;
  }
  return grant.status == 'access_requested' && readyAtValue != null;
}

class _EmergencyPackageDialog extends StatefulWidget {
  const _EmergencyPackageDialog({required this.package, required this.crypto});

  final EmergencyAccessPackage package;
  final EmergencyCryptoService crypto;

  @override
  State<_EmergencyPackageDialog> createState() =>
      _EmergencyPackageDialogState();
}

class _EmergencyPackageDialogState extends State<_EmergencyPackageDialog> {
  final TextEditingController _privateKeyController = TextEditingController();
  String? _decryptedText;
  bool _decrypting = false;

  @override
  void dispose() {
    _privateKeyController.clear();
    _privateKeyController.dispose();
    _decryptedText = null;
    super.dispose();
  }

  Future<void> _decrypt() async {
    if (_decrypting) {
      return;
    }
    final privateKey = _privateKeyController.text.trim();
    if (privateKey.isEmpty) {
      return;
    }
    setState(() {
      _decrypting = true;
      _decryptedText = null;
    });
    try {
      final plaintext = await widget.crypto.decryptPackage(
        encryptedRecoveryPackage: widget.package.encryptedRecoveryPackage,
        packageAad: widget.package.packageAad,
        packageFingerprint: widget.package.packageFingerprint,
        recipientPrivateKey: privateKey,
      );
      _privateKeyController.clear();
      if (!mounted) return;
      setState(() {
        _decryptedText = utf8.decode(plaintext);
        _decrypting = false;
      });
    } catch (_) {
      _privateKeyController.clear();
      if (!mounted) return;
      setState(() {
        _decrypting = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Local decrypt failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final package = widget.package;
    return AlertDialog(
      title: const Text('Emergency package'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DialogToken(label: 'Grant', value: package.grantId),
              _DialogToken(
                label: 'Package fingerprint',
                value: package.packageFingerprint,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('emergency-package-private-key-field'),
                controller: _privateKeyController,
                decoration: const InputDecoration(
                  labelText: 'Recipient private key (local only)',
                ),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey('emergency-local-decrypt-package-button'),
                  onPressed: _decrypting ? null : _decrypt,
                  icon: _decrypting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open_rounded),
                  label: const Text('Decrypt locally'),
                ),
              ),
              if (_decryptedText != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Decrypted package',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                SelectableText(_decryptedText!),
              ],
              const SizedBox(height: 12),
              _DialogToken(label: 'Package AAD', value: package.packageAad),
              _DialogToken(
                label: 'Encrypted package envelope',
                value: package.encryptedRecoveryPackage,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _privateKeyController.clear();
            setState(() {
              _decryptedText = null;
            });
            Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SmallIcon(icon: icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: SecureVisualColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: SecureVisualColors.text.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SmallIcon extends StatelessWidget {
  const _SmallIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: SecureVisualColors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: SecureVisualColors.blue, size: 20),
    );
  }
}

class _TokenRow extends StatelessWidget {
  const _TokenRow({required this.label, required this.value, this.onCopy});

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              if (onCopy != null)
                IconButton(
                  tooltip: 'Copy',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialogToken extends StatelessWidget {
  const _DialogToken({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 3),
          SelectableText(value),
        ],
      ),
    );
  }
}

String _contactTitle(EmergencyContact contact) {
  final label = contact.recipientLabel;
  if (label != null && label.trim().isNotEmpty) {
    return '${contact.recipientEmail ?? contact.id} · $label';
  }
  return contact.recipientEmail ?? contact.id;
}

String? _emptyToNull(String value) => value.isEmpty ? null : value;
