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
import 'package:secure_box/core/sync/sync_api_client.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/core/sync/sync_service.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/db/sync_state_dao.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/shared/i18n/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppShellState { setupRequired, locked, unlocked }

enum BiometricSetupResult { notRequested, enabled, failed }

class CloudSyncResult {
  const CloudSyncResult({
    required this.importedCount,
    this.itemConflictCount = 0,
    this.blobConflictCount = 0,
  });

  final int importedCount;
  final int itemConflictCount;
  final int blobConflictCount;

  int get conflictCount => itemConflictCount + blobConflictCount;

  bool get hasConflicts => conflictCount > 0;
}

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
    SyncService? syncService,
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
    Future<LanTransferImportResult> Function({
      required LanTransferQrPayload payload,
      required String sourceMasterPassword,
    })?
    receiveLanTransferOverride,
    Future<void> Function(String email, String password)? cloudRegisterOverride,
    Future<void> Function(String email, String password)? cloudLoginOverride,
    Future<void> Function()? cloudLogoutOverride,
    Future<String?> Function()? cloudAccountEmailOverride,
    Future<CloudSyncResult> Function(String masterPassword)?
    cloudSyncNowOverride,
    Future<int> Function(String masterPassword)? cloudDownloadOverride,
    Future<List<SyncDevice>> Function()? listCloudDevicesOverride,
    Future<void> Function(String deviceId)? revokeCloudDeviceOverride,
    Future<SyncDevice> Function(String deviceId, String deviceName)?
    renameCloudDeviceOverride,
    Future<List<SyncConflictRecord>> Function()? listSyncConflictsOverride,
    Future<List<SyncBlobConflictRecord>> Function()?
    listSyncBlobConflictsOverride,
    Future<List<EmergencyContact>> Function()? listEmergencyContactsOverride,
    Future<EmergencyContact> Function({
      required EmergencyContactCreateRequest request,
    })?
    createEmergencyContactOverride,
    Future<EmergencyContact> Function(String contactId)?
    revokeEmergencyContactOverride,
    Future<List<EmergencyGrant>> Function()? listEmergencyGrantsOverride,
    Future<EmergencyGrant> Function({
      required EmergencyGrantCreateRequest request,
    })?
    createEmergencyGrantOverride,
    Future<EmergencyGrant> Function({
      required String grantId,
      required String recipientKeyFingerprint,
    })?
    acceptEmergencyGrantOverride,
    Future<EmergencyGrant> Function({
      required String grantId,
      String? requestMessageCiphertext,
      String? requestMessageAad,
    })?
    requestEmergencyGrantAccessOverride,
    Future<EmergencyGrant> Function(String grantId)?
    cancelEmergencyGrantOverride,
    Future<EmergencyGrant> Function(String grantId)?
    revokeEmergencyGrantOverride,
    Future<EmergencyAccessPackage> Function(String grantId)?
    downloadEmergencyAccessPackageOverride,
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
       _syncService = syncService,
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
       _receiveLanTransferOverride = receiveLanTransferOverride,
       _cloudRegisterOverride = cloudRegisterOverride,
       _cloudLoginOverride = cloudLoginOverride,
       _cloudLogoutOverride = cloudLogoutOverride,
       _cloudAccountEmailOverride = cloudAccountEmailOverride,
       _cloudSyncNowOverride = cloudSyncNowOverride,
       _cloudDownloadOverride = cloudDownloadOverride,
       _listCloudDevicesOverride = listCloudDevicesOverride,
       _revokeCloudDeviceOverride = revokeCloudDeviceOverride,
       _renameCloudDeviceOverride = renameCloudDeviceOverride,
       _listSyncConflictsOverride = listSyncConflictsOverride,
       _listSyncBlobConflictsOverride = listSyncBlobConflictsOverride,
       _listEmergencyContactsOverride = listEmergencyContactsOverride,
       _createEmergencyContactOverride = createEmergencyContactOverride,
       _revokeEmergencyContactOverride = revokeEmergencyContactOverride,
       _listEmergencyGrantsOverride = listEmergencyGrantsOverride,
       _createEmergencyGrantOverride = createEmergencyGrantOverride,
       _acceptEmergencyGrantOverride = acceptEmergencyGrantOverride,
       _requestEmergencyGrantAccessOverride =
           requestEmergencyGrantAccessOverride,
       _cancelEmergencyGrantOverride = cancelEmergencyGrantOverride,
       _revokeEmergencyGrantOverride = revokeEmergencyGrantOverride,
       _downloadEmergencyAccessPackageOverride =
           downloadEmergencyAccessPackageOverride,
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
  final SyncService? _syncService;
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
  final Future<LanTransferImportResult> Function({
    required LanTransferQrPayload payload,
    required String sourceMasterPassword,
  })?
  _receiveLanTransferOverride;
  final Future<void> Function(String email, String password)?
  _cloudRegisterOverride;
  final Future<void> Function(String email, String password)?
  _cloudLoginOverride;
  final Future<void> Function()? _cloudLogoutOverride;
  final Future<String?> Function()? _cloudAccountEmailOverride;
  final Future<CloudSyncResult> Function(String masterPassword)?
  _cloudSyncNowOverride;
  final Future<int> Function(String masterPassword)? _cloudDownloadOverride;
  final Future<List<SyncDevice>> Function()? _listCloudDevicesOverride;
  final Future<void> Function(String deviceId)? _revokeCloudDeviceOverride;
  final Future<SyncDevice> Function(String deviceId, String deviceName)?
  _renameCloudDeviceOverride;
  final Future<List<SyncConflictRecord>> Function()? _listSyncConflictsOverride;
  final Future<List<SyncBlobConflictRecord>> Function()?
  _listSyncBlobConflictsOverride;
  final Future<List<EmergencyContact>> Function()?
  _listEmergencyContactsOverride;
  final Future<EmergencyContact> Function({
    required EmergencyContactCreateRequest request,
  })?
  _createEmergencyContactOverride;
  final Future<EmergencyContact> Function(String contactId)?
  _revokeEmergencyContactOverride;
  final Future<List<EmergencyGrant>> Function()? _listEmergencyGrantsOverride;
  final Future<EmergencyGrant> Function({
    required EmergencyGrantCreateRequest request,
  })?
  _createEmergencyGrantOverride;
  final Future<EmergencyGrant> Function({
    required String grantId,
    required String recipientKeyFingerprint,
  })?
  _acceptEmergencyGrantOverride;
  final Future<EmergencyGrant> Function({
    required String grantId,
    String? requestMessageCiphertext,
    String? requestMessageAad,
  })?
  _requestEmergencyGrantAccessOverride;
  final Future<EmergencyGrant> Function(String grantId)?
  _cancelEmergencyGrantOverride;
  final Future<EmergencyGrant> Function(String grantId)?
  _revokeEmergencyGrantOverride;
  final Future<EmergencyAccessPackage> Function(String grantId)?
  _downloadEmergencyAccessPackageOverride;
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
    List<SyncDevice> cloudDevices = const <SyncDevice>[],
    String? cloudAccountEmail,
    Future<void> Function(String email, String password)? cloudRegisterOverride,
    Future<SyncDevice> Function(String deviceId, String deviceName)?
    renameCloudDeviceOverride,
    Future<LanTransferSession> Function({
      required List<String> itemIds,
      required bool includeBlobs,
      required bool includeHistory,
      required String senderName,
    })?
    createLanSendSessionOverride,
    Future<LanTransferImportResult> Function({
      required LanTransferQrPayload payload,
      required String sourceMasterPassword,
    })?
    receiveLanTransferOverride,
    List<SyncConflictRecord> syncConflicts = const <SyncConflictRecord>[],
    List<SyncBlobConflictRecord> syncBlobConflicts =
        const <SyncBlobConflictRecord>[],
    List<EmergencyContact> emergencyContacts = const <EmergencyContact>[],
    List<EmergencyGrant> emergencyGrants = const <EmergencyGrant>[],
    EmergencyAccessPackage? emergencyAccessPackage,
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
    var fakeCloudAccountEmail = cloudAccountEmail;
    final fakeCloudDevices = <String, SyncDevice>{
      for (final device in cloudDevices) device.id: device,
    };
    final fakeEmergencyContacts = {
      for (final contact in emergencyContacts) contact.id: contact,
    };
    final fakeEmergencyGrants = {
      for (final grant in emergencyGrants) grant.id: grant,
    };
    var fakeEmergencyContactCounter = emergencyContacts.length;
    var fakeEmergencyGrantCounter = emergencyGrants.length;

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
      receiveLanTransferOverride: receiveLanTransferOverride,
      cloudRegisterOverride: (email, password) async {
        final override = cloudRegisterOverride;
        if (override != null) {
          await override(email, password);
        }
        fakeCloudAccountEmail = email;
      },
      cloudLoginOverride: (email, password) async {
        fakeCloudAccountEmail = email;
      },
      cloudLogoutOverride: () async {
        fakeCloudAccountEmail = null;
      },
      cloudAccountEmailOverride: () async => fakeCloudAccountEmail,
      cloudSyncNowOverride: (masterPassword) async =>
          const CloudSyncResult(importedCount: 0),
      listCloudDevicesOverride: () async =>
          List.unmodifiable(fakeCloudDevices.values),
      renameCloudDeviceOverride:
          renameCloudDeviceOverride ??
          (deviceId, deviceName) async {
            final existing = fakeCloudDevices[deviceId];
            if (existing == null) {
              throw StateError('Cloud device not found: $deviceId');
            }
            final renamed = SyncDevice(
              id: existing.id,
              deviceName: deviceName,
              deviceType: existing.deviceType,
              trusted: existing.trusted,
              platform: existing.platform,
              clientVersion: existing.clientVersion,
              lastSyncAt: existing.lastSyncAt,
              lastIpAddress: existing.lastIpAddress,
              lastUserAgent: existing.lastUserAgent,
              createdAt: existing.createdAt,
              revokedAt: existing.revokedAt,
            );
            fakeCloudDevices[deviceId] = renamed;
            return renamed;
          },
      listSyncConflictsOverride: () async => List.unmodifiable(syncConflicts),
      listSyncBlobConflictsOverride: () async =>
          List.unmodifiable(syncBlobConflicts),
      listEmergencyContactsOverride: () async {
        return List.unmodifiable(fakeEmergencyContacts.values);
      },
      createEmergencyContactOverride: ({required request}) async {
        fakeEmergencyContactCounter += 1;
        final contact = EmergencyContact(
          id: 'contact-$fakeEmergencyContactCounter',
          ownerUserId: 'fake-owner',
          recipientUserId: 'fake-recipient-$fakeEmergencyContactCounter',
          recipientEmail: request.recipientEmail,
          recipientPublicKey: request.recipientPublicKey,
          recipientKeyFingerprint: request.recipientKeyFingerprint,
          recipientLabel: request.recipientLabel,
          status: 'active',
          createdAt: _fakeIsoTimestamp(fakeTimestamp += 1),
          updatedAt: _fakeIsoTimestamp(fakeTimestamp),
        );
        fakeEmergencyContacts[contact.id] = contact;
        return contact;
      },
      revokeEmergencyContactOverride: (contactId) async {
        final existing = fakeEmergencyContacts[contactId];
        if (existing == null) {
          throw StateError('Emergency contact not found: $contactId');
        }
        final revoked = _copyEmergencyContact(
          existing,
          status: 'revoked',
          revokedAt: _fakeIsoTimestamp(fakeTimestamp += 1),
          updatedAt: _fakeIsoTimestamp(fakeTimestamp),
        );
        fakeEmergencyContacts[contactId] = revoked;
        return revoked;
      },
      listEmergencyGrantsOverride: () async {
        return List.unmodifiable(fakeEmergencyGrants.values);
      },
      createEmergencyGrantOverride: ({required request}) async {
        fakeEmergencyGrantCounter += 1;
        final grant = EmergencyGrant(
          id: 'grant-$fakeEmergencyGrantCounter',
          ownerUserId: 'fake-owner',
          recipientUserId: 'fake-recipient',
          contactId: request.contactId,
          vaultId: 'fake-vault',
          status: 'pending_acceptance',
          waitingPeriodHours: request.waitingPeriodHours,
          packageAad: request.packageAad,
          packageFingerprint: request.packageFingerprint,
          recipientKeyFingerprint: null,
          createdAt: _fakeIsoTimestamp(fakeTimestamp += 1),
          updatedAt: _fakeIsoTimestamp(fakeTimestamp),
        );
        fakeEmergencyGrants[grant.id] = grant;
        return grant;
      },
      acceptEmergencyGrantOverride:
          ({required grantId, required recipientKeyFingerprint}) async {
            final accepted = _updateFakeEmergencyGrant(
              fakeEmergencyGrants,
              grantId,
              status: 'active',
              recipientKeyFingerprint: recipientKeyFingerprint,
              updatedAt: _fakeIsoTimestamp(fakeTimestamp += 1),
            );
            return accepted;
          },
      requestEmergencyGrantAccessOverride:
          ({
            required grantId,
            requestMessageCiphertext,
            requestMessageAad,
          }) async {
            final requested = _updateFakeEmergencyGrant(
              fakeEmergencyGrants,
              grantId,
              status: 'access_requested',
              requestedAt: _fakeIsoTimestamp(fakeTimestamp += 1),
              updatedAt: _fakeIsoTimestamp(fakeTimestamp),
            );
            return requested;
          },
      cancelEmergencyGrantOverride: (grantId) async {
        final cancelled = _updateFakeEmergencyGrant(
          fakeEmergencyGrants,
          grantId,
          status: 'cancelled',
          cancelledAt: _fakeIsoTimestamp(fakeTimestamp += 1),
          updatedAt: _fakeIsoTimestamp(fakeTimestamp),
        );
        return cancelled;
      },
      revokeEmergencyGrantOverride: (grantId) async {
        final revoked = _updateFakeEmergencyGrant(
          fakeEmergencyGrants,
          grantId,
          status: 'revoked',
          revokedAt: _fakeIsoTimestamp(fakeTimestamp += 1),
          updatedAt: _fakeIsoTimestamp(fakeTimestamp),
        );
        return revoked;
      },
      downloadEmergencyAccessPackageOverride: (grantId) async {
        final package = emergencyAccessPackage;
        final grant = fakeEmergencyGrants[grantId];
        if (package == null || grant == null) {
          throw StateError('Emergency access package not found: $grantId');
        }
        if (package.grantId == grantId) {
          return package;
        }
        return EmergencyAccessPackage(
          grantId: grantId,
          ownerUserId: grant.ownerUserId,
          recipientUserId: grant.recipientUserId,
          contactId: grant.contactId,
          status: package.status,
          encryptedRecoveryPackage: package.encryptedRecoveryPackage,
          packageAad: grant.packageAad,
          packageFingerprint: grant.packageFingerprint,
          recipientKeyFingerprint: grant.recipientKeyFingerprint,
          downloadedAt: package.downloadedAt,
        );
      },
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
    return lanTransferService.cancelSendSession();
  }

  Future<void> loginCloudSync({
    required String email,
    required String password,
  }) async {
    final override = _cloudLoginOverride;
    if (override != null) {
      return override(email, password);
    }
    await syncService.login(email: email, password: password);
  }

  Future<void> registerCloudSync({
    required String email,
    required String password,
  }) async {
    final override = _cloudRegisterOverride;
    if (override != null) {
      return override(email, password);
    }
    await syncService.register(email: email, password: password);
  }

  Future<void> logoutCloudSync() async {
    final override = _cloudLogoutOverride;
    if (override != null) {
      return override();
    }
    return syncService.logout();
  }

  Future<String?> cloudSyncAccountEmail() async {
    final override = _cloudAccountEmailOverride;
    if (override != null) {
      return override();
    }
    final service = _syncService;
    if (service == null) {
      return null;
    }
    return service.currentAccountEmail();
  }

  Future<bool> isCloudSyncSignedIn() async {
    return (await cloudSyncAccountEmail()) != null;
  }

  Future<List<SyncDevice>> listCloudSyncDevices() async {
    final override = _listCloudDevicesOverride;
    if (override != null) {
      return override();
    }
    return syncService.listDevices();
  }

  Future<void> revokeCloudSyncDevice(String deviceId) async {
    final override = _revokeCloudDeviceOverride;
    if (override != null) {
      return override(deviceId);
    }
    return syncService.revokeDevice(deviceId);
  }

  Future<SyncDevice> renameCloudSyncDevice({
    required String deviceId,
    required String deviceName,
  }) async {
    final override = _renameCloudDeviceOverride;
    if (override != null) {
      return override(deviceId, deviceName);
    }
    return syncService.renameDevice(deviceId, deviceName);
  }

  Future<List<SyncConflictRecord>> listSyncConflicts() async {
    final override = _listSyncConflictsOverride;
    if (override != null) {
      return override();
    }
    return syncService.conflicts();
  }

  Future<List<SyncBlobConflictRecord>> listSyncBlobConflicts() async {
    final override = _listSyncBlobConflictsOverride;
    if (override != null) {
      return override();
    }
    return syncService.blobConflicts();
  }

  Future<void> clearSyncConflict(String itemId) {
    return syncService.clearConflict(itemId);
  }

  Future<void> clearSyncBlobConflict(String blobId) {
    return syncService.clearBlobConflict(blobId);
  }

  Future<List<EmergencyContact>> listEmergencyContacts() async {
    final override = _listEmergencyContactsOverride;
    if (override != null) {
      return override();
    }
    return syncService.listEmergencyContacts();
  }

  Future<EmergencyContact> createEmergencyContact({
    required EmergencyContactCreateRequest request,
  }) async {
    final override = _createEmergencyContactOverride;
    if (override != null) {
      return override(request: request);
    }
    return syncService.createEmergencyContact(request: request);
  }

  Future<EmergencyContact> revokeEmergencyContact(String contactId) async {
    final override = _revokeEmergencyContactOverride;
    if (override != null) {
      return override(contactId);
    }
    return syncService.revokeEmergencyContact(contactId);
  }

  Future<List<EmergencyGrant>> listEmergencyGrants() async {
    final override = _listEmergencyGrantsOverride;
    if (override != null) {
      return override();
    }
    return syncService.listEmergencyGrants();
  }

  Future<EmergencyGrant> createEmergencyGrant({
    required EmergencyGrantCreateRequest request,
  }) async {
    final override = _createEmergencyGrantOverride;
    if (override != null) {
      return override(request: request);
    }
    return syncService.createEmergencyGrant(request: request);
  }

  Future<EmergencyGrant> acceptEmergencyGrant({
    required String grantId,
    required String recipientKeyFingerprint,
  }) async {
    final override = _acceptEmergencyGrantOverride;
    if (override != null) {
      return override(
        grantId: grantId,
        recipientKeyFingerprint: recipientKeyFingerprint,
      );
    }
    return syncService.acceptEmergencyGrant(
      grantId: grantId,
      recipientKeyFingerprint: recipientKeyFingerprint,
    );
  }

  Future<EmergencyGrant> requestEmergencyGrantAccess({
    required String grantId,
    String? requestMessageCiphertext,
    String? requestMessageAad,
  }) async {
    final override = _requestEmergencyGrantAccessOverride;
    if (override != null) {
      return override(
        grantId: grantId,
        requestMessageCiphertext: requestMessageCiphertext,
        requestMessageAad: requestMessageAad,
      );
    }
    return syncService.requestEmergencyGrantAccess(
      grantId: grantId,
      requestMessageCiphertext: requestMessageCiphertext,
      requestMessageAad: requestMessageAad,
    );
  }

  Future<EmergencyGrant> cancelEmergencyGrant(String grantId) async {
    final override = _cancelEmergencyGrantOverride;
    if (override != null) {
      return override(grantId);
    }
    return syncService.cancelEmergencyGrant(grantId);
  }

  Future<EmergencyGrant> revokeEmergencyGrant(String grantId) async {
    final override = _revokeEmergencyGrantOverride;
    if (override != null) {
      return override(grantId);
    }
    return syncService.revokeEmergencyGrant(grantId);
  }

  Future<EmergencyAccessPackage> downloadEmergencyAccessPackage(
    String grantId,
  ) async {
    final override = _downloadEmergencyAccessPackageOverride;
    if (override != null) {
      return override(grantId);
    }
    return syncService.downloadEmergencyAccessPackage(grantId);
  }

  Future<CloudSyncResult> syncEncryptedVaultNow({
    required String masterPassword,
  }) async {
    final override = _cloudSyncNowOverride;
    if (override != null) {
      return override(masterPassword);
    }
    var snapshot = await _lockShellOnIntegrity(
      vaultService.createVerifiedEncryptedSyncSnapshot,
    );
    var importedCount = 0;

    if (snapshot.items.isEmpty && snapshot.blobs.isEmpty) {
      try {
        importedCount = await downloadCloudEncryptedVault(
          masterPassword: masterPassword,
          mode: BackupImportMode.merge,
        );
      } on SyncApiException catch (error) {
        if (error.statusCode != 404 || error.code != 'VAULT_NOT_INITIALIZED') {
          rethrow;
        }
      }
      snapshot = await _lockShellOnIntegrity(
        vaultService.createVerifiedEncryptedSyncSnapshot,
      );
    } else {
      try {
        importedCount += await _downloadCloudAdditionsBeforePush(
          masterPassword: masterPassword,
          beforeSnapshot: snapshot,
        );
      } on SyncApiException catch (error) {
        if (error.statusCode != 404 || error.code != 'VAULT_NOT_INITIALIZED') {
          rethrow;
        }
      }
      snapshot = await _lockShellOnIntegrity(
        vaultService.createVerifiedEncryptedSyncSnapshot,
      );
    }

    final metaPayload = SyncVaultMetaPayload.fromLocal(
      snapshot.meta,
      manifest: snapshot.manifest,
      revision: snapshot.manifest.counter,
    );
    await syncService.ensureVaultMetaInitialized(metaPayload);
    SyncPushResponse itemPush;
    SyncBlobPushResponse? blobPush;
    if (snapshot.items.isNotEmpty && snapshot.blobs.isNotEmpty) {
      final vaultPush = await syncService.pushEncryptedVault(
        items: snapshot.items,
        blobs: snapshot.blobs,
      );
      itemPush = vaultPush.items;
      blobPush = vaultPush.blobs;
    } else {
      itemPush = snapshot.items.isEmpty
          ? const SyncPushResponse(applied: [], conflicts: [])
          : await syncService.pushEncryptedItems(items: snapshot.items);
    }
    if (snapshot.items.isEmpty && snapshot.blobs.isNotEmpty) {
      blobPush = await syncService.pushEncryptedBlobs(blobs: snapshot.blobs);
    }
    if (itemPush.conflicts.isNotEmpty ||
        (blobPush?.conflicts.isNotEmpty ?? false)) {
      return CloudSyncResult(
        importedCount: importedCount,
        itemConflictCount: itemPush.conflicts.length,
        blobConflictCount: blobPush?.conflicts.length ?? 0,
      );
    }
    await syncService.uploadVaultMeta(metaPayload);
    importedCount += await downloadCloudEncryptedVault(
      masterPassword: masterPassword,
      mode: BackupImportMode.merge,
    );
    return CloudSyncResult(importedCount: importedCount);
  }

  Future<int> _downloadCloudAdditionsBeforePush({
    required String masterPassword,
    required VerifiedEncryptedVaultSyncSnapshot beforeSnapshot,
  }) async {
    final beforeItemIds = beforeSnapshot.items.map((item) => item.id).toSet();
    final beforeBlobIds = beforeSnapshot.blobs
        .map((blob) => blob.blobId)
        .toSet();
    final download = await syncService.prepareEncryptedVaultDownload();
    final importedCount = await importEncryptedBackupJson(
      backupJson: download.backupJson,
      masterPassword: masterPassword,
      mode: BackupImportMode.skip,
    );
    final afterSnapshot = await _lockShellOnIntegrity(
      vaultService.createVerifiedEncryptedSyncSnapshot,
    );
    final remoteItemIds = download.items.map((item) => item.id).toSet();
    final remoteBlobIds = download.blobs.map((blob) => blob.id).toSet();
    final importedItemIds = afterSnapshot.items
        .map((item) => item.id)
        .where(
          (id) => !beforeItemIds.contains(id) && remoteItemIds.contains(id),
        )
        .toSet();
    final importedBlobIds = afterSnapshot.blobs
        .map((blob) => blob.blobId)
        .where(
          (id) => !beforeBlobIds.contains(id) && remoteBlobIds.contains(id),
        )
        .toSet();
    await syncService.recordImportedEncryptedRows(
      download: download,
      itemIds: importedItemIds,
      blobIds: importedBlobIds,
    );
    return importedCount;
  }

  Future<int> downloadCloudEncryptedVault({
    required String masterPassword,
    BackupImportMode mode = BackupImportMode.skip,
  }) async {
    final override = _cloudDownloadOverride;
    if (override != null) {
      return override(masterPassword);
    }
    final download = await syncService.prepareEncryptedVaultDownload();
    final importedCount = await importEncryptedBackupJson(
      backupJson: download.backupJson,
      masterPassword: masterPassword,
      mode: mode,
    );
    await _applyRemoteDeletedSyncItems(download.items);
    await _applyRemoteDeletedSyncBlobs(download.blobs);
    await syncService.commitEncryptedVaultDownload(download);
    for (final item in download.items) {
      await clearSyncConflict(item.id);
    }
    for (final blob in download.blobs) {
      await syncService.clearBlobConflict(blob.id);
    }
    return importedCount;
  }

  Future<void> _applyRemoteDeletedSyncItems(List<SyncItem> items) async {
    final deletedIds = {
      for (final item in items)
        if (item.payload.deleted) item.id,
    };
    if (deletedIds.isEmpty) {
      return;
    }
    if (!vaultService.isUnlocked) {
      throw StateError('Remote deleted sync items require an unlocked vault');
    }
    await _lockShellOnIntegrity(() async {
      for (final id in deletedIds) {
        try {
          await vaultService.deleteItem(id);
        } on VaultItemNotFoundException {
          // Missing or already-deleted local rows already satisfy the tombstone.
        }
      }
    });
  }

  Future<void> _applyRemoteDeletedSyncBlobs(List<SyncBlob> blobs) async {
    final deletedIds = {
      for (final blob in blobs)
        if (blob.payload.deleted) blob.id,
    };
    if (deletedIds.isEmpty) {
      return;
    }
    if (!vaultService.isUnlocked) {
      throw StateError('Remote deleted sync blobs require an unlocked vault');
    }
    await _lockShellOnIntegrity(() async {
      for (final id in deletedIds) {
        try {
          await vaultService.deleteBlob(id);
        } on VaultItemNotFoundException {
          // Missing or already-deleted local rows already satisfy the tombstone.
        }
      }
    });
  }

  Future<void> clearLocalVault() async {
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

  SyncService get syncService {
    final service = _syncService;
    if (service == null) {
      throw StateError('SyncService is unavailable in this app context.');
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

String _fakeIsoTimestamp(int millisecondsSinceEpoch) {
  return DateTime.fromMillisecondsSinceEpoch(
    millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

EmergencyContact _copyEmergencyContact(
  EmergencyContact contact, {
  String? status,
  String? updatedAt,
  String? revokedAt,
}) {
  return EmergencyContact(
    id: contact.id,
    ownerUserId: contact.ownerUserId,
    recipientUserId: contact.recipientUserId,
    recipientEmail: contact.recipientEmail,
    recipientPublicKey: contact.recipientPublicKey,
    recipientKeyFingerprint: contact.recipientKeyFingerprint,
    recipientLabel: contact.recipientLabel,
    status: status ?? contact.status,
    createdAt: contact.createdAt,
    updatedAt: updatedAt ?? contact.updatedAt,
    revokedAt: revokedAt ?? contact.revokedAt,
  );
}

EmergencyGrant _updateFakeEmergencyGrant(
  Map<String, EmergencyGrant> grants,
  String grantId, {
  required String status,
  String? recipientKeyFingerprint,
  String? requestedAt,
  String? cancelledAt,
  String? revokedAt,
  String? updatedAt,
}) {
  final existing = grants[grantId];
  if (existing == null) {
    throw StateError('Emergency grant not found: $grantId');
  }
  final updated = EmergencyGrant(
    id: existing.id,
    ownerUserId: existing.ownerUserId,
    recipientUserId: existing.recipientUserId,
    contactId: existing.contactId,
    vaultId: existing.vaultId,
    status: status,
    waitingPeriodHours: existing.waitingPeriodHours,
    packageAad: existing.packageAad,
    packageFingerprint: existing.packageFingerprint,
    recipientKeyFingerprint:
        recipientKeyFingerprint ?? existing.recipientKeyFingerprint,
    requestedAt: requestedAt ?? existing.requestedAt,
    readyAt: existing.readyAt,
    downloadedAt: existing.downloadedAt,
    cancelledAt: cancelledAt ?? existing.cancelledAt,
    revokedAt: revokedAt ?? existing.revokedAt,
    expiresAt: existing.expiresAt,
    createdAt: existing.createdAt,
    updatedAt: updatedAt ?? existing.updatedAt,
  );
  grants[grantId] = updated;
  return updated;
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
