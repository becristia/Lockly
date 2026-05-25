import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/activity_text_form_field.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key, required this.services});

  final AppServices services;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final TextEditingController _passwordController = TextEditingController();

  bool _passwordObscured = true;
  bool _submitting = false;
  bool _biometricEnabled = false;
  String? _errorText;
  String? _retryMessage;
  int _failedAttempts = 0;
  Timer? _retryTimer;

  bool get _isRetryLocked => _retryTimer?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBiometricAvailability());
  }

  @override
  void dispose() {
    _passwordController.clear();
    _retryTimer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return SecureVisualBackground(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 100),
            const SecureIconBadge(icon: Icons.lock_rounded, size: 106),
            const SizedBox(height: 24),
            Text(
              strings.text('unlockTitle'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 26,
                height: 1.05,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              strings.text('unlockSubtitle'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 22),
            SecureGlassCard(
              padding: const EdgeInsets.all(14),
              color: SecureVisualColors.paleBlue.withValues(alpha: 0.5),
              borderColor: Colors.transparent,
              shadow: false,
              child: ActivityTextFormField(
                controller: _passwordController,
                onActivity: widget.services.recordActivity,
                obscureText: _passwordObscured,
                autofocus: true,
                enabled: !_submitting && !_isRetryLocked,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: strings.text('masterPassword'),
                  errorText: _errorText,
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
                onFieldSubmitted: (_) => _submitUnlock(),
              ),
            ),
            if (_retryMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _retryMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 18),
            SecureGradientButton(
              onPressed: _submitting || _isRetryLocked ? null : _submitUnlock,
              icon: Icons.lock_open_rounded,
              label: _submitting
                  ? strings.text('unlockBusy')
                  : strings.text('unlock'),
            ),
            if (_biometricEnabled) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _submitting ? null : _unlockWithBiometrics,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: Text(strings.text('useBiometric')),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    strings.text('unlockRetryHint'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadBiometricAvailability() async {
    bool enabled;
    try {
      enabled = await widget.services.isBiometricUnlockEnabled();
    } catch (_) {
      enabled = false;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _biometricEnabled = enabled;
    });
  }

  Future<void> _submitUnlock() async {
    widget.services.recordActivity();
    setState(() {
      _submitting = true;
      _errorText = null;
      _retryMessage = _isRetryLocked ? _retryMessage : null;
    });

    final bool unlocked;
    try {
      final masterPassword = _passwordController.text;
      unlocked = await widget.services.unlockWithMasterPassword(masterPassword);
      _passwordController.clear();
    } catch (_) {
      _passwordController.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _errorText = null;
        _retryMessage = AppStrings.of(context).text('unlockRetryFailed');
      });
      return;
    }

    if (!mounted) {
      return;
    }

    if (unlocked) {
      setState(() {
        _submitting = false;
        _failedAttempts = 0;
        _errorText = null;
        _retryMessage = null;
      });
      return;
    }

    final nextFailures = _failedAttempts + 1;
    final delay = _delayForFailures(nextFailures);
    _retryTimer?.cancel();
    if (delay > Duration.zero) {
      _retryTimer = Timer(delay, () {
        if (!mounted) {
          return;
        }
        setState(() {
          _retryMessage = null;
        });
      });
    }

    setState(() {
      _submitting = false;
      _failedAttempts = nextFailures;
      final strings = AppStrings.of(context);
      _errorText = strings.text('wrongMasterPassword');
      _retryMessage = delay > Duration.zero
          ? '${strings.text('waitRetryPrefix')} ${delay.inSeconds} ${strings.text('waitRetrySuffix')}'
          : null;
    });
  }

  Future<void> _unlockWithBiometrics() async {
    widget.services.recordActivity();
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final bool unlocked;
    try {
      unlocked = await widget.services.unlockWithBiometrics();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _retryMessage = AppStrings.of(context).text('useMasterPassword');
      });
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _submitting = false;
      if (!unlocked) {
        _retryMessage = AppStrings.of(context).text('useMasterPassword');
      }
    });
  }

  Duration _delayForFailures(int failures) {
    if (failures < 2) {
      return Duration.zero;
    }

    final seconds = math.min(1 << (failures - 2), 8);
    return Duration(seconds: seconds);
  }

  void _togglePasswordVisibility() {
    widget.services.recordActivity();
    setState(() {
      _passwordObscured = !_passwordObscured;
    });
  }
}
