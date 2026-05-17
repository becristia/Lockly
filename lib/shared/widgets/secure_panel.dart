import 'package:flutter/material.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class SecurePanel extends StatelessWidget {
  const SecurePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SecureGlassCard(
      padding: padding,
      color: color ?? theme.colorScheme.surface.withValues(alpha: 0.92),
      borderColor: borderColor ?? Colors.white,
      child: child,
    );
  }
}

class SecureSection extends StatelessWidget {
  const SecureSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SecureSectionTitle(title: title, subtitle: subtitle, icon: icon),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class SecureStatusPill extends StatelessWidget {
  const SecureStatusPill({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedColor = color ?? theme.colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: resolvedColor.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: resolvedColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: resolvedColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
