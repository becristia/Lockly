import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/master_password_policy.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/features/password_generator/password_generator_page.dart';
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
      setState(() => _isLoading = false);
    } on VaultItemNotFoundException {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _pageError = '这条记录不存在或已删除。';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _pageError = '暂时无法加载记录，请重试。';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这条记录不存在或已删除。')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isEditing ? '编辑密码' : '新增密码';

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
              title: '无法编辑',
              message: _pageError!,
              actionLabel: '重试',
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
                      decoration: const InputDecoration(
                        labelText: '标题',
                        hintText: '例如：公司邮箱',
                        suffixIcon: Icon(Icons.bookmark_border_rounded),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入标题';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ActivityTextFormField(
                      controller: _websiteController,
                      onActivity: widget.services.recordActivity,
                      decoration: const InputDecoration(
                        labelText: '网址',
                        hintText: 'https://example.com',
                        suffixIcon: Icon(Icons.language_rounded),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    ActivityTextFormField(
                      controller: _usernameController,
                      onActivity: widget.services.recordActivity,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        hintText: '用户名或邮箱',
                        suffixIcon: Icon(Icons.person_outline_rounded),
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
                              labelText: '密码',
                              hintText: '输入或生成密码',
                              suffixIcon: IconButton(
                                onPressed: () {
                                  widget.services.recordActivity();
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                                tooltip: _isPasswordVisible ? '隐藏密码' : '显示密码',
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
                                return '请输入密码';
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
                              message: '生成密码',
                              child: const Icon(Icons.key_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _StrengthIndicator(password: _passwordController.text),
                    const SizedBox(height: 14),
                    Text('TOTP 二次验证', style: theme.textTheme.titleSmall),
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
                              label: const Text(
                                '扫描 QR 码',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _showManualTotpInput,
                              icon: const Icon(Icons.edit_rounded, size: 20),
                              label: const Text(
                                '手动输入',
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
                            const Text(
                              'TOTP 已设置',
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
                              child: const Text(
                                '移除',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    ActivityTextFormField(
                      controller: _notesController,
                      onActivity: widget.services.recordActivity,
                      decoration: const InputDecoration(
                        labelText: '备注',
                        hintText: '添加备注信息...',
                      ),
                      keyboardType: TextInputType.multiline,
                      minLines: 5,
                      maxLines: 6,
                    ),
                    const SizedBox(height: 12),
                    ActivityTextFormField(
                      controller: _tagsController,
                      onActivity: widget.services.recordActivity,
                      decoration: const InputDecoration(
                        labelText: '标签',
                        hintText: '选择或创建标签',
                        suffixIcon: Icon(Icons.sell_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SecureGradientButton(
                      onPressed: _isSaving ? null : _save,
                      icon: Icons.lock_rounded,
                      height: 62,
                      label: _isSaving ? '保存中...' : '保存',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showManualTotpInput() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入 TOTP 密钥'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '粘贴 Base32 密钥',
            helperText: '例如：JBSWY3DPEHPK3PXP',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
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
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _scanQrCode() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('QR 码扫描功能需要 camera 权限')));
  }

  static List<String> _parseTags(String rawText) {
    return rawText
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }
}

class _StrengthIndicator extends StatelessWidget {
  const _StrengthIndicator({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final result = MasterPasswordPolicy.evaluate(password);
    final filledBars = result.score.clamp(0, 5);
    final color = switch (result.label) {
      MasterPasswordStrengthLabel.weak => Colors.red,
      MasterPasswordStrengthLabel.fair => Colors.orange,
      MasterPasswordStrengthLabel.strong => Colors.green,
    };

    return Row(
      children: [
        Text('密码强度', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 12),
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
