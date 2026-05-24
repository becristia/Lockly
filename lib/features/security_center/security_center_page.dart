import 'dart:async';

import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/backup/backup_service.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/data/db/sync_state_dao.dart';
import 'package:secure_box/features/emergency_access/emergency_access_page.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class SecurityCenterPage extends StatefulWidget {
  const SecurityCenterPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SecurityCenterPage> createState() => _SecurityCenterPageState();
}

class _SecurityCenterPageState extends State<SecurityCenterPage> {
  late Future<_SecurityCenterSnapshot> _snapshot;
  HealthReport? _healthReport;
  bool _healthLoading = false;
  Object? _healthError;

  @override
  void initState() {
    super.initState();
    _snapshot = _loadSnapshot();
  }

  Future<_SecurityCenterSnapshot> _loadSnapshot() async {
    List<SyncConflictRecord>? conflicts;
    List<SyncBlobConflictRecord>? blobConflicts;
    Object? conflictError;
    List<SyncDevice>? devices;
    Object? deviceError;
    List<EmergencyContact>? emergencyContacts;
    Object? emergencyContactsError;
    List<EmergencyGrant>? emergencyGrants;
    Object? emergencyGrantsError;

    try {
      conflicts = await widget.services.listSyncConflicts();
      blobConflicts = await widget.services.listSyncBlobConflicts();
    } catch (error) {
      conflictError = error;
    }

    try {
      devices = await widget.services.listCloudSyncDevices();
    } catch (error) {
      deviceError = error;
    }

    try {
      emergencyContacts = await widget.services.listEmergencyContacts();
    } catch (error) {
      emergencyContactsError = error;
    }

    try {
      emergencyGrants = await widget.services.listEmergencyGrants();
    } catch (error) {
      emergencyGrantsError = error;
    }

    return _SecurityCenterSnapshot(
      conflicts: conflicts,
      blobConflicts: blobConflicts,
      conflictError: conflictError,
      devices: devices,
      deviceError: deviceError,
      emergencyContacts: emergencyContacts,
      emergencyContactsError: emergencyContactsError,
      emergencyGrants: emergencyGrants,
      emergencyGrantsError: emergencyGrantsError,
    );
  }

  Future<void> _refresh() async {
    widget.services.recordActivity();
    setState(() {
      _snapshot = _loadSnapshot();
    });
    await _snapshot;
  }

  Future<void> _analyzeHealth() async {
    widget.services.recordActivity();
    setState(() {
      _healthLoading = true;
      _healthError = null;
    });
    try {
      final report = await widget.services.analyzePasswordHealth();
      if (!mounted) return;
      setState(() {
        _healthReport = report;
        _healthLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _healthLoading = false;
        _healthError = error;
      });
    }
  }

  Future<void> _showSyncConflicts(
    List<SyncConflictRecord> conflicts,
    List<SyncBlobConflictRecord> blobConflicts,
  ) {
    widget.services.recordActivity();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Sync conflicts'),
          content: SizedBox(
            width: 520,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final conflict in conflicts) ...[
                    _SyncConflictListItem(conflict: conflict),
                    const Divider(height: 20),
                  ],
                  for (final conflict in blobConflicts) ...[
                    _SyncBlobConflictListItem(conflict: conflict),
                    const Divider(height: 20),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(_downloadLatestEncryptedVault());
              },
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Download latest encrypted vault'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadLatestEncryptedVault() async {
    final masterPassword = await _promptForMasterPassword();
    if (masterPassword == null) {
      return;
    }
    widget.services.recordActivity();
    final confirmed = await widget.services.unlockWithMasterPassword(
      masterPassword,
    );
    if (!confirmed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Master password confirmation failed')),
      );
      return;
    }

