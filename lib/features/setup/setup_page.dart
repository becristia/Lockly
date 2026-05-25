import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/master_password_policy.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/i18n/password_policy_strings.dart';
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
    _passwordController.clear();
    _confirmPasswordController.clear();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

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
              strings.text('setupTitle'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              strings.text('setupSubtitle'),
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
                        labelText: strings.text('masterPassword'),
                        helperText: strings.text('passwordMinLength'),
                        suffixIcon: IconButton(
                          tooltip: _passwordObscured
                              ? strings.text('showMasterPassword')
                              : strings.text('hideMasterPassword'),
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
                        labelText: strings.text('confirmMasterPassword'),
                        suffixIcon: IconButton(
                          tooltip: _confirmPasswordObscured
                              ? strings.text('showConfirmPassword')
                              : strings.text('hideConfirmPassword'),
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
                title: Text(strings.text('enableBiometricQuickUnlock')),
                subtitle: Text(
                  strings.text('biometricSetupSubtitle'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SecureGradientButton(
              onPressed: _submitting ? null : _submit,
              label: _submitting
                  ? strings.text('creatingVault')
                  : strings.text('createVault'),
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
                              Icon(
                                Icons.lock_outline,
                                size: 16,
                                color: SecureVisualColors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                strings.text('setupLocalOnly'),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.visibility_off_outlined,
                                size: 16,
                                color: SecureVisualColors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                strings.text('setupCannotRecover'),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 16,
                                color: SecureVisualColors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                strings.text('setupEncrypted'),
                                style: theme.textTheme.bodySmall,
                              ),
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
                      text: strings.text('privacyAgreementPrefix'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    TextSpan(
                      text: strings.text('privacyPolicy'),
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
    return result.isAcceptable
        ? null
        : localizedMasterPasswordPolicyMessage(
            result,
            AppStrings.of(context),
          );
  }

  String? _validateConfirmPassword(String? value) {
    final strings = AppStrings.of(context);
    if ((value ?? '').isEmpty) {
      return strings.text('enterMasterPasswordAgain');
    }
    if (value != _passwordController.text) {
      return strings.text('passwordMismatch');
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
        ).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context).text('vaultCreatedBiometricFailed')),
          ),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('createVaultFailed'))),
      );
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
    final strings = AppStrings.of(context);
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
          localizedMasterPasswordPolicyMessage(strength, strings),
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
