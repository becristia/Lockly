import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/master_password_policy.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/passkey_record.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/features/password_generator/password_generator_page.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/activity_text_form_field.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class VaultEditPage extends StatefulWidget {
  const VaultEditPage({
    super.key,
    required this.services,
    this.itemId,
    this.initialPassword,
  });

  final AppServices services;
  final String? itemId;
  final String? initialPassword;

  @override
  State<VaultEditPage> createState() => _VaultEditPageState();
}

class _VaultEditPageState extends State<VaultEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  String? _totpSecret;
  PasskeyRecord? _passkeyRecord;

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isPasswordVisible = false;
  String? _pageError;

  bool get _isEditing => widget.itemId != null;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
    if (_isEditing) {
      _loadExistingItem();
    } else if (widget.initialPassword != null) {
      _passwordController.text = widget.initialPassword!;
    }
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _titleController.clear();
    _websiteController.clear();
    _usernameController.clear();
    _passwordController.clear();
    _notesController.clear();
    _tagsController.clear();
    _isPasswordVisible = false;
    _titleController.dispose();
    _websiteController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    _totpSecret = null;
    _passkeyRecord = null;
    super.dispose();
  }

  Future<void> _loadExistingItem() async {
    setState(() {
      _isLoading = true;
      _pageError = null;
    });

    try {
      final entry = await widget.services.getVaultItem(widget.itemId!);
      if (!mounted) {
        return;
      }
      _titleController.text = entry.title;
      _websiteController.text = entry.website;
      _usernameController.text = entry.username;
      _passwordController.text = entry.password;
      _notesController.text = entry.notes;
      _tagsController.text = entry.tags.join(', ');
      _totpSecret = entry.totpSecret;
      _passkeyRecord = entry.passkey;
      setState(() => _isLoading = false);
    } on VaultItemNotFoundException {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _pageError = AppStrings.of(context).text('vaultItemMissing');
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _pageError = AppStrings.of(context).text('vaultEditLoadFailed');
      });
    }
  }

  void _onPasswordChanged() {
    setState(() {});
  }

  Future<void> _save() async {
    widget.services.recordActivity();
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    final entry = PasswordEntry(
      title: _titleController.text.trim(),
      website: _websiteController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      notes: _notesController.text.trim(),
      tags: _parseTags(_tagsController.text),
      totpSecret: _totpSecret,
      passkey: _passkeyRecord,
    );

    try {
      if (_isEditing) {
        await widget.services.updateVaultItem(widget.itemId!, entry);
      } else {
        await widget.services.createVaultItem(entry);
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on VaultItemNotFoundException {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('vaultItemMissing')),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('saveFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final title = _isEditing
        ? strings.text('editPassword')
        : strings.text('addPassword');

    return SecureVisualBackground(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          SecureReplicaHeader(
            title: title,
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            trailing: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.crop_free_rounded),
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 64),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_pageError != null)
            _EditMessage(
              title: strings.text('editUnavailable'),
              message: _pageError!,
              actionLabel: strings.retry,
              onAction: _loadExistingItem,
            )
          else
            SecureGlassCard(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              borderRadius: 28,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ActivityTextFormField(
                      controller: _titleController,
                      onActivity: widget.services.recordActivity,
                      decoration: InputDecoration(
                        labelText: strings.text('titleField'),
                        hintText: strings.text('titleHint'),
                        suffixIcon: const Icon(Icons.bookmark_border_rounded),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return strings.text('enterTitle');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ActivityTextFormField(
                      controller: _websiteController,
                      onActivity: widget.services.recordActivity,
                      decoration: InputDecoration(
                        labelText: strings.text('websiteField'),
                        hintText: strings.text('websiteHint'),
                        suffixIcon: const Icon(Icons.language_rounded),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    ActivityTextFormField(
                      controller: _usernameController,
                      onActivity: widget.services.recordActivity,
                      decoration: InputDecoration(
                        labelText: strings.text('usernameField'),
                        hintText: strings.text('usernameHint'),
                        suffixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ActivityTextFormField(
                            controller: _passwordController,
                            onActivity: widget.services.recordActivity,
                            decoration: InputDecoration(
                              labelText: strings.text('passwordField'),
                              hintText: strings.text('passwordHint'),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  widget.services.recordActivity();
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                                tooltip: _isPasswordVisible
                                    ? strings.text('hidePassword')
                                    : strings.text('showPassword'),
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            obscureText: !_isPasswordVisible,
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return strings.text('enterPassword');
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 58,
                          height: 58,
                          child: OutlinedButton(
                            onPressed: () async {
                              widget.services.recordActivity();
                              final generated = await Navigator.of(context)
                                  .push<String>(
                                    MaterialPageRoute<String>(
                                      builder: (context) =>
                                          PasswordGeneratorPage(
                                            services: widget.services,
                                            mode: PasswordGeneratorMode.picker,
                                          ),
                                    ),
                                  );
                              if (generated != null && mounted) {
                                setState(() {
                                  _passwordController.text = generated;
                                });
                              }
                            },
                            child: Tooltip(
                              message: strings.generatePassword,
                              child: const Icon(Icons.key_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _StrengthIndicator(password: _passwordController.text),
                    const SizedBox(height: 14),
                    Text(
                      strings.text('totpTwoFactor'),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (_totpSecret == null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _scanQrCode,
                              icon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 20,
                              ),
                              label: Text(
                                strings.text('scanQrCode'),
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _showManualTotpInput,
                              icon: const Icon(Icons.edit_rounded, size: 20),
                              label: Text(
                                strings.text('manualInput'),
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: SecureVisualColors.success.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: SecureVisualColors.success.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: SecureVisualColors.success,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              strings.text('totpConfigured'),
                              style: TextStyle(
                                fontSize: 13,
                                color: SecureVisualColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _totpSecret = null),
                              child: Text(
                                strings.text('remove'),
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _buildPasskeySection(theme),
                    const SizedBox(height: 14),
                    ActivityTextFormField(
                      controller: _notesController,
                      onActivity: widget.services.recordActivity,
                      decoration: InputDecoration(
                        labelText: strings.text('notesField'),
                        hintText: strings.text('addNotesHint'),
                      ),
                      keyboardType: TextInputType.multiline,
                      minLines: 5,
                      maxLines: 6,
                    ),
                    const SizedBox(height: 12),
                    ActivityTextFormField(
                      controller: _tagsController,
                      onActivity: widget.services.recordActivity,
                      decoration: InputDecoration(
                        labelText: strings.text('tagsField'),
                        hintText: strings.text('tagsHint'),
                        suffixIcon: const Icon(Icons.sell_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SecureGradientButton(
                      onPressed: _isSaving ? null : _save,
                      icon: Icons.lock_rounded,
                      height: 62,
                      label: _isSaving
                          ? strings.text('saveBusy')
                          : strings.text('save'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPasskeySection(ThemeData theme) {
    final strings = AppStrings.of(context);
    final passkey = _passkeyRecord;
    final readiness = passkey?.platformReady == true
        ? strings.text('platformApiReady')
        : strings.text('platformApiNotEnabled');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.text('passkeys'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (passkey == null)
          OutlinedButton.icon(
            key: const ValueKey('passkey-add-button'),
            onPressed: _editPasskeyRecord,
            icon: const Icon(Icons.key_rounded, size: 20),
            label: Text(strings.text('addPasskeyMetadata')),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.key_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        passkey.relyingPartyId,
                        style: theme.textTheme.bodyLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${passkey.credentialId} - $readiness',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('passkey-add-button'),
                      onPressed: _editPasskeyRecord,
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: Text(strings.text('editMetadata')),
                    ),
                    TextButton.icon(
                      key: const ValueKey('passkey-remove-button'),
                      onPressed: () {
                        widget.services.recordActivity();
                        setState(() => _passkeyRecord = null);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text(strings.text('remove')),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _editPasskeyRecord() async {
    widget.services.recordActivity();
    final record = await showDialog<PasskeyRecord>(
      context: context,
      builder: (context) => _PasskeyRecordDialog(
        initialRecord: _passkeyRecord,
        onActivity: widget.services.recordActivity,
      ),
    );
    if (record == null || !mounted) {
      return;
    }
    setState(() => _passkeyRecord = record);
  }

  void _showManualTotpInput() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.of(ctx).text('enterTotpSecret')),
        content: TextField(
          controller: controller,
          autofocus: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: AppStrings.of(ctx).text('totpSecretHint'),
            helperText: AppStrings.of(ctx).text('totpSecretHelper'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.of(ctx).text('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final raw = controller.text.toUpperCase().replaceAll(
                RegExp(r'[^A-Z2-7]'),
                '',
              );
              if (raw.isNotEmpty) {
                setState(() => _totpSecret = raw);
              }
              Navigator.pop(ctx);
            },
            child: Text(AppStrings.of(ctx).text('confirm')),
          ),
        ],
      ),
    );
  }

  void _scanQrCode() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context).text('cameraPermissionRequired')),
      ),
    );
  }

  static List<String> _parseTags(String rawText) {
    return rawText
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }
}

class _PasskeyRecordDialog extends StatefulWidget {
  const _PasskeyRecordDialog({
    required this.initialRecord,
    required this.onActivity,
  });

  final PasskeyRecord? initialRecord;
  final VoidCallback onActivity;

  @override
  State<_PasskeyRecordDialog> createState() => _PasskeyRecordDialogState();
}

class _PasskeyRecordDialogState extends State<_PasskeyRecordDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _relyingPartyIdController;
  late final TextEditingController _credentialIdController;
  late final TextEditingController _userHandleController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _algorithmController;
  late final TextEditingController _platformController;
  late bool _platformReady;

  @override
  void initState() {
    super.initState();
    final record = widget.initialRecord;
    _relyingPartyIdController = TextEditingController(
      text: record?.relyingPartyId ?? '',
    );
    _credentialIdController = TextEditingController(
      text: record?.credentialId ?? '',
    );
    _userHandleController = TextEditingController(
      text: record?.userHandle ?? '',
    );
    _displayNameController = TextEditingController(
      text: record?.displayName ?? '',
    );
    _algorithmController = TextEditingController(
      text: record?.publicKeyAlgorithm ?? '',
    );
    _platformController = TextEditingController(text: record?.platform ?? '');
    _platformReady = record?.platformReady ?? false;
  }

  @override
  void dispose() {
    _relyingPartyIdController.dispose();
    _credentialIdController.dispose();
    _userHandleController.dispose();
    _displayNameController.dispose();
    _algorithmController.dispose();
    _platformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.text('passkeyMetadata')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('passkey-rp-id-input'),
                  controller: _relyingPartyIdController,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.text('relyingPartyId'),
                    hintText: strings.text('exampleDomain'),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _required,
                  onChanged: (_) => widget.onActivity(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('passkey-credential-id-input'),
                  controller: _credentialIdController,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.text('credentialId'),
                    hintText: strings.text('credentialIdHint'),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _required,
                  onChanged: (_) => widget.onActivity(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('passkey-user-handle-input'),
                  controller: _userHandleController,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.text('userHandle'),
                  ),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => widget.onActivity(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('passkey-display-name-input'),
                  controller: _displayNameController,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.text('displayName'),
                  ),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => widget.onActivity(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('passkey-algorithm-input'),
                  controller: _algorithmController,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.text('publicKeyAlgorithm'),
                    hintText: strings.text('algorithmHint'),
                  ),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => widget.onActivity(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('passkey-platform-input'),
                  controller: _platformController,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.text('platform'),
                    hintText: strings.text('platformHint'),
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => widget.onActivity(),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  key: const ValueKey('passkey-platform-ready-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.text('platformApiReady')),
                  value: _platformReady,
                  onChanged: (value) {
                    widget.onActivity();
                    setState(() => _platformReady = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('cancel')),
        ),
        FilledButton(
          key: const ValueKey('passkey-save-button'),
          onPressed: _save,
          child: Text(strings.text('save')),
        ),
      ],
    );
  }

  void _save() {
    widget.onActivity();
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    Navigator.of(context).pop(
      PasskeyRecord(
        relyingPartyId: _relyingPartyIdController.text.trim(),
        credentialId: _credentialIdController.text.trim(),
        userHandle: _userHandleController.text.trim(),
        displayName: _displayNameController.text.trim(),
        publicKeyAlgorithm: _algorithmController.text.trim(),
        platform: _platformController.text.trim(),
        platformReady: _platformReady,
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AppStrings.of(context).text('requiredField');
    }
    return null;
  }
}

class _StrengthIndicator extends StatelessWidget {
  const _StrengthIndicator({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final result = EntryPasswordPolicy.evaluate(password);
    final filledBars = result.score.clamp(0, 5);
    final color = switch (result.label) {
      MasterPasswordStrengthLabel.weak => Colors.red,
      MasterPasswordStrengthLabel.fair => Colors.orange,
      MasterPasswordStrengthLabel.strong => Colors.green,
    };
    final strings = AppStrings.of(context);
    final label = switch (result.label) {
      MasterPasswordStrengthLabel.weak => strings.text('passwordStrengthWeak'),
      MasterPasswordStrengthLabel.fair => strings.text('passwordStrengthFair'),
      MasterPasswordStrengthLabel.strong => strings.text(
        'passwordStrengthStrongShort',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              strings.text('passwordStrength'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < (filledBars * 4 ~/ 5)
                        ? color
                        : SecureVisualColors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              if (i != 3) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _EditMessage extends StatelessWidget {
  const _EditMessage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(
            Icons.edit_note_rounded,
            size: 36,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
