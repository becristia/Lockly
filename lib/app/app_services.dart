import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:secure_box/core/autofill/android_autofill_service.dart';
import 'package:secure_box/core/backup/backup_service.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';
import 'package:secure_box/core/clipboard/clipboard_service.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_server.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_service.dart';
import 'package:secure_box/core/migration/plaintext_csv_importer.dart';
import 'package:secure_box/core/security/app_lifecycle_guard.dart';
import 'package:secure_box/core/security/auto_lock_service.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/shared/i18n/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppShellState { setupRequired, locked, unlocked }

enum BiometricSetupResult { notRequested, enabled, failed }

class MasterPasswordChangedBiometricCleanupException implements Exception {
  MasterPasswordChangedBiometricCleanupException(this.cause);

  final Object cause;

  @override
  String toString() => 'MasterPasswordChangedBiometricCleanupException: $cause';
}

class AppServices {
  AppServices({
    required bool hasVault,
    VaultService? vaultService,
    BackupService? backupService,
    LanTransferService? lanTransferService,
    AndroidAutofillService androidAutofillService =
        const AndroidAutofillService(),
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
    Future<String> Function({
      required String itemId,
      required String displayName,
      required String mediaType,
      required Uint8List bytes,
    })?
    addVaultBlobOverride,
    Future<List<VaultBlobListItem>> Function(String itemId)?
    listVaultBlobsOverride,
    Future<DecryptedVaultBlob> Function(String blobId)? openVaultBlobOverride,
    Future<void> Function(String blobId)? deleteVaultBlobOverride,
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
    Future<LanTransferSession> Function({
      required List<String> itemIds,
      required bool includeBlobs,
      required bool includeHistory,
      required String senderName,
    })?
    createLanSendSessionOverride,
    Future<void> Function()? cancelLanSendSessionOverride,
    Future<LanTransferImportResult> Function({
      required LanTransferQrPayload payload,
      required String sourceMasterPassword,
    })?
    receiveLanTransferOverride,
    Future<void> Function()? clearLocalVaultOverride,
    Future<HealthReport> Function()? analyzePasswordHealthOverride,
    Future<List<VaultListItem>> Function()? listDeletedItemsOverride,
    Future<void> Function(String id)? restoreItemOverride,
    Future<void> Function(String id)? permanentlyDeleteItemOverride,
    Future<void> Function()? emptyTrashOverride,
    Future<int> Function()? deletedItemCountOverride,
    Future<AndroidAutofillStatus> Function()? autofillStatusOverride,
    Future<void> Function()? openAutofillSettingsOverride,
    bool persistLanguagePreference = false,
    bool trackActivity = true,
  }) : _hasVault = hasVault,
       _vaultService = vaultService,
       _backupService = backupService,
       _lanTransferService = lanTransferService,
       _androidAutofillService = androidAutofillService,
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
       _addVaultBlobOverride = addVaultBlobOverride,
       _listVaultBlobsOverride = listVaultBlobsOverride,
       _openVaultBlobOverride = openVaultBlobOverride,
       _deleteVaultBlobOverride = deleteVaultBlobOverride,
       _changeMasterPasswordOverride = changeMasterPasswordOverride,
       _enableBiometricOverride = enableBiometricOverride,
       _disableBiometricOverride = disableBiometricOverride,
       _autoLockTimeoutOverride = autoLockTimeoutOverride,
       _setAutoLockTimeoutOverride = setAutoLockTimeoutOverride,
       _clipboardCleanupTimeoutOverride = clipboardCleanupTimeoutOverride,
       _setClipboardCleanupTimeoutOverride = setClipboardCleanupTimeoutOverride,
       _exportBackupOverride = exportBackupOverride,
       _importBackupOverride = importBackupOverride,
       _createLanSendSessionOverride = createLanSendSessionOverride,
       _cancelLanSendSessionOverride = cancelLanSendSessionOverride,
       _receiveLanTransferOverride = receiveLanTransferOverride,
       _clearLocalVaultOverride = clearLocalVaultOverride,
       _analyzePasswordHealthOverride = analyzePasswordHealthOverride,
       _listDeletedItemsOverride = listDeletedItemsOverride,
       _restoreItemOverride = restoreItemOverride,
       _permanentlyDeleteItemOverride = permanentlyDeleteItemOverride,
       _emptyTrashOverride = emptyTrashOverride,
       _deletedItemCountOverride = deletedItemCountOverride,
       _autofillStatusOverride = autofillStatusOverride,
       _openAutofillSettingsOverride = openAutofillSettingsOverride,
       _persistLanguagePreferenceEnabled = persistLanguagePreference,
       _autoLockTimeout = autoLockTimeout,
       _clipboardCleanupTimeout = clipboardCleanupTimeout,
       _trackActivity = trackActivity,
       navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>(),
       shellState = ValueNotifier<AppShellState>(
         initialShellState ??
             (hasVault ? AppShellState.locked : AppShellState.setupRequired),
       ) {
    if (_persistLanguagePreferenceEnabled) {
      unawaited(_restoreLanguagePreference());
    }
    autoLockService = AutoLockService(
      timeout: autoLockTimeout,
      onLock: lockVault,
    );
    appLifecycleGuard = AppLifecycleGuard(
      autoLockService: autoLockService,
      clipboardService: _clipboardService,
    );
    shellState.addListener(_syncNavigatorToShellState);
  }

