import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/master_password_policy.dart';
import 'package:secure_box/core/sync/sync_api_client.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/core/vault/vault_service.dart';
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
  bool _cloudSyncBusy = false;
  String _cloudSyncStatusKey = 'cloudNotConnected';
  String? _cloudSyncAccountEmail;
  int? _cloudSyncImportedCount;
  int? _cloudSyncConflictCount;
  int? _cloudSyncDeviceCount;

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
    final cloudSyncAccountEmail = await widget.services.cloudSyncAccountEmail();
    if (!mounted) {
      return;
    }
    setState(() {
      _biometricEnabled = biometricEnabled;
      _autoLockTimeout = autoLockTimeout;
      _clipboardCleanupTimeout = clipboardCleanupTimeout;
      _cloudSyncAccountEmail = cloudSyncAccountEmail;
      _setCloudSyncStatus(
        cloudSyncAccountEmail == null ? 'cloudNotConnected' : 'cloudConnected',
      );
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

  Future<void> _loginCloudSync() async {
    widget.services.recordActivity();
    final input = await _showCloudLoginDialog(context);
    if (input == null) return;
    await _runCloudSyncAction(() async {
      await widget.services.loginCloudSync(
        email: input.email,
        password: input.password,
      );
      _cloudSyncAccountEmail = input.email;
      _setCloudSyncStatus('cloudConnected');
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
      _cloudSyncAccountEmail = input.email;
      _setCloudSyncStatus('cloudRegisteredConnected');
    });
  }

  Future<void> _syncCloudNow() async {
    widget.services.recordActivity();
    if (!await _ensureCloudSignedIn()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final strings = AppStrings.of(context);
    final masterPassword = await _showMasterPasswordPrompt(
      title: strings.text('cloudSyncVaultTitle'),
      submitLabel: strings.text('cloudSync'),
    );
    if (masterPassword == null) {
      return;
    }
    await _runCloudSyncAction(() async {
      final imported = await widget.services.syncEncryptedVaultNow(
        masterPassword: masterPassword,
      );
      if (imported.hasConflicts) {
        _setCloudSyncStatus(
          'cloudSyncConflicts',
          importedCount: imported.importedCount,
          conflictCount: imported.conflictCount,
        );
      } else {
        _setCloudSyncStatus(
          'cloudSynced',
          importedCount: imported.importedCount,
        );
      }
    });
  }

  Future<void> _downloadCloudVault() async {
    widget.services.recordActivity();
    if (!await _ensureCloudSignedIn()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final strings = AppStrings.of(context);
    final masterPassword = await _showMasterPasswordPrompt(
      title: strings.text('cloudDownloadVaultTitle'),
      submitLabel: strings.text('download'),
    );
    if (masterPassword == null) {
      return;
    }
    await _runCloudSyncAction(() async {
      final imported = await widget.services.downloadCloudEncryptedVault(
        masterPassword: masterPassword,
      );
      _setCloudSyncStatus('cloudDownloaded', importedCount: imported);
    });
  }

  Future<void> _showCloudDevices() async {
    widget.services.recordActivity();
    if (!await _ensureCloudSignedIn()) {
      return;
    }
    if (_cloudSyncBusy) return;
    setState(() => _cloudSyncBusy = true);
    try {
      final devices = await widget.services.listCloudSyncDevices();
      _setCloudSyncStatus('cloudDeviceCount', deviceCount: devices.length);
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
              setState(() => _setCloudSyncStatus('cloudDeviceRenamed'));
            }
            return device;
          },
          onRevoke: (deviceId) async {
            await widget.services.revokeCloudSyncDevice(deviceId);
            if (mounted) {
              setState(() => _setCloudSyncStatus('cloudDeviceRevoked'));
            }
          },
        ),
      );
      return;
    } catch (error) {
      _setCloudSyncStatus('cloudUnavailable');
      if (mounted) {
        _showCloudMessage(_cloudSyncErrorMessage(error));
      }
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
      _cloudSyncAccountEmail = null;
      _setCloudSyncStatus('cloudNotConnected');
    });
  }

  Future<void> _runCloudSyncAction(Future<void> Function() action) async {
    if (_cloudSyncBusy) return;
    setState(() => _cloudSyncBusy = true);
    try {
      await action();
    } catch (error) {
      _setCloudSyncStatus('cloudUnavailable');
      if (mounted) {
        _showCloudMessage(_cloudSyncErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _cloudSyncBusy = false);
      }
    }
  }

  Future<bool> _ensureCloudSignedIn() async {
    try {
      final email = await widget.services.cloudSyncAccountEmail();
      if (email == null) {
        _cloudSyncAccountEmail = null;
        _setCloudSyncStatus('cloudNotConnected');
        if (mounted) {
          setState(() {});
          _showCloudMessage(AppStrings.of(context).text('cloudLoginRequired'));
        }
        return false;
      }
      _cloudSyncAccountEmail = email;
      return true;
    } catch (_) {
      _cloudSyncAccountEmail = null;
      _setCloudSyncStatus('cloudUnavailable');
      if (mounted) {
        setState(() {});
        _showCloudMessage(AppStrings.of(context).text('cloudNetworkFailed'));
      }
      return false;
    }
  }

  void _showCloudMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _cloudSyncErrorMessage(Object error) {
    final strings = AppStrings.of(context);
    if (error is SyncApiException) {
      return switch (error.code) {
        'INVALID_CREDENTIALS' => strings.text('cloudInvalidCredentials'),
        'USER_DISABLED' => strings.text('cloudUserDisabled'),
        'VALIDATION_ERROR' => strings.text('cloudRegisterValidationError'),
        'UNAUTHORIZED' ||
        'TOKEN_INVALID' ||
        'TOKEN_EXPIRED' => strings.text('cloudLoginRequired'),
        _ =>
          error.statusCode >= 500
              ? strings.text('cloudNetworkFailed')
              : strings.text('cloudActionFailed'),
      };
    }
    if (error is StateError && error.message.contains('token')) {
      return strings.text('cloudLoginRequired');
    }
    if (error is VaultUnlockException) {
      return strings.text('masterPasswordConfirmationFailed');
    }
    return strings.text('cloudNetworkFailed');
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
    await widget.services.clearLocalVault();
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
            const SizedBox(height: 20),
            SecureSection(
              key: const ValueKey('settings-section-cloud-sync'),
              title: strings.text('cloudSyncTitle'),
              subtitle: strings.text('cloudSyncSubtitle'),
              icon: Icons.cloud_sync_outlined,
              child: SecurePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.cloud_done_outlined),
                      title: Text(strings.text('cloudSyncStatus')),
                      subtitle: Text(_cloudSyncStatusLabel(strings)),
                    ),
                    const Divider(),
                    _ActionTile(
                      key: const ValueKey('settings-cloud-login'),
                      icon: Icons.login_rounded,
                      title: strings.text('cloudLogin'),
                      subtitle: strings.text('cloudLoginSubtitle'),
                      onTap: _cloudSyncBusy ? null : _loginCloudSync,
                    ),
                    const Divider(),
                    _ActionTile(
                      key: const ValueKey('settings-cloud-register'),
                      icon: Icons.person_add_alt_1_rounded,
                      title: strings.text('cloudRegister'),
                      subtitle: strings.text('cloudRegisterSubtitle'),
                      onTap: _cloudSyncBusy ? null : _registerCloudSync,
                    ),
                    const Divider(),
                    _ActionTile(
                      key: const ValueKey('settings-cloud-sync-now'),
                      icon: Icons.sync_rounded,
                      title: strings.text('cloudSyncVaultTitle'),
                      subtitle: strings.text('cloudSyncSubtitle'),
                      onTap: _cloudSyncBusy ? null : _syncCloudNow,
                    ),
                    const Divider(),
                    _ActionTile(
                      key: const ValueKey('settings-cloud-download'),
                      icon: Icons.cloud_download_outlined,
                      title: strings.text('cloudDownloadVault'),
                      subtitle: strings.text('cloudDownloadVaultTitle'),
                      onTap: _cloudSyncBusy ? null : _downloadCloudVault,
                    ),
                    const Divider(),
                    _ActionTile(
                      key: const ValueKey('settings-cloud-devices'),
                      icon: Icons.devices_outlined,
                      title: strings.text('cloudDevices'),
                      subtitle: strings.text('cloudDevicesSubtitle'),
                      onTap: _cloudSyncBusy ? null : _showCloudDevices,
                    ),
                    const Divider(),
                    _ActionTile(
                      icon: Icons.logout_rounded,
                      title: strings.text('cloudLogout'),
                      subtitle: strings.text('cloudLogoutSubtitle'),
                      onTap: _cloudSyncBusy ? null : _logoutCloudSync,
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
        subtitle:
            subtitle ??
            AppStrings.of(context).text('cloudMasterPasswordPromptSubtitle'),
        icon: icon,
      ),
    );
  }

  Future<_CloudLoginInput?> _showCloudLoginDialog(BuildContext context) {
    return showDialog<_CloudLoginInput>(
      context: context,
      builder: (context) => _CloudLoginDialog(
        title: AppStrings.of(context).text('cloudLogin'),
        submitLabel: AppStrings.of(context).text('login'),
      ),
    );
  }

  Future<_CloudLoginInput?> _showCloudRegisterDialog(BuildContext context) {
    return showDialog<_CloudLoginInput>(
      context: context,
      builder: (context) => _CloudLoginDialog(
        title: AppStrings.of(context).text('cloudRegister'),
        submitLabel: AppStrings.of(context).text('register'),
        emailFieldKey: ValueKey('cloud-register-email-field'),
        passwordFieldKey: ValueKey('cloud-register-password-field'),
        validateRegistrationPassword: true,
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

  void _setCloudSyncStatus(
    String key, {
    int? importedCount,
    int? conflictCount,
    int? deviceCount,
  }) {
    _cloudSyncStatusKey = key;
    _cloudSyncImportedCount = importedCount;
    _cloudSyncConflictCount = conflictCount;
    _cloudSyncDeviceCount = deviceCount;
  }

  String _cloudSyncStatusLabel(AppStrings strings) {
    String connectedLabel(String base) {
      final email = _cloudSyncAccountEmail;
      return email == null || email.isEmpty ? base : '$base · $email';
    }

    return switch (_cloudSyncStatusKey) {
      'cloudConnected' => connectedLabel(strings.text('cloudConnected')),
      'cloudRegisteredConnected' => connectedLabel(
        strings.text('cloudRegisteredConnected'),
      ),
      'cloudSyncConflicts' =>
        '${strings.text('cloudSyncConflictsDetected')} ${_cloudSyncImportedCount ?? 0} ${strings.text('cloudEncryptedUpdates')}, ${_cloudSyncConflictCount ?? 0} ${strings.text('cloudUnresolvedConflicts')}',
      'cloudSynced' =>
        '${strings.text('cloudSyncedImported')} ${_cloudSyncImportedCount ?? 0} ${strings.text('cloudEncryptedUpdates')}',
      'cloudDownloaded' =>
        '${strings.text('cloudDownloadedImported')} ${_cloudSyncImportedCount ?? 0} ${strings.text('cloudEncryptedRecords')}',
      'cloudDeviceCount' =>
        '${_cloudSyncDeviceCount ?? 0} ${strings.text('cloudDeviceCountSuffix')}',
      'cloudDeviceRenamed' => strings.text('cloudDeviceRenamed'),
      'cloudDeviceRevoked' => strings.text('cloudDeviceRevoked'),
      'cloudUnavailable' => strings.text('cloudUnavailable'),
      _ => strings.text('cloudNotConnected'),
    };
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
  final String subtitle;
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
              const SizedBox(height: 10),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
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
              label: _copied
                  ? strings.text('copied')
                  : strings.text('copyBackup'),
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

class _CloudLoginDialog extends StatefulWidget {
  const _CloudLoginDialog({
    required this.title,
    required this.submitLabel,
    this.emailFieldKey = const ValueKey('cloud-login-email-field'),
    this.passwordFieldKey = const ValueKey('cloud-login-password-field'),
    this.validateRegistrationPassword = false,
  });

  final String title;
  final String submitLabel;
  final ValueKey<String> emailFieldKey;
  final ValueKey<String> passwordFieldKey;
  final bool validateRegistrationPassword;

  @override
  State<_CloudLoginDialog> createState() => _CloudLoginDialogState();
}

class _CloudLoginDialogState extends State<_CloudLoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordObscured = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
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
              decoration: InputDecoration(labelText: strings.text('email')),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                  return strings.text('enterEmailAddress');
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: widget.passwordFieldKey,
              controller: _passwordController,
              obscureText: _passwordObscured,
              decoration: InputDecoration(
                labelText: strings.text('accountPassword'),
                suffixIcon: IconButton(
                  tooltip: _passwordObscured
                      ? strings.text('showPassword')
                      : strings.text('hidePassword'),
                  onPressed: () =>
                      setState(() => _passwordObscured = !_passwordObscured),
                  icon: Icon(
                    _passwordObscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return strings.text('enterAccountPassword');
                }
                if (widget.validateRegistrationPassword &&
                    value.length < MasterPasswordPolicy.minLength) {
                  return strings.text('cloudRegisterValidationError');
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
          child: Text(strings.text('cancel')),
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
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.text('cloudDevices')),
      content: SizedBox(
        width: 420,
        child: _devices.isEmpty
            ? Text(strings.text('noCloudDevices'))
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
                    subtitle: Text(_formatDeviceMetadata(device, strings)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: ValueKey('cloud-device-rename-${device.id}'),
                          tooltip: strings.text('rename'),
                          onPressed: busy ? null : () => _rename(device),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        TextButton(
                          onPressed: busy ? null : () => _revoke(device.id),
                          child: Text(
                            busy
                                ? strings.text('working')
                                : strings.text('revokeGrant'),
                          ),
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
          child: Text(strings.text('close')),
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
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.text('renameDevice')),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey('cloud-device-rename-field'),
          controller: _controller,
          decoration: InputDecoration(labelText: strings.text('deviceName')),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return strings.text('enterDeviceName');
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) {
              return;
            }
            Navigator.of(context).pop(_controller.text.trim());
          },
          child: Text(strings.text('rename')),
        ),
      ],
    );
  }
}

String _formatDeviceMetadata(SyncDevice device, AppStrings strings) {
  final platform =
      _firstNonBlank(device.platform, device.deviceType) ??
      strings.text('unknownPlatform');
  final clientVersion = _nonBlank(device.clientVersion);
  final lastSyncAt = _nonBlank(device.lastSyncAt);
  final lastIpAddress = _nonBlank(device.lastIpAddress);
  final lastUserAgent = _nonBlank(device.lastUserAgent);
  final values = <String>[
    platform,
    if (clientVersion != null) 'v$clientVersion',
    if (lastSyncAt != null) '${strings.text('lastSync')} $lastSyncAt',
    if (lastIpAddress != null) '${strings.text('ipAddress')} $lastIpAddress',
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

class _CloudLoginInput {
  const _CloudLoginInput({required this.email, required this.password});

  final String email;
  final String password;
}
