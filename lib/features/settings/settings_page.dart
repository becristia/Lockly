import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/master_password_policy.dart';
import 'package:secure_box/shared/widgets/secure_panel.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';
import 'package:secure_box/features/migration/migration_wizard_page.dart';
import 'package:secure_box/features/security_health/health_page.dart';
import 'package:secure_box/features/tag_management/tag_management_page.dart';
import 'package:secure_box/shared/i18n/app_language.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/i18n/password_policy_strings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _autoLockChoices = <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];
  static const _clipboardChoices = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  bool _biometricEnabled = false;
  Duration _autoLockTimeout = const Duration(minutes: 2);
  Duration _clipboardCleanupTimeout = const Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final biometricEnabled = await widget.services.isBiometricUnlockEnabled();
    final autoLockTimeout = await widget.services.getAutoLockTimeout();
    final clipboardCleanupTimeout = await widget.services
        .getClipboardCleanupTimeout();
    if (!mounted) {
      return;
    }
    setState(() {
      _biometricEnabled = biometricEnabled;
      _autoLockTimeout = autoLockTimeout;
      _clipboardCleanupTimeout = clipboardCleanupTimeout;
    });
  }

  Future<void> _changeMasterPassword() async {
    widget.services.recordActivity();
    final changed = await _showMasterPasswordChangeDialog(context);
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('masterPasswordChanged')),
        ),
      );
      await _loadSettings();
    }
  }

  Future<void> _setBiometricEnabled(bool enabled) async {
    widget.services.recordActivity();
    if (enabled) {
      final masterPassword = await _showMasterPasswordPrompt(
        title: AppStrings.of(context).text('biometricEnableTitle'),
        submitLabel: AppStrings.of(context).text('biometricEnable'),
        subtitle: AppStrings.of(context).text('biometricPromptSubtitle'),
        icon: Icons.fingerprint_rounded,
      );
      if (masterPassword == null) {
        return;
      }
      try {
        await widget.services.enableBiometricUnlock(masterPassword);
        if (mounted) {
          setState(() => _biometricEnabled = true);
        }
      } catch (_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context).text('biometricEnableFailed')),
          ),
        );
      }
      return;
    }

    final confirmed = await _showConfirmationDialog(
      title: AppStrings.of(context).text('biometricDisableTitle'),
      message: AppStrings.of(context).text('biometricDisableMessage'),
      confirmLabel: AppStrings.of(context).text('biometricDisable'),
    );
    if (confirmed != true) {
      return;
    }
    await widget.services.disableBiometricUnlock();
    if (mounted) {
      setState(() => _biometricEnabled = false);
    }
  }

  Future<void> _setAutoLockTimeout(Duration timeout) async {
    widget.services.recordActivity();
    await widget.services.setAutoLockTimeout(timeout);
    if (mounted) {
      setState(() => _autoLockTimeout = timeout);
    }
  }

  Future<void> _setClipboardCleanupTimeout(Duration timeout) async {
    widget.services.recordActivity();
    await widget.services.setClipboardCleanupTimeout(timeout);
    if (mounted) {
      setState(() => _clipboardCleanupTimeout = timeout);
    }
  }

  Future<void> _exportBackup() async {
    widget.services.recordActivity();
    final masterPassword = await _showMasterPasswordPrompt(
      title: AppStrings.of(context).text('backupExportTitle'),
      submitLabel: AppStrings.of(context).text('exportEncryptedBackup'),
      subtitle: AppStrings.of(context).text('reauthenticateExportSubtitle'),
      icon: Icons.file_upload_outlined,
    );
    if (masterPassword == null) {
      return;
    }
    try {
      await widget.services.verifyMasterPassword(masterPassword);
      final backupJson = await widget.services.exportEncryptedBackupJson();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _BackupExportDialog(
          services: widget.services,
          backupJson: backupJson,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('exportFailed'))),
      );
    }
  }

  Future<void> _importBackup() async {
    widget.services.recordActivity();
    final imported = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (context) => MigrationWizardPage(services: widget.services),
      ),
    );
    if (imported == null || !mounted) {
      return;
    }
    final message = '$imported ${AppStrings.of(context).text('import')}';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearLocalVault() async {
    widget.services.recordActivity();
    final confirmed = await _showConfirmationDialog(
      title: AppStrings.of(context).text('clearLocalVaultTitle'),
      message: AppStrings.of(context).text('clearLocalVaultMessage'),
      confirmLabel: AppStrings.of(context).text('clearLocalVault'),
      destructive: true,
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    final strings = AppStrings.of(context);
    final masterPassword = await _showMasterPasswordPrompt(
      title: strings.text('clearLocalVaultTitle'),
      submitLabel: strings.text('clearLocalVault'),
      subtitle: strings.text('reauthenticateClearVaultSubtitle'),
      icon: Icons.delete_forever_rounded,
    );
    if (masterPassword == null) {
      return;
    }
    try {
      await widget.services.verifyMasterPassword(masterPassword);
      await widget.services.clearLocalVault();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('clearLocalVaultFailed')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SecureVisualBackground(
      bottomInset: 0,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 92),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.settingsTitle,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 30,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 22),
            SecureSection(
              key: const ValueKey('settings-section-language'),
              title: strings.languageTitle,
              subtitle: strings.languageSubtitle,
              icon: Icons.translate_rounded,
              child: SecurePanel(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<AppLanguage>(
                  segments: [
                    ButtonSegment(
                      value: AppLanguage.zh,
                      label: Text(strings.text('zhLanguage')),
                      icon: Icon(Icons.language_rounded),
                    ),
                    ButtonSegment(
                      value: AppLanguage.en,
                      label: Text(strings.text('enLanguage')),
                      icon: Icon(Icons.language_rounded),
                    ),
                  ],
                  selected: {widget.services.language},
                  onSelectionChanged: (languages) {
                    widget.services.recordActivity();
                    widget.services.language = languages.first;
                    setState(() {});
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-theme'),
              title: strings.themeTitle,
              subtitle: strings.themeSubtitle,
              icon: Icons.palette_outlined,
              child: SecurePanel(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(strings.themeLight),
                      icon: const Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(strings.themeDark),
                      icon: const Icon(Icons.dark_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(strings.themeSystem),
                      icon: const Icon(Icons.settings_brightness_outlined),
                    ),
                  ],
                  selected: {widget.services.themeMode},
                  onSelectionChanged: (modes) {
                    widget.services.recordActivity();
                    widget.services.themeMode = modes.first;
                    setState(() {});
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-unlock'),
              title: strings.unlockSecurityTitle,
              subtitle: strings.unlockSecuritySubtitle,
              icon: Icons.verified_user_outlined,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ActionTile(
                      icon: Icons.password_rounded,
                      title: strings.changeMasterPassword,
                      subtitle: strings.changeMasterPasswordSubtitle,
                      onTap: _changeMasterPassword,
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      secondary: const Icon(Icons.fingerprint_rounded),
                      title: Text(strings.biometricTitle),
                      subtitle: Text(strings.biometricSubtitle),
                      value: _biometricEnabled,
                      onChanged: _setBiometricEnabled,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-privacy'),
              title: strings.privacyProtectionTitle,
              subtitle: strings.privacyProtectionSubtitle,
              icon: Icons.privacy_tip_outlined,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _DurationTile(
                      icon: Icons.lock_clock_rounded,
                      title: strings.autoLockTitle,
                      value: _autoLockTimeout,
                      choices: _autoLockChoices,
                      onChanged: _setAutoLockTimeout,
                    ),
                    const Divider(),
                    _DurationTile(
                      icon: Icons.content_paste_off_rounded,
                      title: strings.clipboardCleanupTitle,
                      value: _clipboardCleanupTimeout,
                      choices: _clipboardChoices,
                      onChanged: _setClipboardCleanupTimeout,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-health'),
              title: strings.text('healthTitle'),
              subtitle: strings.text('healthSubtitle'),
              icon: Icons.health_and_safety_outlined,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: SecureVisualColors.blue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.health_and_safety_outlined),
                  ),
                  title: Text(strings.text('healthTitle')),
                  subtitle: Text(strings.text('healthSubtitleShort')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    widget.services.recordActivity();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            HealthPage(services: widget.services),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-tags'),
              title: strings.text('tagManagementTitle'),
              subtitle: strings.text('tagManagementSubtitle'),
              icon: Icons.sell_outlined,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: SecureVisualColors.blue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.sell_outlined),
                  ),
                  title: Text(strings.text('tagManagementTitle')),
                  subtitle: Text(strings.text('tagManagementSubtitleShort')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    widget.services.recordActivity();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            TagManagementPage(services: widget.services),
                      ),
                    );
                  },
                ),
              ),
            ),
            SecureSection(
              key: const ValueKey('settings-section-lan-sync'),
              title: strings.text('lanExchangeTitle'),
              subtitle: strings.text('lanExchangeSubtitle'),
              icon: Icons.lan_outlined,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ActionTile(
                      key: const ValueKey('settings-lan-send'),
                      icon: Icons.qr_code_2_rounded,
                      title: strings.text('lanSendData'),
                      subtitle: strings.text('lanSendDataSubtitle'),
                      onTap: () {
                        widget.services.recordActivity();
                        Navigator.of(
                          context,
                        ).pushNamed(AppServices.routeLanSend);
                      },
                    ),
                    const Divider(),
                    _ActionTile(
                      key: const ValueKey('settings-lan-receive'),
                      icon: Icons.qr_code_scanner_rounded,
                      title: strings.text('lanReceiveData'),
                      subtitle: strings.text('lanReceiveDataSubtitle'),
                      onTap: () {
                        widget.services.recordActivity();
                        Navigator.of(
                          context,
                        ).pushNamed(AppServices.routeLanReceive);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-backup'),
              title: strings.text('encryptedBackup'),
              subtitle: strings.text('encryptedBackupSubtitle'),
              icon: Icons.inventory_2_outlined,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ActionTile(
                      icon: Icons.file_upload_outlined,
                      title: strings.text('exportEncryptedBackup'),
                      subtitle: strings.text('exportEncryptedBackupSubtitle'),
                      onTap: _exportBackup,
                    ),
                    const Divider(),
                    _ActionTile(
                      icon: Icons.move_up_rounded,
                      title: strings.text('migrationImport'),
                      subtitle: strings.text('migrationImportSubtitle'),
                      onTap: _importBackup,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-danger'),
              title: strings.text('dangerZone'),
              subtitle: strings.text('dangerZoneSubtitle'),
              icon: Icons.warning_amber_rounded,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                borderColor: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.35),
                child: _ActionTile(
                  icon: Icons.delete_outline_rounded,
                  title: strings.text('clearLocalVaultTitle'),
                  subtitle: strings.text('clearLocalVaultSubtitle'),
                  destructive: true,
                  onTap: _clearLocalVault,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showMasterPasswordChangeDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (context) =>
          _MasterPasswordChangeDialog(services: widget.services),
    );
  }

  Future<String?> _showMasterPasswordPrompt({
    required String title,
    required String submitLabel,
    String? subtitle,
    IconData icon = Icons.lock_outline_rounded,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) => _MasterPasswordPromptDialog(
        title: title,
        submitLabel: submitLabel,
        subtitle: subtitle,
        icon: icon,
      ),
    );
  }

  Future<bool?> _showConfirmationDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => _ReplicaConfirmationDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        destructive: destructive,
      ),
    );
  }

  static String? _requiredPassword(String? value, AppStrings strings) {
    if (value == null || value.isEmpty) {
      return strings.text('requiredMasterPassword');
    }
    return null;
  }

  static String? _validateNewPassword(String? value, AppStrings strings) {
    final result = MasterPasswordPolicy.evaluate(value ?? '');
    return result.isAcceptable
        ? null
        : localizedMasterPasswordPolicyMessage(result, strings);
  }
}

