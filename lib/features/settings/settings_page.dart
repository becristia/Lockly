import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/shared/widgets/secure_scaffold.dart';

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
        if (!mounted) {
          return;
        }
        setState(() => _biometricEnabled = true);
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

  Future<void> _exportBackup() async {
    widget.services.recordActivity();
    try {
      final backupJson = await widget.services.exportEncryptedBackupJson();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导出加密备份'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(child: SelectableText(backupJson)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
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
    final result = await _showBackupImportDialog(context);
    if (result == null) {
      return;
    }
    try {
      final count = await widget.services.importEncryptedBackupJson(
        backupJson: result.backupJson,
        masterPassword: result.masterPassword,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 $count 条加密记录。')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('导入失败，请检查备份内容和主密码。')));
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
    return SecureScaffold(
      title: '设置',
      subtitle: '管理本地密码库、安全解锁、自动锁定和加密备份。',
      body: Column(
        children: [
          _ActionTile(
            icon: Icons.password_rounded,
            title: '修改主密码',
            subtitle: '只重新加密 DEK，不重新加密所有条目。',
            onTap: _changeMasterPassword,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.fingerprint_rounded),
            title: const Text('生物识别'),
            subtitle: const Text('仅用于快速解锁，失败时仍需主密码。'),
            value: _biometricEnabled,
            onChanged: _setBiometricEnabled,
          ),
          _DurationTile(
            icon: Icons.lock_clock_rounded,
            title: '自动锁定',
            value: _autoLockTimeout,
            choices: _autoLockChoices,
            onChanged: _setAutoLockTimeout,
          ),
          _DurationTile(
            icon: Icons.content_paste_off_rounded,
            title: '剪贴板清理',
            value: _clipboardCleanupTimeout,
            choices: _clipboardChoices,
            onChanged: _setClipboardCleanupTimeout,
          ),
          const SizedBox(height: 8),
          _ActionTile(
            icon: Icons.file_upload_outlined,
            title: '导出加密备份',
            subtitle: '导出本地加密备份 JSON。',
            onTap: _exportBackup,
          ),
          _ActionTile(
            icon: Icons.file_download_outlined,
            title: '导入加密备份',
            subtitle: '使用备份主密码验证后导入。',
            onTap: _importBackup,
          ),
          _ActionTile(
            icon: Icons.delete_outline_rounded,
            title: '清除本地密码库',
            subtitle: '删除本机密码库和设置。',
            onTap: _clearLocalVault,
          ),
        ],
      ),
    );
  }

  Future<bool?> _showMasterPasswordChangeDialog(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? errorText;
    var isSaving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('修改主密码'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: oldPasswordController,
                  decoration: const InputDecoration(labelText: '当前主密码'),
                  obscureText: true,
                  validator: _requiredPassword,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newPasswordController,
                  decoration: const InputDecoration(labelText: '新主密码'),
                  obscureText: true,
                  validator: _validateNewPassword,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmPasswordController,
                  decoration: const InputDecoration(labelText: '确认新主密码'),
                  obscureText: true,
                  validator: (value) {
                    if (value != newPasswordController.text) {
                      return '两次输入的主密码不一致';
                    }
                    return null;
                  },
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final form = formKey.currentState;
                      if (form == null || !form.validate()) {
                        return;
                      }
                      setDialogState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await widget.services.changeMasterPassword(
                          oldPassword: oldPasswordController.text,
                          newPassword: newPasswordController.text,
                        );
                        if (context.mounted) {
                          Navigator.of(context).pop(true);
                        }
                      } catch (_) {
                        setDialogState(() {
                          isSaving = false;
                          errorText = '主密码修改失败，请确认当前主密码。';
                        });
                      }
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    oldPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    return result;
  }

  Future<String?> _showMasterPasswordPrompt({
    required String title,
    required String submitLabel,
  }) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(labelText: '主密码'),
            obscureText: true,
            validator: _requiredPassword,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final form = formKey.currentState;
              if (form == null || !form.validate()) {
                return;
              }
              Navigator.of(context).pop(controller.text);
            },
            child: Text(submitLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<_BackupImportInput?> _showBackupImportDialog(
    BuildContext context,
  ) async {
    final formKey = GlobalKey<FormState>();
    final backupController = TextEditingController();
    final passwordController = TextEditingController();

    final result = await showDialog<_BackupImportInput>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入加密备份'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: backupController,
                decoration: const InputDecoration(labelText: '备份 JSON'),
                minLines: 4,
                maxLines: 6,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请粘贴备份内容' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: '备份主密码'),
                obscureText: true,
                validator: _requiredPassword,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final form = formKey.currentState;
              if (form == null || !form.validate()) {
                return;
              }
              Navigator.of(context).pop(
                _BackupImportInput(
                  backupJson: backupController.text,
                  masterPassword: passwordController.text,
                ),
              );
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );

    backupController.dispose();
    passwordController.dispose();
    return result;
  }

  Future<bool?> _showConfirmationDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  static String? _requiredPassword(String? value) {
    if (value == null || value.isEmpty) {
      return '请输入主密码';
    }
    return null;
  }

  static String? _validateNewPassword(String? value) {
    if (value == null || value.length < 12) {
      return '主密码至少需要 12 个字符';
    }
    return null;
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
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

    return ListTile(
      contentPadding: EdgeInsets.zero,
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

class _BackupImportInput {
  const _BackupImportInput({
    required this.backupJson,
    required this.masterPassword,
  });

  final String backupJson;
  final String masterPassword;
}
