import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/master_password_policy.dart';
import 'package:secure_box/shared/widgets/activity_text_form_field.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';
import 'package:secure_box/features/setup/privacy_policy_page.dart';

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
  MasterPasswordPolicyResult _passwordStrength = MasterPasswordPolicy.evaluate(
    '',
  );

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SecureVisualBackground(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 80),
            const Center(
              child: SecureIconBadge(icon: Icons.lock_rounded, size: 58),
            ),
            const SizedBox(height: 12),
            Text(
              '创建主密码',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '主密码不会上传，也无法找回。请务必牢记。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            SecureGlassCard(
              padding: const EdgeInsets.all(14),
              child: Form(
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
                      onChanged: _updatePasswordStrength,
                      validator: _validatePassword,
                    ),
                    if (_passwordController.text.isNotEmpty &&
                        _passwordStrength.isAcceptable) ...[
                      const SizedBox(height: 8),
                      _PasswordStrengthHint(strength: _passwordStrength),
                    ],
                    const SizedBox(height: 10),
                    ActivityTextFormField(
                      controller: _confirmPasswordController,
                      onActivity: widget.services.recordActivity,
                      obscureText: _confirmPasswordObscured,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: '确认主密码',
                        suffixIcon: IconButton(
                          tooltip: _confirmPasswordObscured
                              ? '显示确认密码'
                              : '隐藏确认密码',
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SecureGlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: SecureVisualColors.blue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.fingerprint_rounded),
                ),
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
                  '生物识别仅用于快速解锁本地密码库，失败仍需输入主密码。',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SecureGradientButton(
              onPressed: _submitting ? null : _submit,
              label: _submitting ? '创建中...' : '创建密码库',
            ),
            const SizedBox(height: 12),
            SecureGlassCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_rounded,
                    color: SecureVisualColors.blue,
                    size: 58,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.lock_outline, size: 16, color: SecureVisualColors.blue),
                              const SizedBox(width: 8),
                              Text('主密码仅存储在设备本地', style: theme.textTheme.bodySmall),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.visibility_off_outlined, size: 16, color: SecureVisualColors.blue),
                              const SizedBox(width: 8),
                              Text('无法查看或恢复你的主密码', style: theme.textTheme.bodySmall),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.shield_outlined, size: 16, color: SecureVisualColors.blue),
                              const SizedBox(width: 8),
                              Text('数据采用端到端加密保护', style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const PrivacyPolicyPage(),
                  ),
                );
              },
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '继续操作即表示你已经阅读并同意 ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    TextSpan(
                      text: '隐私政策',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: SecureVisualColors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _validatePassword(String? value) {
    final result = MasterPasswordPolicy.evaluate(value ?? '');
    return result.isAcceptable ? null : result.message;
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
      if (_biometricEnabled && biometricResult == BiometricSetupResult.failed) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码库已创建，但未能启用生物识别。')));
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

  void _updatePasswordStrength(String value) {
    setState(() {
      _passwordStrength = MasterPasswordPolicy.evaluate(value);
    });
  }

  void _toggleConfirmPasswordVisibility() {
    widget.services.recordActivity();
    setState(() {
      _confirmPasswordObscured = !_confirmPasswordObscured;
    });
  }
}

class _PasswordStrengthHint extends StatelessWidget {
  const _PasswordStrengthHint({required this.strength});

  final MasterPasswordPolicyResult strength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = switch (strength.label) {
      MasterPasswordStrengthLabel.weak => colorScheme.error,
      MasterPasswordStrengthLabel.fair => colorScheme.tertiary,
      MasterPasswordStrengthLabel.strong => colorScheme.primary,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (strength.score.clamp(0, 5) / 5).toDouble(),
            minHeight: 6,
            backgroundColor: colorScheme.surfaceContainerHighest,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          strength.message,
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