class _ReplicaConfirmationDialog extends StatelessWidget {
  const _ReplicaConfirmationDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final color = destructive
        ? SecureVisualColors.danger
        : Theme.of(context).colorScheme.primary;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      backgroundColor: Colors.transparent,
      child: SecureGlassCard(
        borderRadius: 28,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SecureIconBadge(
              icon: destructive
                  ? Icons.delete_outline_rounded
                  : Icons.verified_user_outlined,
              color: color,
              size: 82,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                ),
                child: Text(confirmLabel),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(strings.text('cancel')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MasterPasswordChangeDialog extends StatefulWidget {
  const _MasterPasswordChangeDialog({required this.services});

  final AppServices services;

  @override
  State<_MasterPasswordChangeDialog> createState() =>
      _MasterPasswordChangeDialogState();
}

class _MasterPasswordChangeDialogState
    extends State<_MasterPasswordChangeDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String? _errorText;
  bool _isSaving = false;
  bool _oldObscured = true;
  bool _newObscured = true;
  bool _confirmObscured = true;

  @override
  void dispose() {
    _oldPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      backgroundColor: Colors.transparent,
      child: SingleChildScrollView(
        child: SecureGlassCard(
          borderRadius: 28,
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                const SecureIconBadge(icon: Icons.key_rounded, size: 76),
                const SizedBox(height: 18),
                Text(
                  strings.changeMasterPassword,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  strings.text('changeMasterPasswordAdvice'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _oldPasswordController,
                  decoration: InputDecoration(
                    labelText: strings.text('currentMasterPassword'),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _oldObscured = !_oldObscured),
                      icon: Icon(
                        _oldObscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  obscureText: _oldObscured,
                  enableSuggestions: false,
                  autocorrect: false,
                  validator: (value) =>
                      _SettingsPageState._requiredPassword(value, strings),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _newPasswordController,
                  decoration: InputDecoration(
                    labelText: strings.text('newMasterPassword'),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _newObscured = !_newObscured),
                      icon: Icon(
                        _newObscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  obscureText: _newObscured,
                  enableSuggestions: false,
                  autocorrect: false,
                  validator: (value) =>
                      _SettingsPageState._validateNewPassword(value, strings),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: strings.text('confirmNewMasterPassword'),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _confirmObscured = !_confirmObscured),
                      icon: Icon(
                        _confirmObscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  obscureText: _confirmObscured,
                  enableSuggestions: false,
                  autocorrect: false,
                  validator: (value) {
                    if (value != _newPasswordController.text) {
                      return strings.text('passwordMismatch');
                    }
                    return null;
                  },
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SecureGradientButton(
                  onPressed: _isSaving ? null : _submit,
                  label: strings.text('save'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(strings.text('cancel')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      await widget.services.changeMasterPassword(
        oldPassword: _oldPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on MasterPasswordChangedBiometricCleanupException {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorText = AppStrings.of(context).text('masterPasswordCleanupFailed');
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorText = AppStrings.of(context).text('masterPasswordChangeFailed');
      });
    }
  }
}

class _MasterPasswordPromptDialog extends StatefulWidget {
  const _MasterPasswordPromptDialog({
    required this.title,
    required this.submitLabel,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String submitLabel;
  final String? subtitle;
  final IconData icon;

  @override
  State<_MasterPasswordPromptDialog> createState() =>
      _MasterPasswordPromptDialogState();
}

class _MasterPasswordPromptDialogState
    extends State<_MasterPasswordPromptDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();
  bool _obscureMasterPassword = true;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      backgroundColor: Colors.transparent,
      child: SecureGlassCard(
        borderRadius: 28,
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SecureIconBadge(icon: widget.icon, size: 82),
              const SizedBox(height: 22),
              Text(
                widget.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 10),
                Text(
                  widget.subtitle!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 24),
              TextFormField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: strings.text('masterPassword'),
                  suffixIcon: IconButton(
                    tooltip: _obscureMasterPassword
                        ? strings.text('showMasterPassword')
                        : strings.text('hideMasterPassword'),
                    onPressed: () {
                      setState(
                        () => _obscureMasterPassword = !_obscureMasterPassword,
                      );
                    },
                    icon: Icon(
                      _obscureMasterPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                obscureText: _obscureMasterPassword,
                enableSuggestions: false,
                autocorrect: false,
                validator: (value) =>
                    _SettingsPageState._requiredPassword(value, strings),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(strings.text('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SecureGradientButton(
                      onPressed: _submit,
                      label: widget.submitLabel,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    strings.text('localOnlyInfo'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(_controller.text);
  }
}

class _BackupExportDialog extends StatefulWidget {
  const _BackupExportDialog({required this.services, required this.backupJson});

  final AppServices services;
  final String backupJson;

  @override
  State<_BackupExportDialog> createState() => _BackupExportDialogState();
}

class _BackupExportDialogState extends State<_BackupExportDialog> {
  bool _copied = false;

  Future<void> _copyBackupJson() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ReplicaConfirmationDialog(
        title: AppStrings.of(context).text('copyBackupConfirmTitle'),
        message: AppStrings.of(context).text('copyBackupConfirmMessage'),
        confirmLabel: AppStrings.of(context).text('copyBackup'),
        destructive: true,
      ),
    );
    if (confirmed != true) {
      return;
    }
    final copied = await widget.services.copySensitiveTemporary(
      widget.backupJson,
      clearAfter: const Duration(seconds: 30),
    );
    if (!mounted) {
      return;
    }
    setState(() => _copied = copied);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copied
              ? AppStrings.of(context).text('backupCopied')
              : AppStrings.of(context).copyFailed,
        ),
      ),
    );
  }

  Future<void> _clearClipboardNow() async {
    final cleared = await widget.services.clearSensitiveClipboardNow();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cleared
              ? AppStrings.of(context).text('clipboardCleared')
              : AppStrings.of(context).text('clipboardClearNoPendingSecret'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      backgroundColor: Colors.transparent,
      child: SecureGlassCard(
        borderRadius: 28,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SecureIconBadge(icon: Icons.file_upload_outlined, size: 76),
            const SizedBox(height: 18),
            Text(
              strings.text('backupExportTitle'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              strings.text('backupExportSubtitle'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            SecureGlassCard(
              padding: const EdgeInsets.all(14),
              borderRadius: 16,
              shadow: false,
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.72),
              borderColor: Theme.of(context).colorScheme.outlineVariant,
              child: Text(
                strings
                    .text('backupPreparedNoPreview')
                    .replaceFirst(
                      '{bytes}',
                      widget.backupJson.length.toString(),
                    ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 20),
            SecureGradientButton(
              onPressed: _copyBackupJson,
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              label: _copied
                  ? strings.text('copied')
                  : strings.text('copyBackup'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _clearClipboardNow,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(strings.text('clearClipboardNow')),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.text('close')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.chevron_right_rounded, color: color),
      onTap: onTap,
    );
  }
}

class _DurationTile extends StatelessWidget {
  const _DurationTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final Duration value;
  final List<Duration> choices;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedValue = choices.contains(value) ? value : choices.first;
    final strings = AppStrings.of(context);

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: DropdownButton<Duration>(
        value: selectedValue,
        items: choices
            .map(
              (choice) => DropdownMenuItem<Duration>(
                value: choice,
                child: Text(strings.durationLabel(choice)),
              ),
            )
            .toList(growable: false),
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
      ),
    );
  }
}
