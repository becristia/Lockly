import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
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
    _retryTimer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SecureVisualBackground(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 18),
            const SecureIconBadge(icon: Icons.lock_rounded, size: 106),
            const SizedBox(height: 24),
            Text(
              '解锁密码库',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 26,
                height: 1.05,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '输入主密码以解锁本地加密密码库。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 22),
            SecureGlassCard(
              padding: const EdgeInsets.all(0),
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
                  labelText: '主密码',
                  errorText: _errorText,
                  floatingLabelStyle: const TextStyle(fontSize: 12),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
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
              label: _submitting ? '解锁中...' : '解锁',
            ),
            if (_biometricEnabled) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _submitting ? null : _unlockWithBiometrics,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('使用生物识别'),
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
                    '连续输错后会短暂延迟重试\n以降低暴力尝试风险',
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
      unlocked = await widget.services.unlockWithMasterPassword(
        _passwordController.text,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _errorText = null;
        _retryMessage = '暂时无法解锁，请重试';
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
      _errorText = '主密码不正确';
      _retryMessage = delay > Duration.zero
          ? '请等待 ${delay.inSeconds} 秒后重试'
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
        _retryMessage = '请使用主密码解锁';
      });
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _submitting = false;
      if (!unlocked) {
        _retryMessage = '请使用主密码解锁';
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
