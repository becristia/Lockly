import 'package:flutter/widgets.dart';
import 'package:secure_box/core/security/auto_lock_service.dart';

class AppLifecycleGuard with WidgetsBindingObserver {
  AppLifecycleGuard({required this.autoLockService});

  final AutoLockService autoLockService;
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
        if (_hasLockedSinceResume) {
          return;
        }

        _hasLockedSinceResume = true;
        autoLockService.lockNow();
    }
  }
}
