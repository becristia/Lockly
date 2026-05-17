import 'package:flutter/material.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class SecureScaffold extends StatelessWidget {
  const SecureScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.footer,
    this.icon = Icons.lock_outline_rounded,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? footer;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SecureVisualBackground(
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: SecureIconBadge(icon: icon)),
                const SizedBox(height: 22),
                Center(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SecureGlassCard(
                  padding: const EdgeInsets.all(18),
                  borderRadius: 20,
                  child: body,
                ),
                if (footer != null) ...[
                  const SizedBox(height: 20),
                  Center(child: footer!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
