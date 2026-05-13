import 'package:flutter/material.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';
import 'package:secure_box/core/clipboard/clipboard_service.dart';
import 'package:secure_box/core/security/app_lifecycle_guard.dart';
import 'package:secure_box/core/security/auto_lock_service.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/password_entry.dart';

enum AppShellState { setupRequired, locked, unlocked }

enum BiometricSetupResult { notRequested, enabled, failed }

class AppServices {
  AppServices({
    required bool hasVault,
    VaultService? vaultService,
    BiometricService? biometricService,
    ClipboardService? clipboardService,
    Duration autoLockTimeout = const Duration(minutes: 2),
    AppShellState? initialShellState,
    GlobalKey<NavigatorState>? navigatorKey,
    Future<BiometricSetupResult> Function(
      String masterPassword,
      bool enableBiometric,
    )?
    createVaultOverride,
    Future<bool> Function(String masterPassword)? unlockOverride,
    Future<bool> Function()? biometricEnabledOverride,
    Future<bool> Function()? biometricUnlockOverride,
    Future<List<VaultListItem>> Function(String query)? listItemsOverride,
    Future<PasswordEntry> Function(String id)? getItemOverride,
    Future<String> Function(PasswordEntry entry)? createItemOverride,
    Future<void> Function(String id, PasswordEntry entry)? updateItemOverride,
    Future<void> Function(String id)? deleteItemOverride,
    bool trackActivity = true,
  }) : _hasVault = hasVault,
       _vaultService = vaultService,
       _biometricService = biometricService,
       _clipboardService = clipboardService,
       _createVaultOverride = createVaultOverride,
       _unlockOverride = unlockOverride,
       _biometricEnabledOverride = biometricEnabledOverride,
       _biometricUnlockOverride = biometricUnlockOverride,
       _listItemsOverride = listItemsOverride,
       _getItemOverride = getItemOverride,
       _createItemOverride = createItemOverride,
       _updateItemOverride = updateItemOverride,
       _deleteItemOverride = deleteItemOverride,
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
  final Future<BiometricSetupResult> Function(
    String masterPassword,
    bool enableBiometric,
  )?
  _createVaultOverride;
  final Future<bool> Function(String masterPassword)? _unlockOverride;
  final Future<bool> Function()? _biometricEnabledOverride;
  final Future<bool> Function()? _biometricUnlockOverride;
  final Future<List<VaultListItem>> Function(String query)? _listItemsOverride;
  final Future<PasswordEntry> Function(String id)? _getItemOverride;
  final Future<String> Function(PasswordEntry entry)? _createItemOverride;
  final Future<void> Function(String id, PasswordEntry entry)?
  _updateItemOverride;
  final Future<void> Function(String id)? _deleteItemOverride;
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
    List<PasswordEntry> initialVaultItems = const <PasswordEntry>[],
  }) {
    AppServices? fakeServices;
    final fakeItems = <String, _FakeVaultItem>{};
    var fakeItemCounter = 0;
    var fakeTimestamp = DateTime.now().millisecondsSinceEpoch;

    void seedItems() {
      for (final entry in initialVaultItems) {
        fakeItemCounter += 1;
        fakeTimestamp += 1;
        fakeItems['item-$fakeItemCounter'] = _FakeVaultItem(
          entry: entry,
          createdAt: fakeTimestamp,
          updatedAt: fakeTimestamp,
        );
      }
    }

    seedItems();
    fakeServices = AppServices(
      hasVault: hasVault,
      clipboardService: ClipboardService(),
      initialShellState: hasVault
          ? (unlocked ? AppShellState.unlocked : AppShellState.locked)
          : AppShellState.setupRequired,
      createVaultOverride: (masterPassword, enableBiometric) async {
        fakeServices!._fakeCreateVaultCalls += 1;
        fakeServices._fakeLastCreateVaultPassword = masterPassword;
        fakeServices._fakeLastCreateVaultBiometricEnabled = enableBiometric;
        return enableBiometric
            ? BiometricSetupResult.enabled
            : BiometricSetupResult.notRequested;
      },
      unlockOverride: (masterPassword) async {
        fakeServices!._fakeUnlockCalls += 1;
        return unlockSucceeds;
      },
      biometricEnabledOverride: () async => biometricEnabled,
      biometricUnlockOverride: () async {
        fakeServices!._fakeBiometricUnlockCalls += 1;
        return biometricUnlockSucceeds;
      },
      listItemsOverride: (query) async {
        final normalizedQuery = query.trim().toLowerCase();
        final items =
            fakeItems.entries
                .where((entry) => entry.value.deletedAt == null)
                .where((entry) {
                  if (normalizedQuery.isEmpty) {
                    return true;
                  }
                  return _matchesFakeQuery(
                    entry: entry.value.entry,
                    query: normalizedQuery,
                  );
                })
                .map(
                  (entry) => VaultListItem(
                    id: entry.key,
                    title: entry.value.entry.title,
                    website: entry.value.entry.website,
                    username: entry.value.entry.username,
                    tags: entry.value.entry.tags,
                    createdAt: entry.value.createdAt,
                    updatedAt: entry.value.updatedAt,
                  ),
                )
                .toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return List.unmodifiable(items);
      },
      getItemOverride: (id) async {
        final item = fakeItems[id];
        if (item == null || item.deletedAt != null) {
          throw VaultItemNotFoundException(id);
        }
        return item.entry;
      },
      createItemOverride: (entry) async {
        fakeItemCounter += 1;
        fakeTimestamp += 1;
        final id = 'item-$fakeItemCounter';
        fakeItems[id] = _FakeVaultItem(
          entry: entry,
          createdAt: fakeTimestamp,
          updatedAt: fakeTimestamp,
        );
        return id;
      },
      updateItemOverride: (id, entry) async {
        final existing = fakeItems[id];
        if (existing == null || existing.deletedAt != null) {
          throw VaultItemNotFoundException(id);
        }
        fakeTimestamp += 1;
        fakeItems[id] = existing.copyWith(
          entry: entry,
          updatedAt: fakeTimestamp,
        );
      },
      deleteItemOverride: (id) async {
        final existing = fakeItems[id];
        if (existing == null || existing.deletedAt != null) {
          throw VaultItemNotFoundException(id);
        }
        fakeTimestamp += 1;
        fakeItems[id] = existing.copyWith(
          updatedAt: fakeTimestamp,
          deletedAt: fakeTimestamp,
        );
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

  Future<BiometricSetupResult> createVault({
    required String masterPassword,
    required bool enableBiometric,
  }) async {
    final override = _createVaultOverride;
    if (override != null) {
      final result = await override(masterPassword, enableBiometric);
      markVaultCreated();
      return result;
    }

    await vaultService.createVault(masterPassword: masterPassword);
    var biometricResult = BiometricSetupResult.notRequested;
    if (enableBiometric) {
      try {
        await vaultService.enableBiometricUnlock(
          masterPassword: masterPassword,
          biometricService: biometricService,
        );
        biometricResult = BiometricSetupResult.enabled;
      } catch (_) {
        biometricResult = BiometricSetupResult.failed;
      }
    }

    markVaultCreated();
    return biometricResult;
  }

  Future<bool> unlockWithMasterPassword(String masterPassword) async {
    final override = _unlockOverride;
    if (override != null) {
      final unlocked = await override(masterPassword);
      if (unlocked) {
        markVaultUnlocked();
      }
      return unlocked;
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
      final unlocked = await override();
      if (unlocked) {
        markVaultUnlocked();
      }
      return unlocked;
    }

    final unlocked = await vaultService.unlockWithBiometrics(
      biometricService: biometricService,
    );
    if (unlocked) {
      markVaultUnlocked();
    }
    return unlocked;
  }

  Future<List<VaultListItem>> listVaultItems({String query = ''}) async {
    final override = _listItemsOverride;
    if (override != null) {
      return override(query);
    }

    return vaultService.listItems(query: query);
  }

  Future<PasswordEntry> getVaultItem(String id) async {
    final override = _getItemOverride;
    if (override != null) {
      return override(id);
    }

    return vaultService.getItem(id);
  }

  Future<String> createVaultItem(PasswordEntry entry) async {
    final override = _createItemOverride;
    if (override != null) {
      return override(entry);
    }

    return vaultService.createItem(entry);
  }

  Future<void> updateVaultItem(String id, PasswordEntry entry) async {
    final override = _updateItemOverride;
    if (override != null) {
      return override(id, entry);
    }

    return vaultService.updateItem(id, entry);
  }

  Future<void> deleteVaultItem(String id) async {
    final override = _deleteItemOverride;
    if (override != null) {
      return override(id);
    }

    return vaultService.deleteItem(id);
  }

  Future<bool> copyUsername(String username) {
    return clipboardService.copyUsername(username);
  }

  Future<bool> copyPassword(String password) {
    return clipboardService.copyPassword(password);
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

class _FakeVaultItem {
  const _FakeVaultItem({
    required this.entry,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final PasswordEntry entry;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  _FakeVaultItem copyWith({
    PasswordEntry? entry,
    int? updatedAt,
    int? deletedAt,
  }) {
    return _FakeVaultItem(
      entry: entry ?? this.entry,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

bool _matchesFakeQuery({required PasswordEntry entry, required String query}) {
  final searchableValues = [
    entry.title,
    entry.website,
    entry.username,
    entry.notes,
    ...entry.tags,
  ];

  return searchableValues.any((value) => value.toLowerCase().contains(query));
}
