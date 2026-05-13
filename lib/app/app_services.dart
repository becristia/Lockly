import 'package:flutter/material.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';
import 'package:secure_box/core/clipboard/clipboard_service.dart';
import 'package:secure_box/core/security/app_lifecycle_guard.dart';
import 'package:secure_box/core/security/auto_lock_service.dart';
import 'package:secure_box/core/vault/vault_service.dart';

enum AppShellState { setupRequired, locked, unlocked }

class AppServices {
  AppServices({
    required bool hasVault,
    VaultService? vaultService,
    BiometricService? biometricService,
    ClipboardService? clipboardService,
    Duration autoLockTimeout = const Duration(minutes: 2),
    AppShellState? initialShellState,
    GlobalKey<NavigatorState>? navigatorKey,
  }) : _hasVault = hasVault,
       _vaultService = vaultService,
       _biometricService = biometricService,
       _clipboardService = clipboardService,
       navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>(),
       shellState = ValueNotifier<AppShellState>(
         initialShellState ??
             (hasVault ? AppShellState.locked : AppShellState.setupRequired),
       ) {
    autoLockService = AutoLockService(
      timeout: autoLockTimeout,
      onLock: lockVault,
    );
    appLifecycleGuard = AppLifecycleGuard(autoLockService: autoLockService);
    shellState.addListener(_syncNavigatorToShellState);
  }

  static const routeSetup = '/setup';
  static const routeUnlock = '/unlock';
  static const routeVault = '/vault';
  static const routeGenerator = '/generator';
  static const routeSettings = '/settings';

  final GlobalKey<NavigatorState> navigatorKey;
  final ValueNotifier<AppShellState> shellState;
  final VaultService? _vaultService;
  final BiometricService? _biometricService;
  final ClipboardService? _clipboardService;
  late final AutoLockService autoLockService;
  late final AppLifecycleGuard appLifecycleGuard;

  bool _hasVault;

  static AppServices fake({required bool hasVault, bool unlocked = false}) {
    return AppServices(
      hasVault: hasVault,
      initialShellState: hasVault
          ? (unlocked ? AppShellState.unlocked : AppShellState.locked)
          : AppShellState.setupRequired,
    );
  }

  bool get hasVault => _hasVault;

  VaultService get vaultService {
    final service = _vaultService;
    if (service == null) {
      throw StateError('VaultService is unavailable in this app context.');
    }
    return service;
  }

  BiometricService get biometricService {
    final service = _biometricService;
    if (service == null) {
      throw StateError('BiometricService is unavailable in this app context.');
    }
    return service;
  }

  ClipboardService get clipboardService {
    final service = _clipboardService;
    if (service == null) {
      throw StateError('ClipboardService is unavailable in this app context.');
    }
    return service;
  }

  String get currentRouteName => routeNameFor(shellState.value);

  String routeNameFor(AppShellState state) {
    return switch (state) {
      AppShellState.setupRequired => routeSetup,
      AppShellState.locked => routeUnlock,
      AppShellState.unlocked => routeVault,
    };
  }

  String resolveRouteName(String? requestedRouteName) {
    final shellRoute = currentRouteName;
    final requested = requestedRouteName ?? shellRoute;
    final shell = shellState.value;
    if (shell != AppShellState.unlocked) {
      return shellRoute;
    }

    return switch (requested) {
      routeVault || routeGenerator || routeSettings => requested,
      _ => routeVault,
    };
  }

  void recordActivity() {
    autoLockService.recordActivity();
  }

  void markVaultCreated({bool unlocked = false}) {
    _hasVault = true;
    shellState.value = unlocked ? AppShellState.unlocked : AppShellState.locked;
    if (unlocked) {
      recordActivity();
    }
  }

  void markVaultUnlocked() {
    if (!_hasVault) {
      throw StateError('Cannot unlock a vault that does not exist.');
    }
    shellState.value = AppShellState.unlocked;
    recordActivity();
  }

  void lockVault() {
    _vaultService?.lock();
    shellState.value = _hasVault
        ? AppShellState.locked
        : AppShellState.setupRequired;
  }

  void dispose() {
    shellState.removeListener(_syncNavigatorToShellState);
    WidgetsBinding.instance.removeObserver(appLifecycleGuard);
    autoLockService.dispose();
    _clipboardService?.dispose();
    shellState.dispose();
  }

  void _syncNavigatorToShellState() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    final targetRoute = currentRouteName;
    navigator.pushNamedAndRemoveUntil(targetRoute, (route) => false);
  }
}
