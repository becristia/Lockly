import 'dart:convert';

import 'package:secure_box/core/sync/sync_backup_adapter.dart';
import 'package:secure_box/core/sync/sync_api_client.dart';
import 'package:secure_box/core/sync/sync_credential_store.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/core/sync/sync_payload_guard.dart';
import 'package:secure_box/data/db/sync_state_dao.dart';
import 'package:secure_box/data/models/encrypted_vault_blob.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';

typedef SyncDeviceNameProvider = String Function();

class PreparedSyncVaultDownload {
  const PreparedSyncVaultDownload({
    required this.backupJson,
    required this.items,
    required this.serverTime,
    required this.blobs,
    required this.blobServerTime,
  });

  final String backupJson;
  final List<SyncItem> items;
  final String serverTime;
  final List<SyncBlob> blobs;
  final String blobServerTime;
}

class SyncService {
  static const initialPullCursor = '1970-01-01T00:00:00.000Z';

  SyncService({
    required SyncApiClient api,
    required SyncCredentialStore credentials,
    SyncStateDao? syncState,
    SyncDeviceNameProvider? deviceName,
    String? deviceType,
    String? platform,
    String? clientVersion,
  }) : _api = api,
       _credentials = credentials,
       _syncState = syncState,
       _deviceName = deviceName ?? _defaultDeviceName,
       _deviceType = deviceType,
       _platform = platform,
       _clientVersion = clientVersion;

  final SyncApiClient _api;
  final SyncCredentialStore _credentials;
  final SyncStateDao? _syncState;
  final SyncDeviceNameProvider _deviceName;
  final String? _deviceType;
  final String? _platform;
  final String? _clientVersion;

  Future<SyncAuthTokens> login({
    required String email,
    required String password,
  }) async {
    final tokens = await _api.login(email: email, password: password);
    await _credentials.saveTokens(tokens);
    await _ensureDeviceRegistered(tokens.accessToken, accountEmail: email);
    return tokens;
  }

  Future<SyncAccount> register({
    required String email,
    required String password,
  }) async {
    final account = await _api.register(email: email, password: password);
    await login(email: email, password: password);
    return account;
  }

  Future<T> refreshIfNeeded<T>(
    Future<T> Function(String accessToken) operation,
  ) async {
    final tokens = await _requireTokens();
    try {
      return await operation(tokens.accessToken);
    } on SyncApiException catch (error) {
      if (!_shouldRefresh(error)) {
        rethrow;
      }
      final refreshed = await _api.refresh(refreshToken: tokens.refreshToken);
      await _credentials.saveTokens(refreshed);
      return operation(refreshed.accessToken);
    }
  }

  Future<List<SyncDevice>> listDevices() {
    return refreshIfNeeded((accessToken) {
      return _api.listDevices(accessToken: accessToken);
    });
  }

  Future<EmergencyContact> createEmergencyContact({
    required EmergencyContactCreateRequest request,
  }) {
    return refreshIfNeeded((accessToken) {
      return _api.createEmergencyContact(
        accessToken: accessToken,
        request: request,
      );
    });
  }

  Future<List<EmergencyContact>> listEmergencyContacts() {
    return refreshIfNeeded((accessToken) {
      return _api.listEmergencyContacts(accessToken: accessToken);
    });
  }

  Future<EmergencyContact> revokeEmergencyContact(String contactId) {
    return refreshIfNeeded((accessToken) {
      return _api.revokeEmergencyContact(
        accessToken: accessToken,
        contactId: contactId,
      );
    });
  }

  Future<EmergencyGrant> createEmergencyGrant({
    required EmergencyGrantCreateRequest request,
  }) {
    return refreshIfNeeded((accessToken) {
      return _api.createEmergencyGrant(
        accessToken: accessToken,
        request: request,
      );
    });
  }

  Future<List<EmergencyGrant>> listEmergencyGrants() {
    return refreshIfNeeded((accessToken) {
      return _api.listEmergencyGrants(accessToken: accessToken);
    });
  }

  Future<EmergencyGrant> acceptEmergencyGrant({
    required String grantId,
    required String recipientKeyFingerprint,
  }) {
    return refreshIfNeeded((accessToken) {
      return _api.acceptEmergencyGrant(
        accessToken: accessToken,
        grantId: grantId,
        recipientKeyFingerprint: recipientKeyFingerprint,
      );
    });
  }

  Future<EmergencyGrant> requestEmergencyGrantAccess({
    required String grantId,
    String? requestMessageCiphertext,
    String? requestMessageAad,
  }) {
    return refreshIfNeeded((accessToken) {
      return _api.requestEmergencyGrantAccess(
        accessToken: accessToken,
        grantId: grantId,
        requestMessageCiphertext: requestMessageCiphertext,
        requestMessageAad: requestMessageAad,
      );
    });
  }

