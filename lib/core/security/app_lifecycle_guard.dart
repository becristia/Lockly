import 'package:flutter/widgets.dart';
import 'package:secure_box/core/clipboard/clipboard_service.dart';
import 'package:secure_box/core/security/auto_lock_service.dart';

class AppLifecycleGuard with WidgetsBindingObserver {
  AppLifecycleGuard({required this.autoLockService, this.clipboardService});

  final AutoLockService autoLockService;
  final ClipboardService? clipboardService;
  bool _hasLockedSinceResume = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _hasLockedSinceResume = false;
        return;
      case AppLifecycleState.inactive:
        return;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        clipboardService?.clearPendingPasswordNow();
        if (_hasLockedSinceResume) {
          return;
        }

        _hasLockedSinceResume = true;
        autoLockService.lockNow();
    }
  }
}