    try {
      await widget.services.downloadCloudEncryptedVault(
        masterPassword: masterPassword,
        mode: BackupImportMode.merge,
      );
      if (!mounted) return;
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cloud download failed')));
    }
  }

  Future<String?> _promptForMasterPassword() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => const _MasterPasswordDialog(),
    );
  }

  Future<void> _openEmergencyAccess() async {
    widget.services.recordActivity();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EmergencyAccessPage(services: widget.services),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SecureVisualBackground(
      key: const ValueKey('security-center-page'),
      bottomInset: 84,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: FutureBuilder<_SecurityCenterSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              children: [
                SecureReplicaHeader(
                  title: 'Security Center',
                  subtitle: 'Vault security overview',
                  trailing: IconButton(
                    tooltip: 'Refresh',
                    onPressed: snapshot.connectionState == ConnectionState.done
                        ? _refresh
                        : null,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
                const SizedBox(height: 18),
                if (data == null) ...[
                  const _LoadingCard(),
                ] else ...[
                  _PasswordHealthCard(
                    key: const ValueKey('security-center-health-card'),
                    report: _healthReport,
                    isLoading: _healthLoading,
                    error: _healthError,
                    onAnalyze: _analyzeHealth,
                  ),
                  const SizedBox(height: 12),
                  _CloudSyncCard(
                    key: const ValueKey('security-center-conflicts-card'),
                    conflicts: data.conflicts,
                    blobConflicts: data.blobConflicts,
                    error: data.conflictError,
                    onOpenConflicts:
                        data.conflicts == null || data.blobConflicts == null
                        ? null
                        : () => _showSyncConflicts(
                            data.conflicts!,
                            data.blobConflicts!,
                          ),
                  ),
                  const SizedBox(height: 12),
                  _DeviceTrustCard(
                    key: const ValueKey('security-center-devices-card'),
                    devices: data.devices,
                    error: data.deviceError,
                  ),
                  const SizedBox(height: 12),
                  _EmergencyAccessCard(
                    key: const ValueKey('security-center-emergency-card'),
                    contacts: data.emergencyContacts,
                    contactsError: data.emergencyContactsError,
                    grants: data.emergencyGrants,
                    grantsError: data.emergencyGrantsError,
                    onOpen: _openEmergencyAccess,
                  ),
                  const SizedBox(height: 18),
                  _RoadmapGrid(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MasterPasswordDialog extends StatefulWidget {
  const _MasterPasswordDialog();

  @override
  State<_MasterPasswordDialog> createState() => _MasterPasswordDialogState();
}

class _MasterPasswordDialogState extends State<_MasterPasswordDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm master password'),
      content: TextField(
        key: const ValueKey('sync-conflict-master-password-field'),
        controller: _controller,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Master password'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Download')),
      ],
    );
  }
}

class _SecurityCenterSnapshot {
  const _SecurityCenterSnapshot({
    required this.conflicts,
    required this.blobConflicts,
    required this.conflictError,
    required this.devices,
    required this.deviceError,
    required this.emergencyContacts,
    required this.emergencyContactsError,
    required this.emergencyGrants,
    required this.emergencyGrantsError,
  });

  final List<SyncConflictRecord>? conflicts;
  final List<SyncBlobConflictRecord>? blobConflicts;
  final Object? conflictError;
  final List<SyncDevice>? devices;
  final Object? deviceError;
  final List<EmergencyContact>? emergencyContacts;
  final Object? emergencyContactsError;
  final List<EmergencyGrant>? emergencyGrants;
  final Object? emergencyGrantsError;
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
          Text('Loading security posture'),
        ],
      ),
    );
  }
}

class _PasswordHealthCard extends StatelessWidget {
  const _PasswordHealthCard({
    super.key,
    required this.report,
    required this.isLoading,
    required this.onAnalyze,
    this.error,
  });

  final HealthReport? report;
  final bool isLoading;
  final VoidCallback onAnalyze;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final report = this.report;
    if (isLoading) {
      return const _StatusCard(
        icon: Icons.health_and_safety_outlined,
        title: 'Password health',
        headline: 'Checking local vault',
        detail: 'Decrypting happens locally for this explicit check only.',
        tone: SecureVisualColors.blue,
        action: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    if (report == null) {
      return _StatusCard(
        icon: Icons.health_and_safety_outlined,
        title: 'Password health',
        headline: error == null ? 'Local check not run' : 'Local check failed',
        detail: error == null
            ? 'Run an explicit on-device check before decrypting saved items for analysis.'
            : 'The vault stayed local; try again after confirming it is unlocked.',
        tone: error == null
            ? SecureVisualColors.blue
            : SecureVisualColors.warning,
        action: OutlinedButton.icon(
          onPressed: onAnalyze,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Run local check'),
        ),
      );
    }

    final weak = report.categoryCounts[HealthCategory.weak] ?? 0;
    final reused = report.categoryCounts[HealthCategory.reused] ?? 0;
    final stale = report.categoryCounts[HealthCategory.stale] ?? 0;
    final headline = '${report.score}/100 health score';
    final detail = report.findings.isEmpty
        ? '${report.totalItems} saved items checked locally.'
        : '$weak weak, $reused reused, $stale stale passwords found locally.';

    return _StatusCard(
      icon: Icons.health_and_safety_outlined,
      title: 'Password health',
      headline: headline,
      detail: detail,
      tone: report.score >= 80
          ? SecureVisualColors.success
          : SecureVisualColors.warning,
      action: TextButton.icon(
        onPressed: onAnalyze,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Run again'),
      ),
    );
  }
}

class _CloudSyncCard extends StatelessWidget {
  const _CloudSyncCard({
    super.key,
    required this.conflicts,
    required this.blobConflicts,
    this.error,
    this.onOpenConflicts,
  });

