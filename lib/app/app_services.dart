import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:secure_box/core/backup/backup_service.dart';
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
    BackupService? backupService,
    BiometricService? biometricService,
    ClipboardService? clipboardService,
    Duration autoLockTimeout = const Duration(minutes: 2),
    Duration clipboardCleanupTimeout = const Duration(seconds: 30),
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
    Future<void> Function(String oldPassword, String newPassword)?
    changeMasterPasswordOverride,
    Future<void> Function(String masterPassword)? enableBiometricOverride,
    Future<void> Function()? disableBiometricOverride,
    Future<Duration> Function()? autoLockTimeoutOverride,
    Future<void> Function(Duration timeout)? setAutoLockTimeoutOverride,
    Future<Duration> Function()? clipboardCleanupTimeoutOverride,
    Future<void> Function(Duration timeout)? setClipboardCleanupTimeoutOverride,
    Future<String> Function()? exportBackupOverride,
    Future<int> Function(String backupJson, String masterPassword)?
    importBackupOverride,
    Future<void> Function()? clearLocalVaultOverride,
    bool trackActivity = true,
  }) : _hasVault = hasVault,
       _vaultService = vaultService,
       _backupService = backupService,
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
       _changeMasterPasswordOverride = changeMasterPasswordOverride,
       _enableBiometricOverride = enableBiometricOverride,
       _disableBiometricOverride = disableBiometricOverride,
       _autoLockTimeoutOverride = autoLockTimeoutOverride,
       _setAutoLockTimeoutOverride = setAutoLockTimeoutOverride,
       _clipboardCleanupTimeoutOverride = clipboardCleanupTimeoutOverride,
       _setClipboardCleanupTimeoutOverride = setClipboardCleanupTimeoutOverride,
       _exportBackupOverride = exportBackupOverride,
       _importBackupOverride = importBackupOverride,
       _clearLocalVaultOverride = clearLocalVaultOverride,
       _autoLockTimeout = autoLockTimeout,
       _clipboardCleanupTimeout = clipboardCleanupTimeout,
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
  final BackupService? _backupService;
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
  final Future<void> Function(String oldPassword, String newPassword)?
  _changeMasterPasswordOverride;
  final Future<void> Function(String masterPassword)? _enableBiometricOverride;
  final Future<void> Function()? _disableBiometricOverride;
  final Future<Duration> Function()? _autoLockTimeoutOverride;
  final Future<void> Function(Duration timeout)? _setAutoLockTimeoutOverride;
  final Future<Duration> Function()? _clipboardCleanupTimeoutOverride;
  final Future<void> Function(Duration timeout)?
  _setClipboardCleanupTimeoutOverride;
  final Future<String> Function()? _exportBackupOverride;
  final Future<int> Function(String backupJson, String masterPassword)?
  _importBackupOverride;
  final Future<void> Function()? _clearLocalVaultOverride;
  Duration _autoLockTimeout;
  Duration _clipboardCleanupTimeout;
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
    var fakeBiometricEnabled = biometricEnabled;
    var fakeAutoLockTimeout = const Duration(minutes: 2);
    var fakeClipboardCleanupTimeout = const Duration(seconds: 30);

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
      biometricEnabledOverride: () async => fakeBiometricEnabled,
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
      changeMasterPasswordOverride: (oldPassword, newPassword) async {},
      enableBiometricOverride: (masterPassword) async {
        fakeBiometricEnabled = true;
      },
      disableBiometricOverride: () async {
        fakeBiometricEnabled = false;
      },
      autoLockTimeoutOverride: () async => fakeAutoLockTimeout,
      setAutoLockTimeoutOverride: (timeout) async {
        fakeAutoLockTimeout = timeout;
      },
      clipboardCleanupTimeoutOverride: () async => fakeClipboardCleanupTimeout,
      setClipboardCleanupTimeoutOverride: (timeout) async {
        fakeClipboardCleanupTimeout = timeout;
      },
      exportBackupOverride: () async =>
          jsonEncode({'version': 1, 'items': fakeItems.length}),
      importBackupOverride: (backupJson, masterPassword) async => 0,
      clearLocalVaultOverride: () async {
        fakeItems.clear();
        fakeServices!._hasVault = false;
        fakeServices.shellState.value = AppShellState.setupRequired;
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

  Future<void> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final override = _changeMasterPasswordOverride;
    if (override != null) {
      return override(oldPassword, newPassword);
    }

    await vaultService.changeMasterPassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
      beforePersist: _biometricService?.disable,
    );
  }

  Future<void> enableBiometricUnlock(String masterPassword) async {
    final override = _enableBiometricOverride;
    if (override != null) {
      return override(masterPassword);
    }

    return vaultService.enableBiometricUnlock(
      masterPassword: masterPassword,
      biometricService: biometricService,
    );
  }

  Future<void> disableBiometricUnlock() async {
    final override = _disableBiometricOverride;
    if (override != null) {
      return override();
    }

    return vaultService.disableBiometricUnlock(
      biometricService: biometricService,
    );
  }

  Future<Duration> getAutoLockTimeout() async {
    final override = _autoLockTimeoutOverride;
    if (override != null) {
      _autoLockTimeout = await override();
      return _autoLockTimeout;
    }

    final rawValue = await vaultService.repository.settingsDao.getValue(
      'auto_lock_seconds',
    );
    final seconds = rawValue == null ? null : int.tryParse(rawValue);
    if (seconds != null && seconds > 0) {
      _autoLockTimeout = Duration(seconds: seconds);
      autoLockService.updateTimeout(_autoLockTimeout);
    }
    return _autoLockTimeout;
  }

  Future<void> setAutoLockTimeout(Duration timeout) async {
    final override = _setAutoLockTimeoutOverride;
    if (override != null) {
      await override(timeout);
    } else {
      await vaultService.repository.settingsDao.setValue(
        'auto_lock_seconds',
        timeout.inSeconds.toString(),
      );
    }
    _autoLockTimeout = timeout;
    autoLockService.updateTimeout(timeout);
  }

  Future<Duration> getClipboardCleanupTimeout() async {
    final override = _clipboardCleanupTimeoutOverride;
    if (override != null) {
      _clipboardCleanupTimeout = await override();
      return _clipboardCleanupTimeout;
    }

    final rawValue = await vaultService.repository.settingsDao.getValue(
      'clipboard_clear_seconds',
    );
    final seconds = rawValue == null ? null : int.tryParse(rawValue);
    if (seconds != null && seconds > 0) {
      _clipboardCleanupTimeout = Duration(seconds: seconds);
      _clipboardService?.updateClearPasswordAfter(_clipboardCleanupTimeout);
    }
    return _clipboardCleanupTimeout;
  }

  Future<void> setClipboardCleanupTimeout(Duration timeout) async {
    final override = _setClipboardCleanupTimeoutOverride;
    if (override != null) {
      await override(timeout);
    } else {
      await vaultService.repository.settingsDao.setValue(
        'clipboard_clear_seconds',
        timeout.inSeconds.toString(),
      );
    }
    _clipboardCleanupTimeout = timeout;
    _clipboardService?.updateClearPasswordAfter(timeout);
  }

  Future<String> exportEncryptedBackupJson() async {
    final override = _exportBackupOverride;
    if (override != null) {
      return override();
    }

    final backup = await backupService.exportBackup();
    return const JsonEncoder.withIndent('  ').convert(backup.toJson());
  }

  Future<int> importEncryptedBackupJson({
    required String backupJson,
    required String masterPassword,
  }) async {
    final override = _importBackupOverride;
    if (override != null) {
      return override(backupJson, masterPassword);
    }

    final decoded = jsonDecode(backupJson);
    if (decoded is! Map) {
      throw const FormatException('备份内容格式不正确');
    }
    final importedCount = await backupService.importBackup(
      json: Map<String, Object?>.from(decoded),
      masterPassword: masterPassword,
      mode: BackupImportMode.merge,
    );
    _hasVault = true;
    return importedCount;
  }

  Future<void> clearLocalVault() async {
    final override = _clearLocalVaultOverride;
    if (override != null) {
      return override();
    }

    final repository = vaultService.repository;
    await _biometricService?.disable();
    await repository.transaction((txn) async {
      await txn.itemsDao.executor.delete('vault_items');
      await txn.manifestDao.deleteAll();
      await txn.metaDao.executor.delete('vault_meta');
      await txn.settingsDao.executor.delete('settings');
    });
    _vaultService?.lock();
    _hasVault = false;
    shellState.value = AppShellState.setupRequired;
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

  BackupService get backupService {
    final service = _backupService;
    if (service == null) {
      throw StateError('BackupService is unavailable in this app context.');
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
