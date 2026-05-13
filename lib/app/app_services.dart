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
    Future<void> Function(String masterPassword, bool enableBiometric)?
    createVaultOverride,
    Future<bool> Function(String masterPassword)? unlockOverride,
    Future<bool> Function()? biometricEnabledOverride,
    Future<bool> Function()? biometricUnlockOverride,
    bool trackActivity = true,
  }) : _hasVault = hasVault,
       _vaultService = vaultService,
       _biometricService = biometricService,
       _clipboardService = clipboardService,
       _createVaultOverride = createVaultOverride,
       _unlockOverride = unlockOverride,
       _biometricEnabledOverride = biometricEnabledOverride,
       _biometricUnlockOverride = biometricUnlockOverride,
       _trackActivity = trackActivity,
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
  final Future<void> Function(String masterPassword, bool enableBiometric)?
  _createVaultOverride;
  final Future<bool> Function(String masterPassword)? _unlockOverride;
  final Future<bool> Function()? _biometricEnabledOverride;
  final Future<bool> Function()? _biometricUnlockOverride;
  final bool _trackActivity;
  late final AutoLockService autoLockService;
  late final AppLifecycleGuard appLifecycleGuard;

  bool _hasVault;
  int _fakeCreateVaultCalls = 0;
  String? _fakeLastCreateVaultPassword;
  bool? _fakeLastCreateVaultBiometricEnabled;
  int _fakeUnlockCalls = 0;
  int _fakeBiometricUnlockCalls = 0;

  static AppServices fake({
    required bool hasVault,
    bool unlocked = false,
    bool unlockSucceeds = true,
    bool biometricEnabled = false,
    bool biometricUnlockSucceeds = false,
  }) {
    AppServices? fakeServices;
    fakeServices = AppServices(
      hasVault: hasVault,
      initialShellState: hasVault
          ? (unlocked ? AppShellState.unlocked : AppShellState.locked)
          : AppShellState.setupRequired,
      createVaultOverride: (masterPassword, enableBiometric) async {
        fakeServices!._fakeCreateVaultCalls += 1;
        fakeServices._fakeLastCreateVaultPassword = masterPassword;
        fakeServices._fakeLastCreateVaultBiometricEnabled = enableBiometric;
        fakeServices.markVaultCreated();
      },
      unlockOverride: (masterPassword) async {
        fakeServices!._fakeUnlockCalls += 1;
        if (!unlockSucceeds) {
          return false;
        }
        fakeServices.markVaultUnlocked();
        return true;
      },
      biometricEnabledOverride: () async => biometricEnabled,
      biometricUnlockOverride: () async {
        fakeServices!._fakeBiometricUnlockCalls += 1;
        if (!biometricUnlockSucceeds) {
          return false;
        }
        fakeServices.markVaultUnlocked();
        return true;
      },
      trackActivity: false,
    );

    return fakeServices;
  }

  int get fakeCreateVaultCalls => _fakeCreateVaultCalls;

  String? get fakeLastCreateVaultPassword => _fakeLastCreateVaultPassword;

  bool? get fakeLastCreateVaultBiometricEnabled =>
      _fakeLastCreateVaultBiometricEnabled;

  int get fakeUnlockCalls => _fakeUnlockCalls;

  int get fakeBiometricUnlockCalls => _fakeBiometricUnlockCalls;

  Future<void> createVault({
    required String masterPassword,
    required bool enableBiometric,
  }) async {
    final override = _createVaultOverride;
    if (override != null) {
      await override(masterPassword, enableBiometric);
      return;
    }

    await vaultService.createVault(masterPassword: masterPassword);
    if (enableBiometric) {
      try {
        await vaultService.enableBiometricUnlock(
          masterPassword: masterPassword,
          biometricService: biometricService,
        );
      } catch (_) {
        // Setup keeps vault creation successful even if optional biometric
        // enablement is unavailable on the current device.
      }
    }

    markVaultCreated();
  }

  Future<bool> unlockWithMasterPassword(String masterPassword) async {
    final override = _unlockOverride;
    if (override != null) {
      return override(masterPassword);
    }

    try {
      await vaultService.unlock(masterPassword: masterPassword);
    } on VaultUnlockException {
      return false;
    }

    markVaultUnlocked();
    return true;
  }

  Future<bool> isBiometricUnlockEnabled() async {
    final override = _biometricEnabledOverride;
    if (override != null) {
      return override();
    }

    return vaultService.isBiometricUnlockEnabled();
  }

  Future<bool> unlockWithBiometrics() async {
    final override = _biometricUnlockOverride;
    if (override != null) {
      return override();
    }

    final unlocked = await vaultService.unlockWithBiometrics(
      biometricService: biometricService,
    );
    if (unlocked) {
      markVaultUnlocked();
    }
    return unlocked;
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
    if (!_trackActivity) {
      return;
    }
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