  final List<SyncConflictRecord>? conflicts;
  final List<SyncBlobConflictRecord>? blobConflicts;
  final Object? error;
  final VoidCallback? onOpenConflicts;

  @override
  Widget build(BuildContext context) {
    final conflicts = this.conflicts;
    final blobConflicts = this.blobConflicts;
    if (conflicts == null || blobConflicts == null) {
      return _StatusCard(
        icon: Icons.cloud_sync_outlined,
        title: 'Cloud sync',
        headline: 'Conflict state unavailable',
        detail: 'Cloud sync is not connected or local sync state is missing.',
        tone: SecureVisualColors.warning,
      );
    }

    final count = conflicts.length + blobConflicts.length;
    return _StatusCard(
      icon: Icons.cloud_sync_outlined,
      title: 'Cloud sync',
      headline: count == 0
          ? 'No unresolved conflicts'
          : '$count unresolved ${count == 1 ? 'conflict' : 'conflicts'}',
      detail: count == 0
          ? 'Local encrypted sync state has no pending conflict records.'
          : 'Review safe metadata and download the latest encrypted vault when ready.',
      tone: count == 0 ? SecureVisualColors.success : SecureVisualColors.danger,
      onTap: count == 0 ? null : onOpenConflicts,
      action: count == 0
          ? null
          : TextButton.icon(
              onPressed: onOpenConflicts,
              icon: const Icon(Icons.list_alt_rounded),
              label: const Text('Review conflicts'),
            ),
    );
  }
}

class _SyncConflictListItem extends StatelessWidget {
  const _SyncConflictListItem({required this.conflict});

  final SyncConflictRecord conflict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          conflict.itemId,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            Text('Local revision ${conflict.clientRevision}'),
            Text('Cloud revision ${conflict.serverRevision}'),
            Text('Local timestamp ${conflict.createdAt}'),
          ],
        ),
      ],
    );
  }
}

class _SyncBlobConflictListItem extends StatelessWidget {
  const _SyncBlobConflictListItem({required this.conflict});

  final SyncBlobConflictRecord conflict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Encrypted blob',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          conflict.blobId,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            Text('Local revision ${conflict.clientRevision}'),
            Text('Cloud revision ${conflict.serverRevision}'),
            Text('Local timestamp ${conflict.createdAt}'),
          ],
        ),
      ],
    );
  }
}

class _DeviceTrustCard extends StatelessWidget {
  const _DeviceTrustCard({super.key, required this.devices, this.error});

  final List<SyncDevice>? devices;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final devices = this.devices;
    if (devices == null) {
      return _StatusCard(
        icon: Icons.devices_other_outlined,
        title: 'Device trust',
        headline: 'Device list unavailable',
        detail: 'Sign in to cloud sync to review trusted devices.',
        tone: SecureVisualColors.warning,
      );
    }

    final active = devices.where((device) => device.revokedAt == null).length;
    final revoked = devices.length - active;
    final trusted = devices
        .where((device) => device.revokedAt == null && device.trusted)
        .length;
    final untrusted = devices
        .where((device) => device.revokedAt == null && !device.trusted)
        .length;
    final missingMetadata = devices
        .where(
          (device) =>
              device.revokedAt == null &&
              (_isBlank(device.platform) || _isBlank(device.clientVersion)),
        )
        .length;
    final staleSync = devices
        .where(
          (device) =>
              device.revokedAt == null && _isStaleSync(device.lastSyncAt),
        )
        .length;
    final riskCount = untrusted + missingMetadata + staleSync;
    return _StatusCard(
      icon: Icons.devices_other_outlined,
      title: 'Device trust',
      headline: active == 0
          ? 'No cloud devices connected'
          : '$trusted of $active active devices trusted',
      detail: active == 0
          ? 'Cloud sync can register this device when you sign in.'
          : '$revoked revoked, $riskCount risk ${riskCount == 1 ? 'indicator' : 'indicators'}: '
                '$untrusted untrusted, $missingMetadata missing metadata, $staleSync stale sync.',
      tone: riskCount == 0
          ? SecureVisualColors.success
          : untrusted > 0
          ? SecureVisualColors.danger
          : SecureVisualColors.warning,
    );
  }
}