  static const routeSetup = '/setup';
  static const routeUnlock = '/unlock';
  static const routeVault = '/vault';
  static const routeGenerator = '/generator';
  static const routeSettings = '/settings';
  static const routeHealth = '/health';
  static const routeLanSync = '/lan-sync';
  static const routeLanSend = '/lan-sync/send';
  static const routeLanReceive = '/lan-sync/receive';
  static const maxImportedBackupJsonBytes = 8 * 1024 * 1024;
  static const _languagePreferenceKey = 'lockly.language';

  final GlobalKey<NavigatorState> navigatorKey;
  final ValueNotifier<AppShellState> shellState;
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
    ThemeMode.system,
  );
  final ValueNotifier<AppLanguage> languageNotifier = ValueNotifier(
    AppLanguage.zh,
  );

  ThemeMode get themeMode => themeModeNotifier.value;
  set themeMode(ThemeMode mode) {
    themeModeNotifier.value = mode;
  }

  AppLanguage get language => languageNotifier.value;
  set language(AppLanguage value) {
    if (_isDisposed) {
      return;
    }
    _languagePreferenceRevision += 1;
    if (languageNotifier.value != value) {
      languageNotifier.value = value;
    }
    if (_persistLanguagePreferenceEnabled) {
      unawaited(_persistLanguagePreference(value));
    }
  }

  final VaultService? _vaultService;
  final BackupService? _backupService;
  final LanTransferService? _lanTransferService;
  final AndroidAutofillService _androidAutofillService;
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
  final Future<String> Function({
    required String itemId,
    required String displayName,
    required String mediaType,
    required Uint8List bytes,
  })?
  _addVaultBlobOverride;
  final Future<List<VaultBlobListItem>> Function(String itemId)?
  _listVaultBlobsOverride;
  final Future<DecryptedVaultBlob> Function(String blobId)?
  _openVaultBlobOverride;
  final Future<void> Function(String blobId)? _deleteVaultBlobOverride;
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
  final Future<LanTransferSession> Function({
    required List<String> itemIds,
    required bool includeBlobs,
    required bool includeHistory,
    required String senderName,
  })?
  _createLanSendSessionOverride;
  final Future<void> Function()? _cancelLanSendSessionOverride;
  final Future<LanTransferImportResult> Function({
    required LanTransferQrPayload payload,
    required String sourceMasterPassword,
  })?
  _receiveLanTransferOverride;
  final Future<void> Function()? _clearLocalVaultOverride;
  final Future<HealthReport> Function()? _analyzePasswordHealthOverride;
  final Future<List<VaultListItem>> Function()? _listDeletedItemsOverride;
  final Future<void> Function(String id)? _restoreItemOverride;
  final Future<void> Function(String id)? _permanentlyDeleteItemOverride;
  final Future<void> Function()? _emptyTrashOverride;
  final Future<int> Function()? _deletedItemCountOverride;
  final Future<AndroidAutofillStatus> Function()? _autofillStatusOverride;
  final Future<void> Function()? _openAutofillSettingsOverride;
  final bool _persistLanguagePreferenceEnabled;
  Duration _autoLockTimeout;
  Duration _clipboardCleanupTimeout;
  final bool _trackActivity;
  late final AutoLockService autoLockService;
  late final AppLifecycleGuard appLifecycleGuard;

  bool _hasVault;
  bool _isDisposed = false;
  int _languagePreferenceRevision = 0;
  int _fakeCreateVaultCalls = 0;
  String? _fakeLastCreateVaultPassword;
  bool? _fakeLastCreateVaultBiometricEnabled;
  int _fakeUnlockCalls = 0;
  int _fakeBiometricUnlockCalls = 0;
  int _masterUnlockFailureCount = 0;
  Timer? _masterUnlockRetryTimer;

  static AppServices fake({
    required bool hasVault,
    bool unlocked = false,
    bool unlockSucceeds = true,
    bool biometricEnabled = false,
    bool biometricUnlockSucceeds = false,
    List<PasswordEntry> initialVaultItems = const <PasswordEntry>[],
    Future<HealthReport> Function()? analyzePasswordHealthOverride,
    Future<LanTransferSession> Function({
      required List<String> itemIds,
      required bool includeBlobs,
      required bool includeHistory,
      required String senderName,
    })?
    createLanSendSessionOverride,
    Future<void> Function()? cancelLanSendSessionOverride,
    Future<LanTransferImportResult> Function({
      required LanTransferQrPayload payload,
      required String sourceMasterPassword,
    })?
    receiveLanTransferOverride,
    bool autofillSupported = false,
    bool autofillEnabled = false,
    Future<void> Function()? openAutofillSettingsOverride,
    bool persistLanguagePreference = false,
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
      listDeletedItemsOverride: () async {
        final items =
            fakeItems.entries
                .where((entry) => entry.value.deletedAt != null)
                .map(
                  (entry) => VaultListItem(
                    id: entry.key,
                    title: entry.value.entry.title,
                    website: entry.value.entry.website,
                    username: entry.value.entry.username,
                    tags: entry.value.entry.tags,
                    createdAt: entry.value.createdAt,
                    updatedAt: entry.value.updatedAt,
                    deletedAt: entry.value.deletedAt,
                  ),
                )
                .toList()
              ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
        return List.unmodifiable(items);
      },
      restoreItemOverride: (id) async {
        final existing = fakeItems[id];
        if (existing == null || existing.deletedAt == null) {
          throw VaultItemNotFoundException(id);
        }
        fakeTimestamp += 1;
        fakeItems[id] = existing.copyWith(
          updatedAt: fakeTimestamp,
          deletedAt: null,
        );
      },
      permanentlyDeleteItemOverride: (id) async {
        final existing = fakeItems[id];
        if (existing == null || existing.deletedAt == null) {
          throw VaultItemNotFoundException(id);
        }
        fakeItems.remove(id);
      },
      emptyTrashOverride: () async {
        fakeItems.removeWhere((key, value) => value.deletedAt != null);
      },
      deletedItemCountOverride: () async {
        return fakeItems.values.where((item) => item.deletedAt != null).length;
      },
      autofillStatusOverride: () async => AndroidAutofillStatus(
        supported: autofillSupported,
        enabled: autofillEnabled,
      ),
      openAutofillSettingsOverride: openAutofillSettingsOverride ?? () async {},
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
      createLanSendSessionOverride: createLanSendSessionOverride,
      cancelLanSendSessionOverride: cancelLanSendSessionOverride,
      receiveLanTransferOverride: receiveLanTransferOverride,
      clearLocalVaultOverride: () async {
        fakeItems.clear();
        fakeServices!._hasVault = false;
        fakeServices.shellState.value = AppShellState.setupRequired;
      },
      analyzePasswordHealthOverride: analyzePasswordHealthOverride,
      persistLanguagePreference: persistLanguagePreference,
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
    if (_masterUnlockRetryTimer?.isActive ?? false) {
      return false;
    }

    final override = _unlockOverride;
    if (override != null) {
      final unlocked = await override(masterPassword);
      if (unlocked) {
        _resetMasterUnlockThrottle();
        markVaultUnlocked();
      } else {
        _recordMasterUnlockFailure();
      }
      return unlocked;
    }

    try {
      await vaultService.unlock(masterPassword: masterPassword);
    } on VaultUnlockException {
      _recordMasterUnlockFailure();
      return false;
    } on VaultIntegrityException {
      lockVault();
      rethrow;
    }

    _resetMasterUnlockThrottle();
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

    final unlocked = await _lockShellOnIntegrity(
      () =>
          vaultService.unlockWithBiometrics(biometricService: biometricService),
    );
    if (unlocked) {
      _resetMasterUnlockThrottle();
      markVaultUnlocked();
    }
    return unlocked;
  }

  Future<List<VaultListItem>> listVaultItems({String query = ''}) async {
    final override = _listItemsOverride;
    if (override != null) {
      return override(query);
    }

    return _lockShellOnIntegrity(() => vaultService.listItems(query: query));
  }

  Future<PasswordEntry> getVaultItem(String id) async {
    final override = _getItemOverride;
    if (override != null) {
      return override(id);
    }

    return _lockShellOnIntegrity(() => vaultService.getItem(id));
  }

  Future<String> createVaultItem(PasswordEntry entry) async {
    final override = _createItemOverride;
    if (override != null) {
      return override(entry);
    }

    return _lockShellOnIntegrity(() => vaultService.createItem(entry));
  }

  Future<void> updateVaultItem(String id, PasswordEntry entry) async {
    final override = _updateItemOverride;
    if (override != null) {
      return override(id, entry);
    }

    return _lockShellOnIntegrity(() => vaultService.updateItem(id, entry));
  }

  Future<void> deleteVaultItem(String id) async {
    final override = _deleteItemOverride;
    if (override != null) {
      return override(id);
    }

    return _lockShellOnIntegrity(() => vaultService.deleteItem(id));
  }

  Future<String> addVaultBlob({
    required String itemId,
    required String displayName,
    required String mediaType,
    required Uint8List bytes,
  }) async {
    final override = _addVaultBlobOverride;
    if (override != null) {
      return override(
        itemId: itemId,
        displayName: displayName,
        mediaType: mediaType,
        bytes: bytes,
      );
    }

    return _lockShellOnIntegrity(
      () => vaultService.addBlob(
        itemId: itemId,
        displayName: displayName,
        mediaType: mediaType,
        bytes: bytes,
      ),
    );
  }

  Future<List<VaultBlobListItem>> listVaultBlobs(String itemId) async {
    final override = _listVaultBlobsOverride;
    if (override != null) {
      return override(itemId);
    }

    return _lockShellOnIntegrity(() => vaultService.listBlobs(itemId));
  }

  Future<DecryptedVaultBlob> openVaultBlob(String blobId) async {
    final override = _openVaultBlobOverride;
    if (override != null) {
      return override(blobId);
    }

    return _lockShellOnIntegrity(() => vaultService.openBlob(blobId));
  }

  Future<void> deleteVaultBlob(String blobId) async {
    final override = _deleteVaultBlobOverride;
    if (override != null) {
      return override(blobId);
    }

    return _lockShellOnIntegrity(() => vaultService.deleteBlob(blobId));
  }

  Future<List<TotpListItem>> listTotpItems() async {
    return _lockShellOnIntegrity(vaultService.listTotpItems);
  }

  Future<List<String>> allTags() async =>
      _lockShellOnIntegrity(vaultService.allTags);

  Future<void> renameTag(String oldTag, String newTag) async =>
      _lockShellOnIntegrity(() => vaultService.renameTag(oldTag, newTag));

  Future<void> deleteTag(String tag) async =>
      _lockShellOnIntegrity(() => vaultService.deleteTag(tag));

  Future<List<VaultListItem>> listDeletedItems() async {
    final override = _listDeletedItemsOverride;
    if (override != null) return override();
    return _lockShellOnIntegrity(vaultService.listDeletedItems);
  }

  Future<void> restoreItem(String id) async {
    final override = _restoreItemOverride;
    if (override != null) return override(id);
    return _lockShellOnIntegrity(() => vaultService.restoreItem(id));
  }

  Future<void> permanentlyDeleteItem(String id) async {
    final override = _permanentlyDeleteItemOverride;
    if (override != null) return override(id);
    return _lockShellOnIntegrity(() => vaultService.permanentlyDeleteItem(id));
  }

  Future<void> emptyTrash() async {
    final override = _emptyTrashOverride;
    if (override != null) return override();
    return _lockShellOnIntegrity(vaultService.emptyTrash);
  }

  Future<int> deletedItemCount() async {
    final override = _deletedItemCountOverride;
    if (override != null) return override();
    return _lockShellOnIntegrity(vaultService.deletedItemCount);
  }

  Future<HealthReport> analyzePasswordHealth() async {
    final override = _analyzePasswordHealthOverride;
    if (override != null) return override();
    return _lockShellOnIntegrity(
      () => vaultService.analyzePasswordHealth(
        healthService: PasswordHealthService(),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> listPasswordHistory(String entryId) async {
    try {
      return await vaultService.listPasswordHistory(entryId);
    } on VaultIntegrityException {
      lockVault();
      rethrow;
    }
  }

  Future<void> restorePassword(String entryId, int historyId) async {
    try {
      return await vaultService.restorePassword(entryId, historyId);
    } on VaultIntegrityException {
      lockVault();
      rethrow;
    }
  }

  Future<void> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final override = _changeMasterPasswordOverride;
    if (override != null) {
      return override(oldPassword, newPassword);
    }

    await _lockShellOnIntegrity(
      () => vaultService.changeMasterPassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
        biometricService: _biometricService,
      ),
    );
  }

  Future<void> enableBiometricUnlock(String masterPassword) async {
    final override = _enableBiometricOverride;
    if (override != null) {
      return override(masterPassword);
    }

    return _lockShellOnIntegrity(
      () => vaultService.enableBiometricUnlock(
        masterPassword: masterPassword,
        biometricService: biometricService,
      ),
    );
  }

  Future<void> disableBiometricUnlock() async {
    final override = _disableBiometricOverride;
    if (override != null) {
      return override();
    }

    return _lockShellOnIntegrity(
      () => vaultService.disableBiometricUnlock(
        biometricService: biometricService,
      ),
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

    final backup = await _lockShellOnIntegrity(backupService.exportBackup);
    return const JsonEncoder.withIndent('  ').convert(backup.toJson());
  }

  Future<String> exportEncryptedItemBackupJson(String itemId) async {
    final backup = await _lockShellOnIntegrity(
      () => backupService.exportItemBackup(itemId),
    );
    return const JsonEncoder.withIndent('  ').convert(backup.toJson());
  }

  Future<String> exportLanTransferBackupJson({
    required List<String> itemIds,
    required bool includeBlobs,
    required bool includeHistory,
  }) async {
    final backup = await _lockShellOnIntegrity(
      () => backupService.exportSelectedItemsBackup(
        itemIds: itemIds,
        includeBlobs: includeBlobs,
        includeHistory: includeHistory,
      ),
    );
    return const JsonEncoder.withIndent('  ').convert(backup.toJson());
  }

  PlaintextCsvImportReport previewPlaintextCsvImport(String csvText) {
    return PlaintextCsvImporter.preview(csvText);
  }

  Future<int> importPlaintextCsv(String csvText) async {
    final entries = PlaintextCsvImporter.parseEntries(csvText);
    for (final entry in entries) {
      await createVaultItem(entry);
    }
    return entries.length;
  }

  Future<int> importEncryptedBackupJson({
    required String backupJson,
    required String masterPassword,
    BackupImportMode mode = BackupImportMode.skip,
  }) async {
    if (backupJson.length > maxImportedBackupJsonBytes) {
      throw const FormatException('Backup JSON is too large to import safely');
    }

    final override = _importBackupOverride;
    if (override != null) {
      return override(backupJson, masterPassword);
    }

    final decoded = jsonDecode(backupJson);
    if (decoded is! Map) {
      throw const FormatException('备份内容格式不正确');
    }
    final importedCount = await _lockShellOnIntegrity(
      () => backupService.importBackup(
        json: Map<String, Object?>.from(decoded),
        masterPassword: masterPassword,
        mode: mode,
      ),
    );
    _hasVault = true;
    shellState.value = vaultService.isUnlocked
        ? AppShellState.unlocked
        : AppShellState.locked;
    return importedCount;
  }

  Future<ConflictAwareBackupImportResult> importLanTransferBackupJson({
    required String backupJson,
    required String sourceMasterPassword,
  }) async {
    if (backupJson.length > maxImportedBackupJsonBytes) {
      throw const FormatException('Backup JSON is too large to import safely');
    }

    final decoded = jsonDecode(backupJson);
    if (decoded is! Map) {
      throw const FormatException('Backup JSON root must be an object');
    }
    final result = await _lockShellOnIntegrity(
      () => backupService.importBackupSkippingIdentityConflicts(
        json: Map<String, Object?>.from(decoded),
        masterPassword: sourceMasterPassword,
      ),
    );
    _hasVault = true;
    shellState.value = vaultService.isUnlocked
        ? AppShellState.unlocked
        : AppShellState.locked;
    return result;
  }

  Future<LanTransferSession> createLanSendSession({
    required List<String> itemIds,
    required bool includeBlobs,
    required bool includeHistory,
    required String senderName,
  }) async {
    final override = _createLanSendSessionOverride;
    if (override != null) {
      return override(
        itemIds: itemIds,
        includeBlobs: includeBlobs,
        includeHistory: includeHistory,
        senderName: senderName,
      );
    }

    return _lockShellOnIntegrity(
      () => lanTransferService.createSendSession(
        itemIds: itemIds,
        includeBlobs: includeBlobs,
        includeHistory: includeHistory,
        senderName: senderName,
      ),
    );
  }

  Future<LanTransferImportResult> receiveLanTransfer({
    required LanTransferQrPayload payload,
    required String sourceMasterPassword,
  }) async {
    final override = _receiveLanTransferOverride;
    if (override != null) {
      return override(
        payload: payload,
        sourceMasterPassword: sourceMasterPassword,
      );
    }

    return _lockShellOnIntegrity(
      () => lanTransferService.receiveFromPayload(
        payload: payload,
        sourceMasterPassword: sourceMasterPassword,
      ),
    );
  }

  Future<void> cancelLanSendSession() {
    final override = _cancelLanSendSessionOverride;
    if (override != null) {
      return override();
    }
    return lanTransferService.cancelSendSession();
  }

  Future<void> clearLocalVault() async {
    await _cancelActiveLanSendSession();

    final override = _clearLocalVaultOverride;
    if (override != null) {
      return override();
    }

    await _biometricService?.disable();
    await vaultService.clearLocalVault();
    _hasVault = false;
    shellState.value = AppShellState.setupRequired;
  }

  Future<bool> copyUsername(String username) {
    return clipboardService.copyUsername(username);
  }

  Future<bool> copyPassword(String password) {
    return clipboardService.copyPassword(password);
  }

  Future<bool> copySensitiveTemporary(
    String value, {
    Duration clearAfter = const Duration(seconds: 30),
  }) {
    return clipboardService.copySensitiveTemporary(
      value,
      clearAfter: clearAfter,
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

  BackupService get backupService {
    final service = _backupService;
    if (service == null) {
      throw StateError('BackupService is unavailable in this app context.');
    }
    return service;
  }

  LanTransferService get lanTransferService {
    final service = _lanTransferService;
    if (service == null) {
      throw StateError(
        'LanTransferService is unavailable in this app context.',
      );
    }
    return service;
  }

  Future<AndroidAutofillStatus> getAndroidAutofillStatus() {
    final override = _autofillStatusOverride;
    if (override != null) {
      return override();
    }
    return _androidAutofillService.status();
  }

  Future<void> openAndroidAutofillSettings() {
    final override = _openAutofillSettingsOverride;
    if (override != null) {
      return override();
    }
    return _androidAutofillService.openSettings();
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
      routeVault ||
      routeGenerator ||
      routeSettings ||
      routeLanSync ||
      routeLanSend ||
      routeLanReceive => requested,
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
    unawaited(_cancelActiveLanSendSession());
    final clipboardClear = _clipboardService?.clearPendingPasswordNow();
    if (clipboardClear != null) {
      unawaited(clipboardClear);
    }
    _vaultService?.lock();
    shellState.value = _hasVault
        ? AppShellState.locked
        : AppShellState.setupRequired;
  }

  Future<T> _lockShellOnIntegrity<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on VaultIntegrityException {
      lockVault();
      rethrow;
    }
  }

  Future<void> _restoreLanguagePreference() async {
    final revision = _languagePreferenceRevision;
    try {
      final preferences = await SharedPreferences.getInstance();
      final restoredLanguage = AppLanguageX.parse(
        preferences.getString(_languagePreferenceKey),
      );
      if (_isDisposed || revision != _languagePreferenceRevision) {
        return;
      }
      if (languageNotifier.value != restoredLanguage) {
        languageNotifier.value = restoredLanguage;
      }
    } catch (error, stackTrace) {
      if (_isDisposed) {
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'secure_box',
          context: ErrorDescription('while restoring language preference'),
        ),
      );
    }
  }

  Future<void> _persistLanguagePreference(AppLanguage value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_languagePreferenceKey, value.code);
    } catch (error, stackTrace) {
      if (_isDisposed) {
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'secure_box',
          context: ErrorDescription('while saving language preference'),
        ),
      );
    }
  }

  void dispose() {
    unawaited(_cancelActiveLanSendSession());
    _isDisposed = true;
    shellState.removeListener(_syncNavigatorToShellState);
    WidgetsBinding.instance.removeObserver(appLifecycleGuard);
    autoLockService.dispose();
    _masterUnlockRetryTimer?.cancel();
    _clipboardService?.dispose();
    shellState.dispose();
    themeModeNotifier.dispose();
    languageNotifier.dispose();
  }

  Future<void> _cancelActiveLanSendSession() {
    final service = _lanTransferService;
    if (service == null) {
      return Future<void>.value();
    }
    return service.cancelSendSession();
  }

  void _syncNavigatorToShellState() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    final targetRoute = currentRouteName;
    navigator.pushNamedAndRemoveUntil(targetRoute, (route) => false);
  }

  void _recordMasterUnlockFailure() {
    _masterUnlockFailureCount += 1;
    final delay = _masterUnlockDelayForFailures(_masterUnlockFailureCount);
    if (delay == Duration.zero) {
      return;
    }

    _masterUnlockRetryTimer?.cancel();
    _masterUnlockRetryTimer = Timer(delay, () {
      _masterUnlockRetryTimer = null;
    });
  }

  void _resetMasterUnlockThrottle() {
    _masterUnlockFailureCount = 0;
    _masterUnlockRetryTimer?.cancel();
    _masterUnlockRetryTimer = null;
  }

  Duration _masterUnlockDelayForFailures(int failures) {
    if (failures < 2) {
      return Duration.zero;
    }

    final seconds = failures >= 5 ? 8 : 1 << (failures - 2);
    return Duration(seconds: seconds);
  }
}

class _FakeVaultItem {
  const _FakeVaultItem({
    required this.entry,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  static const _sentinel = Object();

  final PasswordEntry entry;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  _FakeVaultItem copyWith({
    PasswordEntry? entry,
    int? updatedAt,
    Object? deletedAt = _sentinel,
  }) {
    return _FakeVaultItem(
      entry: entry ?? this.entry,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: identical(deletedAt, _sentinel)
          ? this.deletedAt
          : deletedAt as int?,
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