  Future<EmergencyGrant> cancelEmergencyGrant(String grantId) {
    return refreshIfNeeded((accessToken) {
      return _api.cancelEmergencyGrant(
        accessToken: accessToken,
        grantId: grantId,
      );
    });
  }

  Future<EmergencyGrant> revokeEmergencyGrant(String grantId) {
    return refreshIfNeeded((accessToken) {
      return _api.revokeEmergencyGrant(
        accessToken: accessToken,
        grantId: grantId,
      );
    });
  }

  Future<EmergencyAccessPackage> downloadEmergencyAccessPackage(
    String grantId,
  ) {
    return refreshIfNeeded((accessToken) {
      return _api.downloadEmergencyAccessPackage(
        accessToken: accessToken,
        grantId: grantId,
      );
    });
  }

  Future<SyncDevice> renameDevice(String deviceId, String deviceName) {
    return refreshIfNeeded((accessToken) {
      return _api.renameDevice(
        accessToken: accessToken,
        deviceId: deviceId,
        deviceName: deviceName,
      );
    });
  }

  Future<List<SyncConflictRecord>> conflicts() {
    return _requireSyncState().conflicts();
  }

  Future<List<SyncBlobConflictRecord>> blobConflicts() {
    return _requireSyncState().blobConflicts();
  }

  Future<void> clearConflict(String itemId) {
    return _requireSyncState().clearConflict(itemId);
  }

  Future<void> clearBlobConflict(String blobId) {
    return _requireSyncState().clearBlobConflict(blobId);
  }

  Future<void> revokeDevice(String deviceId) async {
    final currentDeviceId = await _credentials.readDeviceId();
    await refreshIfNeeded((accessToken) {
      return _api.revokeDevice(accessToken: accessToken, deviceId: deviceId);
    });
    if (deviceId == currentDeviceId) {
      await _credentials.clear();
      await _syncState?.clearAll();
    }
  }

