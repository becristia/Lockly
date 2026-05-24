import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/autofill/android_autofill_service.dart';
import 'package:secure_box/core/security/master_password_policy.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/shared/widgets/secure_panel.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';
import 'package:secure_box/features/migration/migration_wizard_page.dart';
import 'package:secure_box/features/security_health/health_page.dart';
import 'package:secure_box/features/tag_management/tag_management_page.dart';

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
  AndroidAutofillStatus _autofillStatus =
      const AndroidAutofillStatus.unavailable();
  bool _cloudSyncBusy = false;
  String _cloudSyncStatus = 'Not connected';

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
    final autofillStatus = await widget.services.getAndroidAutofillStatus();
    if (!mounted) {
      return;
    }
    setState(() {
      _biometricEnabled = biometricEnabled;
      _autoLockTimeout = autoLockTimeout;
      _clipboardCleanupTimeout = clipboardCleanupTimeout;
      _autofillStatus = autofillStatus;
    });
  }

  Future<void> _changeMasterPassword() async {
    widget.services.recordActivity();
    final changed = await _showMasterPasswordChangeDialog(context);
    if (changed == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('主密码已修改，生物识别需要重新开启。')));
      await _loadSettings();
    }
  }

  Future<void> _setBiometricEnabled(bool enabled) async {
    widget.services.recordActivity();
    if (enabled) {
      final masterPassword = await _showMasterPasswordPrompt(
        title: '开启生物识别',
        submitLabel: '开启',
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法开启生物识别，请确认主密码。')));
      }
      return;
    }

    final confirmed = await _showConfirmationDialog(
      title: '关闭生物识别',
      message: '关闭后会删除系统安全区中的 DEK 副本，下次需要输入主密码。',
      confirmLabel: '关闭',
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

  Future<void> _openAutofillSettings() async {
    widget.services.recordActivity();
    try {
      await widget.services.openAndroidAutofillSettings();
      final status = await widget.services.getAndroidAutofillStatus();
      if (mounted) {
        setState(() => _autofillStatus = status);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Android Autofill settings unavailable')),
      );
    }
  }

  Future<void> _exportBackup() async {
    widget.services.recordActivity();
    try {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('导出失败，请稍后重试。')));
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Imported $imported record(s).')));
  }

  Future<void> _loginCloudSync() async {
    widget.services.recordActivity();
    final input = await _showCloudLoginDialog(context);
    if (input == null) return;
    await _runCloudSyncAction(() async {
      await widget.services.loginCloudSync(
        email: input.email,
        password: input.password,
      );
      _cloudSyncStatus = 'Connected';
    });
  }

  Future<void> _registerCloudSync() async {
    widget.services.recordActivity();
    final input = await _showCloudRegisterDialog(context);
    if (input == null) return;
    await _runCloudSyncAction(() async {
      await widget.services.registerCloudSync(
        email: input.email,
        password: input.password,
      );
      _cloudSyncStatus = 'Registered and connected';
    });
  }

  Future<void> _syncCloudNow() async {
    widget.services.recordActivity();
    final masterPassword = await _showMasterPasswordPrompt(
      title: 'Sync encrypted vault',
      submitLabel: 'Sync',
    );
    if (masterPassword == null) {
      return;
    }
    await _runCloudSyncAction(() async {
      final imported = await widget.services.syncEncryptedVaultNow(
        masterPassword: masterPassword,
      );
      if (imported.hasConflicts) {
        _cloudSyncStatus =
            'Sync conflicts detected; imported ${imported.importedCount} encrypted updates, '
            '${imported.conflictCount} unresolved conflicts';
      } else {
        _cloudSyncStatus =
            'Synced; imported ${imported.importedCount} encrypted updates';
      }
    });
  }

  Future<void> _downloadCloudVault() async {
    widget.services.recordActivity();
    final masterPassword = await _showMasterPasswordPrompt(
      title: 'Download cloud vault',
      submitLabel: 'Download',
    );
    if (masterPassword == null) {
      return;
    }
    await _runCloudSyncAction(() async {
      final imported = await widget.services.downloadCloudEncryptedVault(
        masterPassword: masterPassword,
      );
      _cloudSyncStatus = 'Downloaded and imported $imported encrypted records';
    });
  }

  Future<void> _showCloudDevices() async {
    widget.services.recordActivity();
    if (_cloudSyncBusy) return;
    setState(() => _cloudSyncBusy = true);
    try {
      final devices = await widget.services.listCloudSyncDevices();
      _cloudSyncStatus = '${devices.length} cloud device(s)';
      if (!mounted) {
        return;
      }
      setState(() => _cloudSyncBusy = false);
      await showDialog<void>(
        context: context,
        builder: (context) => _CloudDevicesDialog(
          devices: devices,
          onRename: (deviceId, deviceName) async {
            final device = await widget.services.renameCloudSyncDevice(
              deviceId: deviceId,
              deviceName: deviceName,
            );
            if (mounted) {
              setState(() => _cloudSyncStatus = 'Device renamed');
            }
            return device;
          },
          onRevoke: (deviceId) async {
            await widget.services.revokeCloudSyncDevice(deviceId);
            if (mounted) {
              setState(() => _cloudSyncStatus = 'Device revoked');
            }
          },
        ),
      );
      return;
    } catch (_) {
      _cloudSyncStatus = 'Cloud sync unavailable';
    } finally {
      if (mounted && _cloudSyncBusy) {
        setState(() => _cloudSyncBusy = false);
      }
    }
  }

  Future<void> _logoutCloudSync() async {
    widget.services.recordActivity();
    await _runCloudSyncAction(() async {
      await widget.services.logoutCloudSync();
      _cloudSyncStatus = 'Not connected';
    });
  }

  Future<void> _runCloudSyncAction(Future<void> Function() action) async {
    if (_cloudSyncBusy) return;
    setState(() => _cloudSyncBusy = true);
    try {
      await action();
    } catch (_) {
      _cloudSyncStatus = 'Cloud sync unavailable';
    } finally {
      if (mounted) {
        setState(() => _cloudSyncBusy = false);
      }
    }
  }

  Future<void> _clearLocalVault() async {
    widget.services.recordActivity();
    final confirmed = await _showConfirmationDialog(
      title: '清除本地密码库',
      message: '此操作会删除本机密码库和设置，无法找回。请确认已经导出可用备份。',
      confirmLabel: '清除',
      destructive: true,
    );
    if (confirmed != true) {
      return;
    }
    await widget.services.clearLocalVault();
  }

  @override
  Widget build(BuildContext context) {
    return SecureVisualBackground(
      bottomInset: 0,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 92),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设置',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 30,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 22),
            SecureSection(
              key: const ValueKey('settings-section-theme'),
              title: '主题',
              subtitle: '选择浅色、深色或跟随系统主题。',
              icon: Icons.palette_outlined,
              child: SecurePanel(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('浅色'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('深色'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('跟随系统'),
                      icon: Icon(Icons.settings_brightness_outlined),
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
              title: '解锁安全',
              subtitle: '管理主密码和生物识别快速解锁。',
              icon: Icons.verified_user_outlined,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ActionTile(
                      icon: Icons.password_rounded,
                      title: '修改主密码',
                      subtitle: '只重新加密 DEK，不重新加密所有条目。',
                      onTap: _changeMasterPassword,
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      secondary: const Icon(Icons.fingerprint_rounded),
                      title: const Text('生物识别'),
                      subtitle: const Text('失败时仍需回退到主密码。'),
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
              title: '隐私保护',
              subtitle: '控制自动锁定和剪贴板清理时间。',
              icon: Icons.privacy_tip_outlined,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _DurationTile(
                      icon: Icons.lock_clock_rounded,
                      title: '自动锁定',
                      value: _autoLockTimeout,
                      choices: _autoLockChoices,
                      onChanged: _setAutoLockTimeout,
                    ),
                    const Divider(),
                    _DurationTile(
                      icon: Icons.content_paste_off_rounded,
                      title: '剪贴板清理',
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
              key: const ValueKey('settings-section-autofill'),
              title: 'Android Autofill',
              subtitle:
                  'Prepare the system provider; filling requires a later authenticated picker.',
              icon: Icons.password_rounded,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        _autofillStatus.enabled
                            ? Icons.check_circle_outline_rounded
                            : Icons.info_outline_rounded,
                      ),
                      title: const Text('Status'),
                      subtitle: Text(_autofillStatusLabel(_autofillStatus)),
                    ),
                    const Divider(),
                    _ActionTile(
                      key: const ValueKey('settings-open-autofill'),
                      icon: Icons.settings_applications_outlined,
                      title: 'Open Android Autofill settings',
                      subtitle:
                          'Enable Lockly as the provider. Stage A does not fill saved items yet.',
                      onTap: _autofillStatus.supported
                          ? _openAutofillSettings
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-health'),
              title: '密码健康',
              subtitle: '检测弱密码、重复密码和过期密码。',
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
                  title: const Text('密码健康'),
                  subtitle: const Text('检测弱密码、重复密码和过期密码'),
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
              title: '标签管理',
              subtitle: '管理密码库标签。',
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
                  title: const Text('标签管理'),
                  subtitle: const Text('管理密码库标签'),
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
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-cloud-sync'),
              title: 'Cloud sync',
              subtitle:
                  'Sync encrypted vault rows only; vault unlock stays local.',
              icon: Icons.cloud_sync_outlined,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.cloud_done_outlined),
                      title: const Text('Cloud sync status'),
                      subtitle: Text(_cloudSyncStatus),
                    ),
                    const Divider(),
                    _ActionTile(
                      icon: Icons.login_rounded,
                      title: 'Cloud login',
                      subtitle: 'Use a separate backend account password.',
                      onTap: _cloudSyncBusy ? null : _loginCloudSync,
                    ),
                    const Divider(),
                    _ActionTile(
                      icon: Icons.person_add_alt_1_rounded,
                      title: 'Cloud register',
                      subtitle:
                          'Create a backend account, then register this device.',
                      onTap: _cloudSyncBusy ? null : _registerCloudSync,
                    ),
                    const Divider(),
                    _ActionTile(
                      icon: Icons.sync_rounded,
                      title: 'Sync encrypted vault',
                      subtitle:
                          'Upload local ciphertext and download encrypted updates.',
                      onTap: _cloudSyncBusy ? null : _syncCloudNow,
                    ),
                    const Divider(),
                    _ActionTile(
                      icon: Icons.cloud_download_outlined,
                      title: 'Download cloud vault',
                      subtitle:
                          'Requires the local vault passphrase to verify import.',
                      onTap: _cloudSyncBusy ? null : _downloadCloudVault,
                    ),
                    const Divider(),
                    _ActionTile(
                      icon: Icons.devices_outlined,
                      title: 'Cloud devices',
                      subtitle: 'List trusted devices for this account.',
                      onTap: _cloudSyncBusy ? null : _showCloudDevices,
                    ),
                    const Divider(),
                    _ActionTile(
                      icon: Icons.logout_rounded,
                      title: 'Cloud logout',
                      subtitle: 'Clear cloud tokens from this device.',
                      onTap: _cloudSyncBusy ? null : _logoutCloudSync,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-backup'),
              title: '加密备份',
              subtitle: '备份仍需主密码才能恢复。',
              icon: Icons.inventory_2_outlined,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ActionTile(
                      icon: Icons.file_upload_outlined,
                      title: '导出加密备份',
                      subtitle: '导出本地加密备份 JSON。',
                      onTap: _exportBackup,
                    ),
                    const Divider(),
                    _ActionTile(
                      icon: Icons.move_up_rounded,
                      title: 'Migration import',
                      subtitle: 'Import Lockly JSON or local CSV exports.',
                      onTap: _importBackup,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-danger'),
              title: '危险操作',
              subtitle: '这些操作不可撤销。',
              icon: Icons.warning_amber_rounded,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                borderColor: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.35),
                child: _ActionTile(
                  icon: Icons.delete_outline_rounded,
                  title: '清除本地密码库',
                  subtitle: '删除本机密码库和设置。',
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
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) =>
          _MasterPasswordPromptDialog(title: title, submitLabel: submitLabel),
    );
  }

  Future<_CloudLoginInput?> _showCloudLoginDialog(BuildContext context) {
    return showDialog<_CloudLoginInput>(
      context: context,
      builder: (context) => const _CloudLoginDialog(),
    );
  }

  Future<_CloudLoginInput?> _showCloudRegisterDialog(BuildContext context) {
    return showDialog<_CloudLoginInput>(
      context: context,
      builder: (context) => const _CloudLoginDialog(
        title: 'Cloud register',
        submitLabel: 'Register',
        emailFieldKey: ValueKey('cloud-register-email-field'),
        passwordFieldKey: ValueKey('cloud-register-password-field'),
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

  static String? _requiredPassword(String? value) {
    if (value == null || value.isEmpty) {
      return '请输入主密码';
    }
    return null;
  }

  static String _autofillStatusLabel(AndroidAutofillStatus status) {
    if (!status.supported) {
      return 'Unsupported';
    }
    return status.enabled ? 'Enabled' : 'Disabled';
  }

  static String? _validateNewPassword(String? value) {
    final result = MasterPasswordPolicy.evaluate(value ?? '');
    return result.isAcceptable ? null : result.message;
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
                child: const Text('取消'),
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
                Text('修改主密码', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '建议定期更新密码以提升安全性。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _oldPasswordController,
                  decoration: InputDecoration(
                    labelText: '当前主密码',
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
                  validator: _SettingsPageState._requiredPassword,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _newPasswordController,
                  decoration: InputDecoration(
                    labelText: '新主密码',
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
                  validator: _SettingsPageState._validateNewPassword,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: '确认新主密码',
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
                  validator: (value) {
                    if (value != _newPasswordController.text) {
                      return '两次输入的主密码不一致';
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
                  label: '保存',
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
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
        _errorText = '主密码已修改，但生物识别清理失败。请使用新主密码重新进入设置并重试关闭生物识别。';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorText = '主密码修改失败，请确认当前主密码。';
      });
    }
  }
}

class _MasterPasswordPromptDialog extends StatefulWidget {
  const _MasterPasswordPromptDialog({
    required this.title,
    required this.submitLabel,
  });

  final String title;
  final String submitLabel;

  @override
  State<_MasterPasswordPromptDialog> createState() =>
      _MasterPasswordPromptDialogState();
}

class _MasterPasswordPromptDialogState
    extends State<_MasterPasswordPromptDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              const SecureIconBadge(icon: Icons.fingerprint_rounded, size: 82),
              const SizedBox(height: 22),
              Text(
                widget.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                '启用后，可使用指纹或面部快速解锁\n仍需输入主密码以管理设置',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: '主密码',
                  suffixIcon: Icon(Icons.visibility_off_outlined),
                ),
                obscureText: true,
                validator: _SettingsPageState._requiredPassword,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
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
                    '信息仅存储在本机',
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
    final copied = await widget.services.copySensitiveTemporary(
      widget.backupJson,
      clearAfter: const Duration(seconds: 30),
    );
    if (!mounted) {
      return;
    }
    setState(() => _copied = copied);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(copied ? '加密备份已复制，30 秒后将自动清理剪贴板。' : '复制失败，请重试。')),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            Text('导出加密备份', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '备份内容已加密，恢复时仍需要对应主密码。',
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
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: SelectableText(
                    widget.backupJson,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SecureGradientButton(
              onPressed: _copyBackupJson,
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              label: _copied ? '已复制' : '复制备份',
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
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

class _CloudLoginDialog extends StatefulWidget {
  const _CloudLoginDialog({
    this.title = 'Cloud login',
    this.submitLabel = 'Login',
    this.emailFieldKey = const ValueKey('cloud-login-email-field'),
    this.passwordFieldKey = const ValueKey('cloud-login-password-field'),
  });

  final String title;
  final String submitLabel;
  final ValueKey<String> emailFieldKey;
  final ValueKey<String> passwordFieldKey;

  @override
  State<_CloudLoginDialog> createState() => _CloudLoginDialogState();
}

class _CloudLoginDialogState extends State<_CloudLoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: widget.emailFieldKey,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) {
                if (value == null || !value.contains('@')) {
                  return 'Enter an email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: widget.passwordFieldKey,
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Account password'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Enter the account password';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) {
              return;
            }
            Navigator.of(context).pop(
              _CloudLoginInput(
                email: _emailController.text.trim(),
                password: _passwordController.text,
              ),
            );
          },
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}

class _CloudDevicesDialog extends StatefulWidget {
  const _CloudDevicesDialog({
    required this.devices,
    required this.onRename,
    required this.onRevoke,
  });

  final List<SyncDevice> devices;
  final Future<SyncDevice> Function(String deviceId, String deviceName)
  onRename;
  final Future<void> Function(String deviceId) onRevoke;

  @override
  State<_CloudDevicesDialog> createState() => _CloudDevicesDialogState();
}

class _CloudDevicesDialogState extends State<_CloudDevicesDialog> {
  late List<SyncDevice> _devices;
  String? _busyDeviceId;

  @override
  void initState() {
    super.initState();
    _devices = List<SyncDevice>.of(widget.devices);
  }

  Future<void> _rename(SyncDevice device) async {
    if (_busyDeviceId != null) {
      return;
    }
    final deviceName = await showDialog<String>(
      context: context,
      builder: (context) => _CloudDeviceRenameDialog(device: device),
    );
    if (deviceName == null || deviceName == device.deviceName || !mounted) {
      return;
    }
    setState(() => _busyDeviceId = device.id);
    try {
      final renamed = await widget.onRename(device.id, deviceName);
      if (mounted) {
        setState(() {
          final index = _devices.indexWhere((item) => item.id == device.id);
          if (index != -1) {
            _devices[index] = renamed;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busyDeviceId = null);
      }
    }
  }

  Future<void> _revoke(String deviceId) async {
    if (_busyDeviceId != null) {
      return;
    }
    setState(() => _busyDeviceId = deviceId);
    try {
      await widget.onRevoke(deviceId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _busyDeviceId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cloud devices'),
      content: SizedBox(
        width: 420,
        child: _devices.isEmpty
            ? const Text('No cloud devices')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _devices.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  final busy = _busyDeviceId == device.id;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.devices_outlined),
                    title: Text(device.deviceName),
                    subtitle: Text(_formatDeviceMetadata(device)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: ValueKey('cloud-device-rename-${device.id}'),
                          tooltip: 'Rename',
                          onPressed: busy ? null : () => _rename(device),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        TextButton(
                          onPressed: busy ? null : () => _revoke(device.id),
                          child: Text(busy ? 'Working' : 'Revoke'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busyDeviceId == null
              ? () => Navigator.of(context).pop()
              : null,
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _CloudDeviceRenameDialog extends StatefulWidget {
  const _CloudDeviceRenameDialog({required this.device});

  final SyncDevice device;

  @override
  State<_CloudDeviceRenameDialog> createState() =>
      _CloudDeviceRenameDialogState();
}

class _CloudDeviceRenameDialogState extends State<_CloudDeviceRenameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.device.deviceName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename device'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey('cloud-device-rename-field'),
          controller: _controller,
          decoration: const InputDecoration(labelText: 'Device name'),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Enter a device name';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) {
              return;
            }
            Navigator.of(context).pop(_controller.text.trim());
          },
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

String _formatDeviceMetadata(SyncDevice device) {
  final platform =
      _firstNonBlank(device.platform, device.deviceType) ?? 'Unknown platform';
  final clientVersion = _nonBlank(device.clientVersion);
  final lastSyncAt = _nonBlank(device.lastSyncAt);
  final lastIpAddress = _nonBlank(device.lastIpAddress);
  final lastUserAgent = _nonBlank(device.lastUserAgent);
  final values = <String>[
    platform,
    if (clientVersion != null) 'v$clientVersion',
    if (lastSyncAt != null) 'Last sync $lastSyncAt',
    if (lastIpAddress != null) 'IP $lastIpAddress',
    ?lastUserAgent,
  ];
  return values.join(' | ');
}

String? _firstNonBlank(String? first, String? second) {
  return _nonBlank(first) ?? _nonBlank(second);
}

String? _nonBlank(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
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

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: DropdownButton<Duration>(
        value: selectedValue,
        items: choices
            .map(
              (choice) => DropdownMenuItem<Duration>(
                value: choice,
                child: Text(_formatDuration(choice)),
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

  static String _formatDuration(Duration value) {
    if (value.inMinutes >= 1) {
      return '${value.inMinutes} 分钟';
    }
    return '${value.inSeconds} 秒';
  }
}

class _CloudLoginInput {
  const _CloudLoginInput({required this.email, required this.password});

  final String email;
  final String password;
}
