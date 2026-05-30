import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';

class WindowsWindowFrame extends StatefulWidget {
  const WindowsWindowFrame({super.key, required this.child});

  static const double chromeHeight = 34;

  final Widget child;

  @override
  State<WindowsWindowFrame> createState() => _WindowsWindowFrameState();
}

class _WindowsWindowFrameState extends State<WindowsWindowFrame> {
  late final OverlayEntry _frameEntry = OverlayEntry(builder: _buildFrame);

  @override
  void didUpdateWidget(covariant WindowsWindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _frameEntry.markNeedsBuild();
  }

  @override
  void dispose() {
    if (_frameEntry.mounted) {
      _frameEntry.remove();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return widget.child;
    }

    return Overlay(initialEntries: [_frameEntry]);
  }

  Widget _buildFrame(BuildContext context) {
    return Stack(
      key: const ValueKey('windows-window-frame'),
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          top: WindowsWindowFrame.chromeHeight,
          child: KeyedSubtree(
            key: const ValueKey('windows-window-content'),
            child: widget.child,
          ),
        ),
        const Positioned(
          top: 0,
          right: 0,
          height: WindowsWindowFrame.chromeHeight,
          child: WindowsWindowControls(),
        ),
      ],
    );
  }
}

class WindowsWindowControls extends StatelessWidget {
  const WindowsWindowControls({super.key});

  static const MethodChannel _channel = MethodChannel('lockly/window');

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Material(
      key: const ValueKey('windows-window-controls'),
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WindowChromeButton(
            key: const ValueKey('windows-window-minimize'),
            tooltip: strings.text('windowMinimize'),
            icon: Icons.remove_rounded,
            onPressed: () => _channel.invokeMethod<void>('minimize'),
          ),
          _WindowChromeButton(
            key: const ValueKey('windows-window-close'),
            tooltip: strings.text('windowExit'),
            icon: Icons.close_rounded,
            isClose: true,
            onPressed: () => _channel.invokeMethod<void>('close'),
          ),
        ],
      ),
    );
  }
}

class _WindowChromeButton extends StatelessWidget {
  const _WindowChromeButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurface.withValues(alpha: 0.72);
    final closeForeground = theme.colorScheme.error;

    return Semantics(
      label: tooltip,
      button: true,
      child: SizedBox(
        width: 42,
        height: WindowsWindowFrame.chromeHeight,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            shape: const RoundedRectangleBorder(),
            foregroundColor: isClose ? closeForeground : foreground,
            hoverColor: isClose
                ? theme.colorScheme.errorContainer.withValues(alpha: 0.72)
                : theme.colorScheme.primaryContainer.withValues(alpha: 0.44),
          ),
          iconSize: 18,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
