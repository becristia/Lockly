import 'dart:ui';

import 'package:flutter/material.dart';

class SecureVisualColors {
  static const navy = Color(0xFF08224A);
  static const text = Color(0xFF0B2855);
  static const muted = Color(0xFF6D7F9B);
  static const blue = Color(0xFF0B66F6);
  static const cyan = Color(0xFF24D3E7);
  static const paleBlue = Color(0xFFEAF5FF);
  static const card = Color(0xF7FFFFFF);
  static const line = Color(0xFFDDE9F6);
  static const danger = Color(0xFFE33C32);
  static const success = Color(0xFF55B965);
  static const warning = Color(0xFFF5A623);
  static const softSurface = Color(0xFFF7FBFF);
}

class SecureVisualBackground extends StatelessWidget {
  const SecureVisualBackground({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 24),
    this.bottomInset = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.28,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFF2F9FF),
              Color(0xFFEAF5FF),
            ],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: 80,
              right: -26,
              child: _SecureBackgroundMark(
                icon: Icons.shield_outlined,
                size: 120,
              ),
            ),
            const Positioned(
              bottom: 118,
              left: -28,
              child: _SecureBackgroundMark(
                icon: Icons.local_offer_outlined,
                size: 110,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: padding,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecureBackgroundMark extends StatelessWidget {
  const _SecureBackgroundMark({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: -0.42,
        child: Icon(
          icon,
          size: size,
          color: SecureVisualColors.blue.withValues(alpha: 0.045),
        ),
      ),
    );
  }
}

class SecureGlassCard extends StatelessWidget {
  const SecureGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 20,
    this.color,
    this.borderColor,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? color;
  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? SecureVisualColors.card,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.86),
              width: 1.2,
            ),
            boxShadow: shadow
                ? [
                    BoxShadow(
                      color: const Color(0xFF7DADE3).withValues(alpha: 0.18),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ]
                : null,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SecureGradientButton extends StatelessWidget {
  const SecureGradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.height = 58,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: disabled
              ? null
              : const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFF0B65F0), Color(0xFF28D7E4)],
                ),
          color: disabled ? const Color(0xFFD4E0EF) : null,
          borderRadius: BorderRadius.circular(18),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: SecureVisualColors.blue.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
        ),
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
          label: Text(label),
        ),
      ),
    );
  }
}

class SecureIconBadge extends StatelessWidget {
  const SecureIconBadge({
    super.key,
    required this.icon,
    this.size = 70,
    this.color = SecureVisualColors.blue,
  });

  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, color.withValues(alpha: 0.12)],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.58,
          height: size * 0.58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.95), const Color(0xFF78C8FF)],
            ),
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.34),
        ),
      ),
    );
  }
}

class SecureSectionTitle extends StatelessWidget {
  const SecureSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.color = SecureVisualColors.blue,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: SecureVisualColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class SecureReplicaHeader extends StatelessWidget {
  const SecureReplicaHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: SecureVisualColors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: SecureVisualColors.text.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