  Future<SyncPushResponse> pushEncryptedItems({
    required List<EncryptedVaultItem> items,
  }) async {
    final syncState = _requireSyncState();
    final deviceId = await _requireSyncDeviceId(syncState);
    final syncItems = <SyncItem>[];
    for (final item in items) {
      final state = await syncState.itemState(item.id);
      syncItems.add(
        SyncItem(
          id: item.id,
          payload: SyncItemPayload.fromLocal(
            item,
            revision: state?.serverRevision ?? 0,
          ),
        ),
      );
    }

    final response = await refreshIfNeeded((accessToken) {
      return _api.push(
        accessToken: accessToken,
        deviceId: deviceId,
        items: syncItems,
      );
    });
    _assertNoMixedItemPushResponse(response);

    for (final item in response.applied) {
      await syncState.saveItemState(
        SyncItemState(
          itemId: item.id,
          serverRevision: item.payload.revision,
          serverUpdatedAt: item.payload.serverUpdatedAt,
        ),
      );
      await syncState.clearConflict(item.id);
    }

    for (final conflict in response.conflicts) {
      final remotePayload = conflict.toJson();
      assertNoForbiddenSyncFields(remotePayload);
      await syncState.saveConflict(
        SyncConflictRecord(
          itemId: conflict.itemId,
          clientRevision: conflict.localRevision,
          serverRevision: conflict.remoteRevision,
          remotePayload: jsonEncode(remotePayload),
          createdAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      );
    }

    return response;
  }

  Future<SyncBlobPushResponse> pushEncryptedBlobs({
    required List<EncryptedVaultBlob> blobs,
  }) async {
    final syncState = _requireSyncState();
    final deviceId = await _requireSyncDeviceId(syncState);
    final syncBlobs = <SyncBlob>[];
    for (final blob in blobs) {
      final state = await syncState.blobState(blob.blobId);
      syncBlobs.add(
        SyncBlob(
          id: blob.blobId,
          itemId: blob.itemId,
          payload: SyncBlobPayload.fromLocal(
            blob,
            revision: state?.serverRevision ?? 0,
          ),
        ),
      );
    }

    final response = await refreshIfNeeded((accessToken) {
      return _api.pushBlobs(
        accessToken: accessToken,
        deviceId: deviceId,
        blobs: syncBlobs,
      );
    });
    _assertNoMixedBlobPushResponse(response);

    for (final blob in response.applied) {
      await syncState.saveBlobState(
        SyncBlobState(
          blobId: blob.id,
          serverRevision: blob.payload.revision,
          serverUpdatedAt: blob.payload.serverUpdatedAt,
        ),
      );
      await syncState.clearBlobConflict(blob.id);
    }

    for (final conflict in response.conflicts) {
      final remotePayload = conflict.toJson();
      assertNoForbiddenSyncFields(remotePayload);
      await syncState.saveBlobConflict(
        SyncBlobConflictRecord(
          blobId: conflict.blobId,
          clientRevision: conflict.localRevision,
          serverRevision: conflict.remoteRevision,
          remotePayload: jsonEncode(remotePayload),
          createdAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      );
    }

    return response;
  }

  Future<SyncVaultPushResponse> pushEncryptedVault({
    required List<EncryptedVaultItem> items,
    required List<EncryptedVaultBlob> blobs,
  }) async {
    final syncState = _requireSyncState();
    final deviceId = await _requireSyncDeviceId(syncState);
    final syncItems = <SyncItem>[];
    for (final item in items) {
      final state = await syncState.itemState(item.id);
      syncItems.add(
        SyncItem(
          id: item.id,
          payload: SyncItemPayload.fromLocal(
            item,
            revision: state?.serverRevision ?? 0,
          ),
        ),
      );
    }
    final syncBlobs = <SyncBlob>[];
    for (final blob in blobs) {
      final state = await syncState.blobState(blob.blobId);
      syncBlobs.add(
        SyncBlob(
          id: blob.blobId,
          itemId: blob.itemId,
          payload: SyncBlobPayload.fromLocal(
            blob,
            revision: state?.serverRevision ?? 0,
          ),
        ),
      );
    }

    final response = await refreshIfNeeded((accessToken) {
      return _api.pushVault(
        accessToken: accessToken,
        deviceId: deviceId,
        items: syncItems,
        blobs: syncBlobs,
      );
    });
    _assertNoMixedVaultPushResponse(response);

    for (final item in response.items.applied) {
      await syncState.saveItemState(
        SyncItemState(
          itemId: item.id,
          serverRevision: item.payload.revision,
          serverUpdatedAt: item.payload.serverUpdatedAt,
        ),
      );
      await syncState.clearConflict(item.id);
    }
    for (final conflict in response.items.conflicts) {
      final remotePayload = conflict.toJson();
      assertNoForbiddenSyncFields(remotePayload);
      await syncState.saveConflict(
        SyncConflictRecord(
          itemId: conflict.itemId,
          clientRevision: conflict.localRevision,
          serverRevision: conflict.remoteRevision,
          remotePayload: jsonEncode(remotePayload),
          createdAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      );
    }
    for (final blob in response.blobs.applied) {
      await syncState.saveBlobState(
        SyncBlobState(
          blobId: blob.id,
          serverRevision: blob.payload.revision,
          serverUpdatedAt: blob.payload.serverUpdatedAt,
        ),
      );
      await syncState.clearBlobConflict(blob.id);
    }
    for (final conflict in response.blobs.conflicts) {
      final remotePayload = conflict.toJson();
      assertNoForbiddenSyncFields(remotePayload);
      await syncState.saveBlobConflict(
        SyncBlobConflictRecord(
          blobId: conflict.blobId,
          clientRevision: conflict.localRevision,
          serverRevision: conflict.remoteRevision,
          remotePayload: jsonEncode(remotePayload),
          createdAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      );
    }
    return response;
  }

  Future<List<SyncItem>> pullEncryptedItems() async {
    return _pullEncryptedItemsSince(await _currentPullCursor());
  }

  Future<List<SyncBlob>> pullEncryptedBlobs() async {
    return _pullEncryptedBlobsSince(await _currentBlobPullCursor());
  }

  Future<void> uploadVaultMeta(SyncVaultMetaPayload meta) async {
    final deviceId = await _requireDeviceId();
    await refreshIfNeeded((accessToken) async {
      SyncVaultMetaPayload current;
      try {
        current = await _api.getVaultMeta(
          accessToken: accessToken,
          deviceId: deviceId,
        );
      } on SyncApiException catch (error) {
        if (error.statusCode == 404 && error.code == 'VAULT_NOT_INITIALIZED') {
          await _api.initVault(accessToken: accessToken, meta: meta);
          return;
        }
        rethrow;
      }
      await _api.updateVaultMeta(
        accessToken: accessToken,
        deviceId: deviceId,
        meta: meta.withRevision(current.revision),
      );
    });
  }

  Future<void> ensureVaultMetaInitialized(SyncVaultMetaPayload meta) async {
    final deviceId = await _requireDeviceId();
    await refreshIfNeeded((accessToken) async {
      try {
        await _api.getVaultMeta(accessToken: accessToken, deviceId: deviceId);
      } on SyncApiException catch (error) {
        if (error.statusCode == 404 && error.code == 'VAULT_NOT_INITIALIZED') {
          await _api.initVault(accessToken: accessToken, meta: meta);
          return;
        }
        rethrow;
      }
    });
  }

  Future<String> downloadEncryptedVaultBackupJson() async {
    return (await prepareEncryptedVaultDownload()).backupJson;
  }

  Future<PreparedSyncVaultDownload> prepareEncryptedVaultDownload() async {
    final deviceId = await _requireDeviceId();
    final meta = await refreshIfNeeded((accessToken) {
      return _api.getVaultMeta(accessToken: accessToken, deviceId: deviceId);
    });
    final response = await _pullEncryptedItemsResponseSince(initialPullCursor);
    final blobResponse = await _pullEncryptedBlobsResponseSince(
      initialPullCursor,
    );
    final items = response.items;
    final blobs = blobResponse.blobs;
    final backup = cloudVaultBackupFromSync(
      meta: meta,
      items: items,
      blobs: blobs,
    );
    return PreparedSyncVaultDownload(
      backupJson: const JsonEncoder.withIndent('  ').convert(backup.toJson()),
      items: items,
      serverTime: response.serverTime,
      blobs: blobs,
      blobServerTime: blobResponse.serverTime,
    );
  }

  Future<void> commitEncryptedVaultDownload(
    PreparedSyncVaultDownload download,
  ) {
    return _recordPreparedDownload(download);
  }

  Future<void> recordImportedEncryptedRows({
    required PreparedSyncVaultDownload download,
    required Set<String> itemIds,
    required Set<String> blobIds,
  }) async {
    for (final item in download.items) {
      if (!itemIds.contains(item.id)) {
        continue;
      }
      await _requireSyncState().saveItemState(
        SyncItemState(
          itemId: item.id,
          serverRevision: item.payload.revision,
          serverUpdatedAt: item.payload.serverUpdatedAt,
        ),
      );
      await _requireSyncState().clearConflict(item.id);
    }
    for (final blob in download.blobs) {
      if (!blobIds.contains(blob.id)) {
        continue;
      }
      await _requireSyncState().saveBlobState(
        SyncBlobState(
          blobId: blob.id,
          serverRevision: blob.payload.revision,
          serverUpdatedAt: blob.payload.serverUpdatedAt,
        ),
      );
      await _requireSyncState().clearBlobConflict(blob.id);
    }
  }

  Future<String> _currentPullCursor() async {
    final syncState = _requireSyncState();
    return await syncState.lastPullCursor() ?? initialPullCursor;
  }

  Future<String> _currentBlobPullCursor() async {
    final syncState = _requireSyncState();
    return await syncState.lastBlobPullCursor() ?? initialPullCursor;
  }

  Future<List<SyncItem>> _pullEncryptedItemsSince(String since) async {
    final response = await _pullEncryptedItemsResponseSince(since);
    await _recordPulledItems(response.items, response.serverTime);
    return response.items;
  }

  Future<List<SyncBlob>> _pullEncryptedBlobsSince(String since) async {
    final response = await _pullEncryptedBlobsResponseSince(since);
    await _recordPulledBlobs(response.blobs, response.serverTime);
    return response.blobs;
  }

  Future<SyncPullResponse> _pullEncryptedItemsResponseSince(
    String since,
  ) async {
    final syncState = _requireSyncState();
    final deviceId = await _requireSyncDeviceId(syncState);
    return refreshIfNeeded((accessToken) {
      return _api.pull(
        accessToken: accessToken,
        since: since,
        deviceId: deviceId,
      );
    });
  }

  Future<SyncBlobPullResponse> _pullEncryptedBlobsResponseSince(
    String since,
  ) async {
    final syncState = _requireSyncState();
    final deviceId = await _requireSyncDeviceId(syncState);
    return refreshIfNeeded((accessToken) {
      return _api.pullBlobs(
        accessToken: accessToken,
        since: since,
        deviceId: deviceId,
      );
    });
  }

  Future<void> _recordPulledItems(
    List<SyncItem> items,
    String serverTime,
  ) async {
    final syncState = _requireSyncState();
    for (final item in items) {
      await syncState.saveItemState(
        SyncItemState(
          itemId: item.id,
          serverRevision: item.payload.revision,
          serverUpdatedAt: item.payload.serverUpdatedAt,
        ),
      );
    }
    await syncState.setLastPullCursor(serverTime);
  }

  Future<void> _recordPreparedDownload(
    PreparedSyncVaultDownload download,
  ) async {
    await _recordPulledItems(download.items, download.serverTime);
    await _recordPulledBlobs(download.blobs, download.blobServerTime);
  }

  Future<void> _recordPulledBlobs(
    List<SyncBlob> blobs,
    String serverTime,
  ) async {
    final syncState = _requireSyncState();
    for (final blob in blobs) {
      await syncState.saveBlobState(
        SyncBlobState(
          blobId: blob.id,
          serverRevision: blob.payload.revision,
          serverUpdatedAt: blob.payload.serverUpdatedAt,
        ),
      );
    }
    await syncState.setLastBlobPullCursor(serverTime);
  }

  Future<void> logout() async {
    final tokens = await _credentials.readTokens();
    Object? logoutError;
    StackTrace? logoutStackTrace;
    if (tokens != null) {
      try {
        await _logoutWithRefreshRetry(tokens);
      } catch (error, stackTrace) {
        logoutError = error;
        logoutStackTrace = stackTrace;
      }
    }

    await _credentials.clear();
    await _syncState?.clearAll();

    if (logoutError != null) {
      Error.throwWithStackTrace(logoutError, logoutStackTrace!);
    }
  }

  Future<void> _ensureDeviceRegistered(
    String accessToken, {
    required String accountEmail,
  }) async {
    final deviceId = await _credentials.readDeviceId();
    final deviceAccountEmail = await _credentials.readDeviceAccountEmail();
    if (deviceId != null && deviceAccountEmail == accountEmail) {
      return;
    }
    if (deviceId != null || deviceAccountEmail != null) {
      await _credentials.clearDeviceRegistration();
      await _syncState?.clearAll();
    }
    final device = await _api.registerDevice(
      accessToken: accessToken,
      deviceName: _deviceName(),
      deviceType: _deviceType,
      platform: _platform,
      clientVersion: _clientVersion,
    );
    await _credentials.saveDeviceId(device.id);
    await _credentials.saveDeviceAccountEmail(accountEmail);
    await _syncState?.setDeviceId(device.id);
  }

  Future<void> _logoutWithRefreshRetry(SyncAuthTokens tokens) async {
    try {
      await _api.logout(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    } on SyncApiException catch (error) {
      if (!_shouldRefresh(error)) {
        rethrow;
      }
      final refreshed = await _api.refresh(refreshToken: tokens.refreshToken);
      await _api.logout(
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken,
      );
    }
  }

  Future<SyncAuthTokens> _requireTokens() async {
    final tokens = await _credentials.readTokens();
    if (tokens == null) {
      throw StateError('Sync auth tokens are not available');
    }
    return tokens;
  }

  SyncStateDao _requireSyncState() {
    final syncState = _syncState;
    if (syncState == null) {
      throw StateError('Sync state store is not available');
    }
    return syncState;
  }

  Future<String> _requireSyncDeviceId(SyncStateDao syncState) async {
    final deviceId =
        await _credentials.readDeviceId() ?? await syncState.deviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw StateError('Sync device id is not available');
    }
    return deviceId;
  }

  Future<String> _requireDeviceId() async {
    final deviceId =
        await _credentials.readDeviceId() ?? await _syncState?.deviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw StateError('Sync device id is not available');
    }
    return deviceId;
  }

  bool _shouldRefresh(SyncApiException error) {
    return error.statusCode == 401 &&
        (error.code == 'TOKEN_EXPIRED' || error.code == 'UNAUTHORIZED');
  }
}

void _assertNoMixedItemPushResponse(SyncPushResponse response) {
  if (response.applied.isNotEmpty && response.conflicts.isNotEmpty) {
    throw StateError(
      'Sync push protocol violation: applied items returned with conflicts',
    );
  }
}

void _assertNoMixedBlobPushResponse(SyncBlobPushResponse response) {
  if (response.applied.isNotEmpty && response.conflicts.isNotEmpty) {
    throw StateError(
      'Sync push protocol violation: applied blobs returned with conflicts',
    );
  }
}

void _assertNoMixedVaultPushResponse(SyncVaultPushResponse response) {
  _assertNoMixedItemPushResponse(response.items);
  _assertNoMixedBlobPushResponse(response.blobs);
  final hasConflicts =
      response.items.conflicts.isNotEmpty ||
      response.blobs.conflicts.isNotEmpty;
  final hasApplied =
      response.items.applied.isNotEmpty || response.blobs.applied.isNotEmpty;
  if (hasConflicts && hasApplied) {
    throw StateError(
      'Sync vault push protocol violation: applied rows returned with conflicts',
    );
  }
}

String _defaultDeviceName() => 'Lockly device';
