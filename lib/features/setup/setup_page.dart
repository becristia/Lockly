import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/shared/widgets/activity_text_form_field.dart';
import 'package:secure_box/shared/widgets/secure_scaffold.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _passwordObscured = true;
  bool _confirmPasswordObscured = true;
  bool _biometricEnabled = false;
  bool _submitting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SecureScaffold(
      title: '创建主密码',
      subtitle: '主密码不会上传，也无法找回。请务必牢记。',
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ActivityTextFormField(
              controller: _passwordController,
              onActivity: widget.services.recordActivity,
              obscureText: _passwordObscured,
              autofocus: true,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: '主密码',
                helperText: '至少 12 个字符',
                suffixIcon: IconButton(
                  tooltip: _passwordObscured ? '显示主密码' : '隐藏主密码',
                  onPressed: _togglePasswordVisibility,
                  icon: Icon(
                    _passwordObscured
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: _validatePassword,
            ),
            const SizedBox(height: 12),
            ActivityTextFormField(
              controller: _confirmPasswordController,
              onActivity: widget.services.recordActivity,
              obscureText: _confirmPasswordObscured,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: '确认主密码',
                suffixIcon: IconButton(
                  tooltip: _confirmPasswordObscured ? '显示确认密码' : '隐藏确认密码',
                  onPressed: _toggleConfirmPasswordVisibility,
                  icon: Icon(
                    _confirmPasswordObscured
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: _validateConfirmPassword,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _biometricEnabled,
              onChanged: _submitting
                  ? null
                  : (value) {
                      widget.services.recordActivity();
                      setState(() {
                        _biometricEnabled = value;
                      });
                    },
              title: const Text('启用生物识别快速解锁'),
              subtitle: Text(
                '仅用于快速解锁本地密码库，失败时仍需输入主密码。',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? '创建中...' : '创建密码库'),
              ),
            ),
          ],
        ),
      ),
      footer: Text(
        '生物识别仅用于快速解锁，设备重装或安全区失效后仍需依赖主密码恢复。',
        style: theme.textTheme.bodyMedium,
      ),
    );
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 12) {
      return '主密码至少需要 12 个字符';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if ((value ?? '').isEmpty) {
      return '请再次输入主密码';
    }
    if (value != _passwordController.text) {
      return '两次输入的主密码不一致';
    }
    return null;
  }

  Future<void> _submit() async {
    widget.services.recordActivity();
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final biometricResult = await widget.services.createVault(
        masterPassword: _passwordController.text,
        enableBiometric: _biometricEnabled,
      );
      if (!mounted) {
        return;
      }
      if (_biometricEnabled &&
          biometricResult == BiometricSetupResult.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码库已创建，但未能启用生物识别。')),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('创建失败，请稍后重试')));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _togglePasswordVisibility() {
    widget.services.recordActivity();
    setState(() {
      _passwordObscured = !_passwordObscured;
    });
  }

  void _toggleConfirmPasswordVisibility() {
    widget.services.recordActivity();
    setState(() {
      _confirmPasswordObscured = !_confirmPasswordObscured;
    });
  }
}
