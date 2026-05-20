import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/master_password_policy.dart';
import 'package:secure_box/shared/widgets/secure_panel.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

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

  Future<void> _exportBackup() async {
    widget.services.recordActivity();
    try {
      final backupJson = await widget.services.exportEncryptedBackupJson();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _BackupExportDialog(backupJson: backupJson),
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
                      icon: Icons.file_download_outlined,
                      title: '导入加密备份',
                      subtitle: '使用备份主密码验证后导入。',
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

  Future<_BackupImportInput?> _showBackupImportDialog(
    BuildContext context,
  ) async {
    return showDialog<_BackupImportInput>(
      context: context,
      builder: (context) => const _BackupImportDialog(),
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
        child:SecureGlassCard(
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
                      onPressed: () => setState(() => _oldObscured = !_oldObscured),
                      icon: Icon(
                        _oldObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
                      onPressed: () => setState(() => _newObscured = !_newObscured),
                      icon: Icon(
                        _newObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
                      onPressed: () => setState(() => _confirmObscured = !_confirmObscured),
                      icon: Icon(
                        _confirmObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
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

class _BackupImportDialog extends StatefulWidget {
  const _BackupImportDialog();

  @override
  State<_BackupImportDialog> createState() => _BackupImportDialogState();
}

class _BackupImportDialogState extends State<_BackupImportDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _backupController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _backupController.dispose();
    _passwordController.dispose();
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
                const SecureIconBadge(
                  icon: Icons.file_download_outlined,
                  size: 76,
                ),
                const SizedBox(height: 18),
                Text('导入加密备份', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '粘贴加密备份 JSON，并输入备份主密码验证后导入。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _backupController,
                  decoration: const InputDecoration(
                    labelText: '备份 JSON',
                    prefixIcon: Icon(Icons.data_object_rounded),
                  ),
                  minLines: 4,
                  maxLines: 6,
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请粘贴备份内容' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: '备份主密码',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                  obscureText: true,
                  validator: _SettingsPageState._requiredPassword,
                ),
                const SizedBox(height: 22),
                SecureGradientButton(onPressed: _submit, label: '导入'),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
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

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(
      _BackupImportInput(
        backupJson: _backupController.text,
        masterPassword: _passwordController.text,
      ),
    );
  }
}

class _BackupExportDialog extends StatefulWidget {
  const _BackupExportDialog({required this.backupJson});

  final String backupJson;

  @override
  State<_BackupExportDialog> createState() => _BackupExportDialogState();
}

class _BackupExportDialogState extends State<_BackupExportDialog> {
  bool _copied = false;

  Future<void> _copyBackupJson() async {
    await Clipboard.setData(ClipboardData(text: widget.backupJson));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('加密备份已复制。')));
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
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
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

class _BackupImportInput {
  const _BackupImportInput({
    required this.backupJson,
    required this.masterPassword,
  });

  final String backupJson;
  final String masterPassword;
}
