import 'package:flutter/material.dart';

class SecureVisualColors {
  static const navy = Color(0xFF0F172A);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const blue = Color(0xFF0284C7);
  static const cyan = Color(0xFF06B6D4);
  static const paleBlue = Color(0xFFF0F9FF);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE2EEF7);
  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFB7791F);
  static const softSurface = Color(0xFFFCFEFF);
  static const amberSurface = Color(0xFFFFF7E6);
  static const dangerSurface = Color(0xFFFFF1F0);
  static const successSurface = Color(0xFFEAF7EE);
}

class SecureVisualBackground extends StatelessWidget {
  const SecureVisualBackground({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 24),
    this.bottomInset = 0,
    this.maxContentWidth = 1180,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double bottomInset;
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
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
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxContentWidth ?? double.infinity,
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomInset),
                      child: child,
                    ),
                  ),
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
          color: SecureVisualColors.blue.withValues(alpha: 0.032),
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
    this.borderRadius = 12,
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
    final theme = Theme.of(context);
    final effectiveRadius = borderRadius.clamp(0, 14).toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(effectiveRadius),
        border: Border.all(color: borderColor ?? theme.colorScheme.outline),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: SecureVisualColors.navy.withValues(alpha: 0.035),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class SecureStatusSurface extends StatelessWidget {
  const SecureStatusSurface({
    super.key,
    required this.child,
    required this.color,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 12,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class SecureIconTile extends StatelessWidget {
  const SecureIconTile({
    super.key,
    required this.icon,
    this.color = SecureVisualColors.blue,
    this.size = 42,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

class SecureActionButton extends StatelessWidget {
  const SecureActionButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.height = 52,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FilledButton(onPressed: onPressed, child: child),
    );
  }
}

class SecureMetricCard extends StatelessWidget {
  const SecureMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = SecureVisualColors.blue,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return SecureStatusSurface(
      color: color,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SecureIconTile(icon: icon, color: color, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
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
    this.height = 52,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SecureActionButton(
      onPressed: onPressed,
      label: label,
      icon: icon,
      height: height,
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
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Center(
        child: Container(
          width: size * 0.56,
          height: size * 0.56,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.32),
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
    final onSurface = theme.colorScheme.onSurface;
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
                  color: onSurface,
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
    final onSurface = theme.colorScheme.onSurface;
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
                  color: onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onSurface.withValues(alpha: 0.78),
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
