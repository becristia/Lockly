import 'package:flutter/material.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class SecureDialog extends StatelessWidget {
  const SecureDialog({
    super.key,
    this.icon,
    required this.title,
    this.message,
    this.child,
    required this.actions,
    this.destructive = false,
  }) : assert(message != null || child != null);

  final IconData? icon;
  final String title;
  final String? message;
  final Widget? child;
  final List<SecureDialogAction> actions;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final maxDialogHeight = MediaQuery.sizeOf(context).height - 48;
    final hasBody = message != null || child != null;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          minWidth: 280,
          maxHeight: maxDialogHeight.clamp(320.0, double.infinity).toDouble(),
        ),
        child: SecureGlassCard(
          borderRadius: 20,
          padding: const EdgeInsets.all(24),
          color: theme.colorScheme.surface.withValues(alpha: 0.92),
          borderColor: theme.colorScheme.outlineVariant,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Center(
                  child: SecureIconBadge(icon: icon!, color: color, size: 72),
                ),
                const SizedBox(height: 18),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (hasBody) const SizedBox(height: 14),
              if (hasBody)
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (message != null)
                          Text(
                            message!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        if (message != null && child != null)
                          const SizedBox(height: 18),
                        ?child,
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              SecureDialogActions(actions: actions),
            ],
          ),
        ),
      ),
    );
  }
}

class SecureDialogActions extends StatelessWidget {
  const SecureDialogActions({super.key, required this.actions});

  final List<SecureDialogAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < actions.length; index += 1) ...[
          actions[index],
          if (index != actions.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class SecureDialogAction extends StatelessWidget {
  const SecureDialogAction._({
    super.key,
    required this.label,
    required this.onPressed,
    required _SecureDialogActionKind kind,
    this.icon,
    this.actionKey,
    this.enabled = true,
    this.busy = false,
  }) : _kind = kind;

  factory SecureDialogAction.cancel(
    BuildContext context, {
    VoidCallback? onPressed,
    bool enabled = true,
  }) {
    return SecureDialogAction._(
      label: AppStrings.of(context).text('cancel'),
      onPressed: onPressed ?? () => Navigator.of(context).pop(),
      kind: _SecureDialogActionKind.cancel,
      actionKey: const ValueKey('secure-dialog-cancel-action'),
      enabled: enabled,
    );
  }

  factory SecureDialogAction.close(
    BuildContext context, {
    VoidCallback? onPressed,
    bool enabled = true,
  }) {
    return SecureDialogAction._(
      label: AppStrings.of(context).text('close'),
      onPressed: onPressed ?? () => Navigator.of(context).pop(),
      kind: _SecureDialogActionKind.cancel,
      actionKey: const ValueKey('secure-dialog-close-action'),
      enabled: enabled,
    );
  }

  factory SecureDialogAction.primary({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool enabled = true,
    bool busy = false,
  }) {
    return SecureDialogAction._(
      key: key,
      label: label,
      onPressed: onPressed,
      kind: _SecureDialogActionKind.primary,
      icon: icon,
      enabled: enabled,
      busy: busy,
    );
  }

  factory SecureDialogAction.secondary({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool enabled = true,
    bool busy = false,
  }) {
    return SecureDialogAction._(
      key: key,
      label: label,
      onPressed: onPressed,
      kind: _SecureDialogActionKind.secondary,
      icon: icon,
      enabled: enabled,
      busy: busy,
    );
  }

  factory SecureDialogAction.destructive({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool enabled = true,
    bool busy = false,
  }) {
    return SecureDialogAction._(
      key: key,
      label: label,
      onPressed: onPressed,
      kind: _SecureDialogActionKind.destructive,
      icon: icon,
      enabled: enabled,
      busy: busy,
    );
  }

  final String label;
  final VoidCallback? onPressed;
  final _SecureDialogActionKind _kind;
  final IconData? icon;
  final Key? actionKey;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveOnPressed = enabled && !busy ? onPressed : null;
    final child = busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : icon == null
        ? Text(label, textAlign: TextAlign.center)
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
      key: actionKey,
      width: double.infinity,
      child: switch (_kind) {
        _SecureDialogActionKind.cancel => OutlinedButton(
          onPressed: effectiveOnPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.72),
            foregroundColor: theme.colorScheme.onSurface,
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: child,
        ),
        _SecureDialogActionKind.secondary => OutlinedButton(
          onPressed: effectiveOnPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.52),
            foregroundColor: theme.colorScheme.primary,
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: child,
        ),
        _SecureDialogActionKind.primary => FilledButton(
          onPressed: effectiveOnPressed,
          child: child,
        ),
        _SecureDialogActionKind.destructive => FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: child,
        ),
      },
    );
  }
}

enum _SecureDialogActionKind { cancel, secondary, primary, destructive }
