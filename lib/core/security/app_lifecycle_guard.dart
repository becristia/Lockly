import 'package:flutter/widgets.dart';
import 'package:secure_box/core/security/auto_lock_service.dart';

class AppLifecycleGuard with WidgetsBindingObserver {
  AppLifecycleGuard({required this.autoLockService});

  final AutoLockService autoLockService;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        autoLockService.lockNow();
    }
  }
}