class _EmergencyAccessCard extends StatelessWidget {
  const _EmergencyAccessCard({
    super.key,
    required this.contacts,
    required this.grants,
    required this.onOpen,
    this.contactsError,
    this.grantsError,
  });

  final List<EmergencyContact>? contacts;
  final Object? contactsError;
  final List<EmergencyGrant>? grants;
  final Object? grantsError;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final contacts = this.contacts;
    final grants = this.grants;
    if (contacts == null || grants == null) {
      return _StatusCard(
        icon: Icons.contact_emergency_outlined,
        title: 'Emergency access',
        headline: 'Emergency access unavailable',
        detail:
            'Cloud sync is not connected or emergency metadata is unavailable.',
        tone: SecureVisualColors.warning,
        action: TextButton.icon(
          key: const ValueKey('security-center-manage-emergency-access'),
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Manage'),
        ),
      );
    }

    final activeContacts = contacts
        .where((contact) => contact.status == 'active')
        .length;
    final pendingGrants = grants
        .where(
          (grant) =>
              grant.status != 'revoked' &&
              grant.status != 'cancelled' &&
              grant.status != 'downloaded',
        )
        .length;
    return _StatusCard(
      icon: Icons.contact_emergency_outlined,
      title: 'Emergency access',
      headline:
          '$activeContacts active ${activeContacts == 1 ? 'contact' : 'contacts'}',
      detail:
          '$pendingGrants ${pendingGrants == 1 ? 'grant' : 'grants'} configured for delayed recovery.',
      tone: activeContacts > 0
          ? SecureVisualColors.success
          : SecureVisualColors.blue,
      onTap: onOpen,
      action: TextButton.icon(
        key: const ValueKey('security-center-manage-emergency-access'),
        onPressed: onOpen,
        icon: const Icon(Icons.open_in_new_rounded),
        label: const Text('Manage'),
      ),
    );
  }
}

bool _isBlank(String? value) => value == null || value.trim().isEmpty;

bool _isStaleSync(String? value) {
  if (_isBlank(value)) {
    return true;
  }
  final parsed = DateTime.tryParse(value!);
  if (parsed == null) {
    return true;
  }
  return parsed.toUtc().isBefore(
    DateTime.now().toUtc().subtract(const Duration(days: 30)),
  );
}

class _RoadmapGrid extends StatelessWidget {
  const _RoadmapGrid();

  @override
  Widget build(BuildContext context) {
    final items = const [
      _RoadmapItem(
        keyValue: 'security-center-migration',
        icon: Icons.move_up_rounded,
        title: 'Migration',
        detail: 'Guided importer and export checks.',
      ),
      _RoadmapItem(
        keyValue: 'security-center-autofill',
        icon: Icons.password_rounded,
        title: 'Autofill',
        detail: 'System autofill posture and setup status.',
      ),
      _RoadmapItem(
        keyValue: 'security-center-attachments',
        icon: Icons.attach_file_rounded,
        title: 'Attachments',
        detail: 'Encrypted file storage readiness.',
      ),
      _RoadmapItem(
        keyValue: 'security-center-passkeys',
        icon: Icons.key_rounded,
        title: 'Passkeys',
        detail: 'Passkey vault support entry point.',
      ),
      _RoadmapItem(
        keyValue: 'security-center-emergency-access',
        icon: Icons.contact_emergency_outlined,
        title: 'Emergency',
        detail: 'Recovery contacts and delayed access.',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          childAspectRatio: columns == 1 ? 4.2 : 3.8,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: items,
        );
      },
    );
  }
}

class _RoadmapItem extends StatelessWidget {
  const _RoadmapItem({
    required this.keyValue,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final String keyValue;
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SecureGlassCard(
      key: ValueKey(keyValue),
      borderRadius: 14,
      padding: const EdgeInsets.all(14),
      shadow: false,
      child: Row(
        children: [
          _IconTile(icon: icon, color: SecureVisualColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: SecureVisualColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: SecureVisualColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.headline,
    required this.detail,
    required this.tone,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String headline;
  final String detail;
  final Color tone;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = SecureGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      shadow: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: icon, color: tone),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: SecureVisualColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: SecureVisualColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: SecureVisualColors.text.withValues(alpha: 0.72),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: action!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return card;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 23),
    );
  }
}
