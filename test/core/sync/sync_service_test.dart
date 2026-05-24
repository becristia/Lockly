import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/sync/sync_api_client.dart';
import 'package:secure_box/core/sync/sync_credential_store.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/core/sync/sync_payload_guard.dart';
import 'package:secure_box/core/sync/sync_service.dart';
import 'package:secure_box/data/db/sync_state_dao.dart';
import 'package:secure_box/data/models/encrypted_vault_blob.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';

void main() {
  test('login saves tokens and registers a local device once', () async {
    final api = _FakeSyncApiClient();
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    final service = SyncService(
      api: api,
      credentials: store,
      deviceName: () => 'Work laptop',
      deviceType: 'desktop',
    );

    await service.login(email: 'user@example.test', password: 'sync-password');

    expect(await store.readTokens(), _tokens('login-access', 'login-refresh'));
    expect(await store.readDeviceId(), 'device-1');
    expect(api.calls, [
      'login:user@example.test:sync-password',
      'registerDevice:login-access:Work laptop:desktop',
    ]);

    await service.login(email: 'user@example.test', password: 'sync-password');

    expect(api.calls.where((call) => call.startsWith('registerDevice')), [
      'registerDevice:login-access:Work laptop:desktop',
    ]);
  });

  test(
    'login includes device platform and client version when registering',
    () async {
      final api = _FakeSyncApiClient();
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      final service = SyncService(
        api: api,
        credentials: store,
        deviceName: () => 'Work laptop',
        deviceType: 'desktop',
        platform: 'windows',
        clientVersion: '1.4.2',
      );

      await service.login(
        email: 'user@example.test',
        password: 'sync-password',
      );

      expect(api.calls, [
        'login:user@example.test:sync-password',
        'registerDevice:login-access:Work laptop:desktop:windows:1.4.2',
      ]);
    },
  );

  test('login registers a new device when the cloud account changes', () async {
    final api = _FakeSyncApiClient();
    final storage = _InMemorySyncSecureStorage();
    final store = SyncCredentialStore(storage);
    final syncState = _InMemorySyncStateDao();
    await store.saveDeviceId('old-account-device');
    await store.saveDeviceAccountEmail('old@example.test');
    await syncState.setDeviceId('old-account-device');
    await syncState.setLastPullCursor('2026-05-23T00:00:00Z');
    await syncState.saveItemState(
      const SyncItemState(
        itemId: 'item-1',
        serverRevision: 7,
        serverUpdatedAt: '2026-05-23T00:00:00Z',
      ),
    );
    await syncState.saveConflict(
      const SyncConflictRecord(
        itemId: 'item-1',
        clientRevision: 7,
        serverRevision: 8,
        remotePayload: '{}',
        createdAt: 1779465600000,
      ),
    );
    final service = SyncService(
      api: api,
      credentials: store,
      syncState: syncState,
      deviceName: () => 'Work laptop',
      deviceType: 'desktop',
    );

    await service.login(email: 'new@example.test', password: 'sync-password');

    expect(await store.readDeviceId(), 'device-1');
    expect(await store.readDeviceAccountEmail(), 'new@example.test');
    expect(await syncState.deviceId(), 'device-1');
    expect(await syncState.lastPullCursor(), isNull);
    expect(await syncState.itemState('item-1'), isNull);
    expect(await syncState.conflicts(), isEmpty);
    expect(api.calls, [
      'login:new@example.test:sync-password',
      'registerDevice:login-access:Work laptop:desktop',
    ]);
  });

  test(
    'login clears old device binding before account-change registration',
    () async {
      final api = _FakeSyncApiClient()
        ..registerDeviceError = const SyncApiException(
          statusCode: 503,
          code: 'SERVICE_UNAVAILABLE',
        );
      final storage = _InMemorySyncSecureStorage();
      final store = SyncCredentialStore(storage);
      final syncState = _InMemorySyncStateDao();
      await store.saveDeviceId('old-account-device');
      await store.saveDeviceAccountEmail('old@example.test');
      await syncState.setDeviceId('old-account-device');
      await syncState.setLastPullCursor('2026-05-23T00:00:00Z');
      final service = SyncService(
        api: api,
        credentials: store,
        syncState: syncState,
        deviceName: () => 'Work laptop',
        deviceType: 'desktop',
      );

      await expectLater(
        service.login(email: 'new@example.test', password: 'sync-password'),
        throwsA(isA<SyncApiException>()),
      );

      expect(
        await store.readTokens(),
        _tokens('login-access', 'login-refresh'),
      );
      expect(await store.readDeviceId(), isNull);
      expect(await store.readDeviceAccountEmail(), isNull);
      expect(await syncState.deviceId(), isNull);
      expect(await syncState.lastPullCursor(), isNull);
    },
  );

  test('login reuses the device when the same cloud account logs in', () async {
    final api = _FakeSyncApiClient();
    final storage = _InMemorySyncSecureStorage();
    final store = SyncCredentialStore(storage);
    await store.saveDeviceId('device-1');
    await store.saveDeviceAccountEmail('user@example.test');
    final service = SyncService(
      api: api,
      credentials: store,
      deviceName: () => 'Work laptop',
      deviceType: 'desktop',
    );

    await service.login(email: 'user@example.test', password: 'sync-password');

    expect(await store.readDeviceId(), 'device-1');
    expect(api.calls, ['login:user@example.test:sync-password']);
  });

  test(
    'renameDevice refreshes expired token then returns updated device',
    () async {
      final api = _FakeSyncApiClient()
        ..renameDeviceErrors.add(
          const SyncApiException(statusCode: 401, code: 'TOKEN_EXPIRED'),
        );
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      await store.saveTokens(_tokens('expired-access', 'refresh-1'));
      final service = SyncService(
        api: api,
        credentials: store,
        deviceName: () => 'Phone',
      );

      final device = await service.renameDevice('device-1', 'Travel laptop');

      expect(device.deviceName, 'Travel laptop');
      expect(api.calls, [
        'renameDevice:expired-access:device-1:Travel laptop',
        'refresh:refresh-1',
        'renameDevice:refresh-access:device-1:Travel laptop',
      ]);
    },
  );

  test('register creates account then follows the same login flow', () async {
    final api = _FakeSyncApiClient();
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    final service = SyncService(
      api: api,
      credentials: store,
      deviceName: () => 'Phone',
    );

    final account = await service.register(
      email: 'new@example.test',
      password: 'sync-password',
    );

    expect(account.id, 'account-1');
    expect(await store.readTokens(), _tokens('login-access', 'login-refresh'));
    expect(await store.readDeviceId(), 'device-1');
    expect(api.calls, [
      'register:new@example.test:sync-password',
      'login:new@example.test:sync-password',
      'registerDevice:login-access:Phone:null',
    ]);
  });

  test(
    'authenticated operations refresh once on expired token then retry',
    () async {
      final api = _FakeSyncApiClient()
        ..listDevicesErrors.add(
          const SyncApiException(statusCode: 401, code: 'TOKEN_EXPIRED'),
        );
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      await store.saveTokens(_tokens('expired-access', 'refresh-1'));
      final service = SyncService(
        api: api,
        credentials: store,
        deviceName: () => 'Phone',
      );

      final devices = await service.listDevices();

      expect(devices.single.id, 'device-1');
      expect(await store.readTokens(), _tokens('refresh-access', 'refresh-2'));
      expect(api.calls, [
        'listDevices:expired-access',
        'refresh:refresh-1',
        'listDevices:refresh-access',
      ]);
    },
  );

  test('emergency access wrappers pass access token to api', () async {
    final api = _FakeSyncApiClient();
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    await store.saveTokens(_tokens('access', 'refresh'));
    final service = SyncService(api: api, credentials: store);

    final contact = await service.createEmergencyContact(
      request: const EmergencyContactCreateRequest(
        recipientEmail: 'friend@example.test',
        recipientPublicKey: 'recipient-public-key',
        recipientKeyFingerprint: 'fingerprint-1',
        recipientLabel: 'Friend',
      ),
    );
    final contacts = await service.listEmergencyContacts();
    final revokedContact = await service.revokeEmergencyContact('contact-1');
    final grant = await service.createEmergencyGrant(
      request: const EmergencyGrantCreateRequest(
        contactId: 'contact-1',
        waitingPeriodHours: 24,
        encryptedRecoveryPackage: _safeEmergencyPackageEnvelope,
        packageAad: _safeEmergencyPackageAad,
        packageFingerprint: 'package-fingerprint-1',
      ),
    );
    final grants = await service.listEmergencyGrants();
    final accepted = await service.acceptEmergencyGrant(
      grantId: 'grant-1',
      recipientKeyFingerprint: 'fingerprint-1',
    );
    final requested = await service.requestEmergencyGrantAccess(
      grantId: 'grant-1',
      requestMessageCiphertext: 'request-ciphertext',
      requestMessageAad: _safeEmergencyRequestMessageAad,
    );
    final cancelled = await service.cancelEmergencyGrant('grant-1');
    final revokedGrant = await service.revokeEmergencyGrant('grant-1');
    final package = await service.downloadEmergencyAccessPackage('grant-1');

    expect(contact.id, 'contact-1');
    expect(contacts.single.id, 'contact-1');
    expect(revokedContact.status, 'revoked');
    expect(grant.id, 'grant-1');
    expect(grants.single.id, 'grant-1');
    expect(accepted.status, 'active');
    expect(requested.status, 'access_requested');
    expect(cancelled.status, 'cancelled');
    expect(revokedGrant.status, 'revoked');
    expect(package.encryptedRecoveryPackage, _safeEmergencyPackageEnvelope);
    expect(api.calls, [
      'createEmergencyContact:access:friend@example.test',
      'listEmergencyContacts:access',
      'revokeEmergencyContact:access:contact-1',
      'createEmergencyGrant:access:contact-1',
      'listEmergencyGrants:access',
      'acceptEmergencyGrant:access:grant-1:fingerprint-1',
      'requestEmergencyGrantAccess:access:grant-1:request-ciphertext:$_safeEmergencyRequestMessageAad',
      'cancelEmergencyGrant:access:grant-1',
      'revokeEmergencyGrant:access:grant-1',
      'downloadEmergencyAccessPackage:access:grant-1',
    ]);
  });

  test('emergency access wrappers refresh expired token then retry', () async {
    final api = _FakeSyncApiClient()
      ..listEmergencyGrantsErrors.add(
        const SyncApiException(statusCode: 401, code: 'TOKEN_EXPIRED'),
      );
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    await store.saveTokens(_tokens('expired-access', 'refresh-1'));
    final service = SyncService(api: api, credentials: store);

    final grants = await service.listEmergencyGrants();

    expect(grants.single.id, 'grant-1');
    expect(await store.readTokens(), _tokens('refresh-access', 'refresh-2'));
    expect(api.calls, [
      'listEmergencyGrants:expired-access',
      'refresh:refresh-1',
      'listEmergencyGrants:refresh-access',
    ]);
  });

  test('authenticated operations do not refresh forever', () async {
    final api = _FakeSyncApiClient()
      ..listDevicesErrors.addAll([
        const SyncApiException(statusCode: 401, code: 'UNAUTHORIZED'),
        const SyncApiException(statusCode: 401, code: 'UNAUTHORIZED'),
      ]);
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    await store.saveTokens(_tokens('expired-access', 'refresh-1'));
    final service = SyncService(
      api: api,
      credentials: store,
      deviceName: () => 'Phone',
    );

    await expectLater(service.listDevices(), throwsA(isA<SyncApiException>()));

    expect(api.calls, [
      'listDevices:expired-access',
      'refresh:refresh-1',
      'listDevices:refresh-access',
    ]);
  });

  test('non-authentication api failures are not refreshed', () async {
    final api = _FakeSyncApiClient()
      ..listDevicesErrors.add(
        const SyncApiException(statusCode: 500, code: 'SERVER_ERROR'),
      );
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    await store.saveTokens(_tokens('access', 'refresh'));
    final service = SyncService(
      api: api,
      credentials: store,
      deviceName: () => 'Phone',
    );

    await expectLater(service.listDevices(), throwsA(isA<SyncApiException>()));

    expect(api.calls, ['listDevices:access']);
  });

  test('revoke current device clears local sync credentials', () async {
    final api = _FakeSyncApiClient();
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    final syncState = _InMemorySyncStateDao();
    await store.saveTokens(_tokens('access', 'refresh'));
    await store.saveDeviceId('device-1');
    await syncState.setDeviceId('device-1');
    final service = SyncService(
      api: api,
      credentials: store,
      syncState: syncState,
      deviceName: () => 'Phone',
    );

    await service.revokeDevice('device-1');

    expect(await store.readDeviceId(), isNull);
    expect(await store.readTokens(), isNull);
    expect(await syncState.deviceId(), isNull);
    expect(api.calls, ['revokeDevice:access:device-1']);
  });

  test('logout refreshes expired access token before remote logout', () async {
    final api = _FakeSyncApiClient()
      ..logoutErrors.add(
        const SyncApiException(statusCode: 401, code: 'TOKEN_EXPIRED'),
      );
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    await store.saveTokens(_tokens('expired-access', 'refresh-1'));
    await store.saveDeviceId('device-1');
    final service = SyncService(
      api: api,
      credentials: store,
      deviceName: () => 'Phone',
    );

    await service.logout();

    expect(await store.readTokens(), isNull);
    expect(await store.readDeviceId(), isNull);
    expect(api.calls, [
      'logout:expired-access:refresh-1',
      'refresh:refresh-1',
      'logout:refresh-access:refresh-2',
    ]);
  });

  test('logout clears local state even when backend logout fails', () async {
    final api = _FakeSyncApiClient()
      ..logoutError = const SyncApiException(
        statusCode: 503,
        code: 'SERVICE_UNAVAILABLE',
      );
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    await store.saveTokens(_tokens('access', 'refresh'));
    await store.saveDeviceId('device-1');
    final syncState = _InMemorySyncStateDao();
    await syncState.setDeviceId('device-1');
    final service = SyncService(
      api: api,
      credentials: store,
      syncState: syncState,
      deviceName: () => 'Phone',
    );

    await expectLater(service.logout(), throwsA(isA<SyncApiException>()));

    expect(await store.readTokens(), isNull);
    expect(await store.readDeviceId(), isNull);
    expect(await syncState.deviceId(), isNull);
    expect(api.calls, ['logout:access:refresh']);
  });

  test('logout clears pull cursor, item state, and conflicts', () async {
    final api = _FakeSyncApiClient();
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    final syncState = _InMemorySyncStateDao();
    await store.saveTokens(_tokens('access', 'refresh'));
    await store.saveDeviceId('device-1');
    await syncState.setDeviceId('device-1');
    await syncState.setLastPullCursor('2026-05-23T00:00:00Z');
    await syncState.saveItemState(
      const SyncItemState(
        itemId: 'item-1',
        serverRevision: 7,
        serverUpdatedAt: '2026-05-23T00:00:00Z',
      ),
    );
    await syncState.saveConflict(
      const SyncConflictRecord(
        itemId: 'item-1',
        clientRevision: 7,
        serverRevision: 8,
        remotePayload: '{}',
        createdAt: 1779465600000,
      ),
    );
    final service = SyncService(
      api: api,
      credentials: store,
      syncState: syncState,
      deviceName: () => 'Phone',
    );

    await service.logout();

    expect(await syncState.deviceId(), isNull);
    expect(await syncState.lastPullCursor(), isNull);
    expect(await syncState.itemState('item-1'), isNull);
    expect(await syncState.conflicts(), isEmpty);
  });

  test(
    'pushEncryptedItems sends only encrypted payload and updates applied state',
    () async {
      final api = _FakeSyncApiClient();
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      final syncState = _InMemorySyncStateDao();
      await store.saveTokens(_tokens('access', 'refresh'));
      await syncState.setDeviceId('device-local');
      await syncState.saveItemState(
        const SyncItemState(
          itemId: 'item-1',
          serverRevision: 7,
          serverUpdatedAt: '2026-05-23T01:00:00Z',
        ),
      );
      final service = SyncService(
        api: api,
        credentials: store,
        syncState: syncState,
      );
      final localItem = _encryptedItem(
        id: 'item-1',
        ciphertext: 'ciphertext-v2',
        nonce: 'nonce-v2',
        mac: 'mac-v2',
      );
      api.pushResponse = SyncPushResponse(
        applied: [
          SyncItem(
            id: 'item-1',
            payload: SyncItemPayload.fromJson({
              'ciphertext': 'ciphertext-v2',
              'nonce': 'nonce-v2',
              'aad': jsonEncode({'mac': 'mac-v2', 'schema': 'lockly-item-v1'}),
              'revision': 8,
              'deleted': false,
              'client_updated_at': '2026-05-23T00:00:00.000Z',
              'server_updated_at': '2026-05-23T02:00:00Z',
            }),
          ),
        ],
        conflicts: const [],
      );

      await service.pushEncryptedItems(items: [localItem]);

      expect(api.calls, ['push:access:device-local']);
      expect(api.pushedItems, hasLength(1));
      final sent = api.pushedItems.single.toJson();
      expect(sent['item_id'], 'item-1');
      expect(sent['ciphertext'], 'ciphertext-v2');
      expect(sent['nonce'], 'nonce-v2');
      expect(jsonDecode(sent['aad']! as String), {
        'mac': 'mac-v2',
        'schema': 'lockly-item-v1',
      });
      expect(sent['revision'], 7);
      expect(findForbiddenSyncFields(sent), isEmpty);
      expect(
        await syncState.itemState('item-1'),
        const SyncItemState(
          itemId: 'item-1',
          serverRevision: 8,
          serverUpdatedAt: '2026-05-23T02:00:00Z',
        ),
      );
      expect(await syncState.conflicts(), isEmpty);
    },
  );

  test('pushEncryptedItems keeps conflicts for later resolution', () async {
    final api = _FakeSyncApiClient();
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    final syncState = _InMemorySyncStateDao();
    await store.saveTokens(_tokens('access', 'refresh'));
    await syncState.setDeviceId('device-local');
    final service = SyncService(
      api: api,
      credentials: store,
      syncState: syncState,
    );
    api.pushResponse = const SyncPushResponse(
      applied: [],
      conflicts: [
        SyncConflict(itemId: 'item-1', localRevision: 0, remoteRevision: 3),
      ],
    );

    await service.pushEncryptedItems(items: [_encryptedItem(id: 'item-1')]);

    final conflict = (await syncState.conflicts()).single;
    expect(conflict.itemId, 'item-1');
    expect(conflict.clientRevision, 0);
    expect(conflict.serverRevision, 3);
    expect(jsonDecode(conflict.remotePayload), {
      'item_id': 'item-1',
      'client_revision': 0,
      'server_revision': 3,
    });
    expect(
      findForbiddenSyncFields(jsonDecode(conflict.remotePayload)),
      isEmpty,
    );
  });

  test(
    'pushEncryptedItems rejects mixed applied and conflict responses',
    () async {
      final api = _FakeSyncApiClient();
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      final syncState = _InMemorySyncStateDao();
      await store.saveTokens(_tokens('access', 'refresh'));
      await syncState.setDeviceId('device-local');
      final service = SyncService(
        api: api,
        credentials: store,
        syncState: syncState,
      );
      api.pushResponse = SyncPushResponse(
        applied: [
          SyncItem(
            id: 'item-applied',
            payload: SyncItemPayload.fromJson({
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
              'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
              'revision': 2,
              'deleted': false,
              'client_updated_at': '2026-05-23T00:00:00Z',
              'server_updated_at': '2026-05-23T01:00:00Z',
            }),
          ),
        ],
        conflicts: const [
          SyncConflict(
            itemId: 'item-conflict',
            localRevision: 0,
            remoteRevision: 3,
          ),
        ],
      );

      await expectLater(
        service.pushEncryptedItems(items: [_encryptedItem(id: 'item-local')]),
        throwsStateError,
      );
      expect(await syncState.itemState('item-applied'), isNull);
      expect(await syncState.conflicts(), isEmpty);
    },
  );

  test(
    'pushEncryptedBlobs sends blob revisions and records metadata-only conflicts',
    () async {
      final api = _FakeSyncApiClient();
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      final syncState = _InMemorySyncStateDao();
      await store.saveTokens(_tokens('access', 'refresh'));
      await store.saveDeviceId('device-local');
      await syncState.saveBlobState(
        const SyncBlobState(
          blobId: 'blob-1',
          serverRevision: 6,
          serverUpdatedAt: '2026-05-23T01:00:00Z',
        ),
      );
      api.blobPushResponse = const SyncBlobPushResponse(
        applied: [],
        conflicts: [
          SyncBlobConflict(
            blobId: 'blob-2',
            localRevision: 0,
            remoteRevision: 3,
          ),
        ],
      );
      final service = SyncService(
        api: api,
        credentials: store,
        syncState: syncState,
      );

      await service.pushEncryptedBlobs(blobs: [_encryptedBlob()]);

      expect(api.calls, ['pushBlobs:access:device-local']);
      final sent = api.pushedBlobs.single.toJson();
      expect(sent['blob_id'], 'blob-1');
      expect(sent['item_id'], 'item-1');
      expect(sent['revision'], 6);
      expect(jsonDecode(sent['metadata_aad']! as String), {
        'mac': 'meta-mac',
        'schema': 'lockly-blob-meta-v1',
      });
      expect(jsonDecode(sent['aad']! as String), {
        'mac': 'content-mac',
        'schema': 'lockly-blob-v1',
      });
      expect(findForbiddenSyncFields(sent), isEmpty);
      final conflict = (await syncState.blobConflicts()).single;
      expect(conflict.blobId, 'blob-2');
      expect(jsonDecode(conflict.remotePayload), {
        'blob_id': 'blob-2',
        'client_revision': 0,
        'server_revision': 3,
      });
    },
  );

  test(
    'pushEncryptedBlobs rejects mixed applied and conflict responses',
    () async {
      final api = _FakeSyncApiClient();
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      final syncState = _InMemorySyncStateDao();
      await store.saveTokens(_tokens('access', 'refresh'));
      await store.saveDeviceId('device-local');
      final service = SyncService(
        api: api,
        credentials: store,
        syncState: syncState,
      );
      api.blobPushResponse = SyncBlobPushResponse(
        applied: [
          SyncBlob.fromJson({
            ..._safeBlobJson(revision: 2),
            'server_updated_at': '2026-05-23T01:00:00Z',
          }),
        ],
        conflicts: const [
          SyncBlobConflict(
            blobId: 'blob-conflict',
            localRevision: 0,
            remoteRevision: 3,
          ),
        ],
      );

      await expectLater(
        service.pushEncryptedBlobs(blobs: [_encryptedBlob()]),
        throwsStateError,
      );
      expect(await syncState.blobState('blob-1'), isNull);
      expect(await syncState.blobConflicts(), isEmpty);
    },
  );

  test(
    'pushEncryptedVault rejects cross-domain applied and conflict responses',
    () async {
      final api = _FakeSyncApiClient();
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      final syncState = _InMemorySyncStateDao();
      await store.saveTokens(_tokens('access', 'refresh'));
      await store.saveDeviceId('device-local');
      final service = SyncService(
        api: api,
        credentials: store,
        syncState: syncState,
      );
      api.vaultPushResponse = SyncVaultPushResponse(
        items: SyncPushResponse(
          applied: [
            SyncItem(
              id: 'item-applied',
              payload: SyncItemPayload.fromJson({
                'ciphertext': 'ciphertext',
                'nonce': 'nonce',
                'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
                'revision': 2,
                'deleted': false,
                'client_updated_at': '2026-05-23T00:00:00Z',
                'server_updated_at': '2026-05-23T01:00:00Z',
              }),
            ),
          ],
          conflicts: const [],
        ),
        blobs: const SyncBlobPushResponse(
          applied: [],
          conflicts: [
            SyncBlobConflict(
              blobId: 'blob-conflict',
              localRevision: 0,
              remoteRevision: 3,
            ),
          ],
        ),
      );

      await expectLater(
        service.pushEncryptedVault(
          items: [_encryptedItem(id: 'item-local')],
          blobs: [_encryptedBlob()],
        ),
        throwsStateError,
      );
      expect(await syncState.itemState('item-applied'), isNull);
      expect(await syncState.blobConflicts(), isEmpty);
    },
  );

  test('clearConflict removes one local conflict record', () async {
    final api = _FakeSyncApiClient();
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    final syncState = _InMemorySyncStateDao();
    final service = SyncService(
      api: api,
      credentials: store,
      syncState: syncState,
    );
    await syncState.saveConflict(
      const SyncConflictRecord(
        itemId: 'item-1',
        clientRevision: 1,
        serverRevision: 2,
        remotePayload: '{}',
        createdAt: 1770000000000,
      ),
    );
    await syncState.saveConflict(
      const SyncConflictRecord(
        itemId: 'item-2',
        clientRevision: 3,
        serverRevision: 4,
        remotePayload: '{}',
        createdAt: 1770000001000,
      ),
    );

    await service.clearConflict('item-1');

    expect((await syncState.conflicts()).map((conflict) => conflict.itemId), [
      'item-2',
    ]);
  });

  test(
    'pullEncryptedItems uses cursor and device then updates item state',
    () async {
      final api = _FakeSyncApiClient();
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      final syncState = _InMemorySyncStateDao();
      await store.saveTokens(_tokens('access', 'refresh'));
      await store.saveDeviceId('device-local');
      await syncState.setLastPullCursor('2026-05-23T02:00:00Z');
      final service = SyncService(
        api: api,
        credentials: store,
        syncState: syncState,
      );
      api.pullResponse = SyncPullResponse(
        serverTime: '2026-05-23T03:00:00Z',
        items: [
          SyncItem(
            id: 'item-1',
            payload: SyncItemPayload.fromJson({
              'ciphertext': 'remote-ciphertext',
              'nonce': 'remote-nonce',
              'aad': jsonEncode({'mac': 'remote-mac'}),
              'revision': 9,
              'deleted': false,
              'client_updated_at': '2026-05-23T00:00:00.000Z',
              'server_updated_at': '2026-05-23T03:00:00Z',
            }),
          ),
        ],
      );

      final items = await service.pullEncryptedItems();

      expect(api.calls, ['pull:access:2026-05-23T02:00:00Z:device-local']);
      expect(items.single.id, 'item-1');
      expect(items.single.payload.ciphertext, 'remote-ciphertext');
      expect(
        await syncState.itemState('item-1'),
        const SyncItemState(
          itemId: 'item-1',
          serverRevision: 9,
          serverUpdatedAt: '2026-05-23T03:00:00Z',
        ),
      );
      expect(await syncState.lastPullCursor(), '2026-05-23T03:00:00Z');
    },
  );

  test('SyncItemPayload rejects obvious plaintext secret assignment', () {
    expect(
      () => SyncItemPayload.fromJson({
        'ciphertext': 'password=cleartext-secret',
        'nonce': 'remote-nonce',
        'aad': jsonEncode({'mac': 'remote-mac'}),
        'revision': 1,
        'deleted': false,
        'client_updated_at': '2026-05-23T00:00:00.000Z',
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'SyncItemPayload allows opaque ciphertext with incidental key terms',
    () {
      final payload = SyncItemPayload.fromJson({
        'ciphertext': 'opaque-password-totp-passkey-rawkey-ciphertext',
        'nonce': 'opaque-nonce',
        'aad': jsonEncode({'mac': 'remote-mac'}),
        'revision': 1,
        'deleted': false,
        'client_updated_at': '2026-05-23T00:00:00.000Z',
      });

      expect(payload.ciphertext, contains('password'));
      expect(payload.ciphertext, contains('passkey'));
    },
  );

  test('pullEncryptedBlobs uses blob cursor and updates blob state', () async {
    final api = _FakeSyncApiClient();
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    final syncState = _InMemorySyncStateDao();
    await store.saveTokens(_tokens('access', 'refresh'));
    await store.saveDeviceId('device-local');
    await syncState.setLastBlobPullCursor('2026-05-23T02:00:00Z');
    api.blobPullResponse = SyncBlobPullResponse(
      serverTime: '2026-05-23T03:00:00Z',
      blobs: [
        SyncBlob.fromJson(
          _safeBlobJson(revision: 9, serverUpdatedAt: '2026-05-23T03:00:00Z'),
        ),
      ],
    );
    final service = SyncService(
      api: api,
      credentials: store,
      syncState: syncState,
    );

    final blobs = await service.pullEncryptedBlobs();

    expect(api.calls, ['pullBlobs:access:2026-05-23T02:00:00Z:device-local']);
    expect(blobs.single.id, 'blob-1');
    expect(
      await syncState.blobState('blob-1'),
      const SyncBlobState(
        blobId: 'blob-1',
        serverRevision: 9,
        serverUpdatedAt: '2026-05-23T03:00:00Z',
      ),
    );
    expect(await syncState.lastBlobPullCursor(), '2026-05-23T03:00:00Z');
  });

  test('pushEncryptedItems uses the device id saved by login', () async {
    final api = _FakeSyncApiClient();
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    final syncState = _InMemorySyncStateDao();
    final service = SyncService(
      api: api,
      credentials: store,
      syncState: syncState,
      deviceName: () => 'Phone',
    );

    await service.login(email: 'user@example.test', password: 'sync-password');
    await service.pushEncryptedItems(items: [_encryptedItem(id: 'item-1')]);

    expect(api.calls, [
      'login:user@example.test:sync-password',
      'registerDevice:login-access:Phone:null',
      'push:login-access:device-1',
    ]);
  });

  test('pushEncryptedItems refreshes expired token then retries', () async {
    final api = _FakeSyncApiClient()
      ..pushErrors.add(
        const SyncApiException(statusCode: 401, code: 'TOKEN_EXPIRED'),
      );
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    final syncState = _InMemorySyncStateDao();
    await store.saveTokens(_tokens('expired-access', 'refresh-1'));
    await store.saveDeviceId('device-local');
    final service = SyncService(
      api: api,
      credentials: store,
      syncState: syncState,
    );

    await service.pushEncryptedItems(items: [_encryptedItem(id: 'item-1')]);

    expect(api.calls, [
      'push:expired-access:device-local',
      'refresh:refresh-1',
      'push:refresh-access:device-local',
    ]);
  });

  test('pullEncryptedItems refreshes expired token then retries', () async {
    final api = _FakeSyncApiClient()
      ..pullErrors.add(
        const SyncApiException(statusCode: 401, code: 'UNAUTHORIZED'),
      );
    final store = SyncCredentialStore(_InMemorySyncSecureStorage());
    final syncState = _InMemorySyncStateDao();
    await store.saveTokens(_tokens('expired-access', 'refresh-1'));
    await store.saveDeviceId('device-local');
    final service = SyncService(
      api: api,
      credentials: store,
      syncState: syncState,
    );

    await service.pullEncryptedItems();

    expect(api.calls, [
      'pull:expired-access:1970-01-01T00:00:00.000Z:device-local',
      'refresh:refresh-1',
      'pull:refresh-access:1970-01-01T00:00:00.000Z:device-local',
    ]);
  });

  test(
    'uploadVaultMeta initializes missing vault then keeps manifest synced',
    () async {
      final api = _FakeSyncApiClient()
        ..getVaultMetaErrors.add(
          const SyncApiException(
            statusCode: 404,
            code: 'VAULT_NOT_INITIALIZED',
          ),
        );
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      await store.saveTokens(_tokens('access', 'refresh'));
      await store.saveDeviceId('device-local');
      final service = SyncService(api: api, credentials: store);
      final meta = _syncVaultMeta();

      await service.uploadVaultMeta(meta);

      expect(api.calls, [
        'getVaultMeta:access:device-local',
        'initVault:access',
      ]);
      expect(api.savedVaultMeta!.manifest!['mac'], 'manifest-mac');
    },
  );

  test(
    'uploadVaultMeta updates with the current server metadata revision',
    () async {
      final api = _FakeSyncApiClient()
        ..vaultMeta = _syncVaultMeta(revision: 11);
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      await store.saveTokens(_tokens('access', 'refresh'));
      await store.saveDeviceId('device-local');
      final service = SyncService(api: api, credentials: store);
      final localMeta = _syncVaultMeta(revision: 99);

      await service.uploadVaultMeta(localMeta);

      expect(api.calls, [
        'getVaultMeta:access:device-local',
        'updateVaultMeta:access:device-local',
      ]);
      expect(api.savedVaultMeta!.revision, 11);
      expect(api.savedVaultMeta!.manifest!['mac'], 'manifest-mac');
    },
  );

  test(
    'downloadEncryptedVaultBackupJson pulls full encrypted cloud vault',
    () async {
      final api = _FakeSyncApiClient();
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      final syncState = _InMemorySyncStateDao();
      await store.saveTokens(_tokens('access', 'refresh'));
      await store.saveDeviceId('device-local');
      await syncState.setLastPullCursor('2026-05-23T02:00:00Z');
      api.vaultMeta = _syncVaultMeta();
      api.pullResponse = SyncPullResponse(
        serverTime: '2026-05-23T03:00:00Z',
        items: [
          SyncItem(
            id: 'item-1',
            payload: SyncItemPayload.fromJson({
              'ciphertext': 'remote-ciphertext',
              'nonce': 'remote-nonce',
              'aad': jsonEncode({
                'mac': 'remote-mac',
                'schema': 'lockly-item-v1',
              }),
              'revision': 9,
              'deleted': false,
              'client_updated_at': '2026-05-23T00:00:00.000Z',
              'server_updated_at': '2026-05-23T03:00:00Z',
            }),
          ),
        ],
      );
      api.blobPullResponse = SyncBlobPullResponse(
        serverTime: '2026-05-23T03:30:00Z',
        blobs: [SyncBlob.fromJson(_safeBlobJson())],
      );
      final service = SyncService(
        api: api,
        credentials: store,
        syncState: syncState,
      );

      final download = await service.prepareEncryptedVaultDownload();
      final backupJson = download.backupJson;
      final backup = jsonDecode(backupJson) as Map<String, Object?>;

      expect(api.calls, [
        'getVaultMeta:access:device-local',
        'pull:access:1970-01-01T00:00:00.000Z:device-local',
        'pullBlobs:access:1970-01-01T00:00:00.000Z:device-local',
      ]);
      expect(backup['encrypted_dek_by_master'], 'dek-ciphertext');
      expect(backup['manifest'], isA<Map<String, Object?>>());
      expect((backup['items']! as List<Object?>), hasLength(1));
      expect((backup['blobs']! as List<Object?>), hasLength(1));
      expect(await syncState.lastPullCursor(), '2026-05-23T02:00:00Z');
      expect(await syncState.lastBlobPullCursor(), isNull);

      await service.commitEncryptedVaultDownload(download);

      expect(await syncState.lastPullCursor(), '2026-05-23T03:00:00Z');
      expect(await syncState.lastBlobPullCursor(), '2026-05-23T03:30:00Z');
    },
  );

  test(
    'encrypted sync operations require token and device before requesting',
    () async {
      final api = _FakeSyncApiClient();
      final store = SyncCredentialStore(_InMemorySyncSecureStorage());
      final syncState = _InMemorySyncStateDao();
      final service = SyncService(
        api: api,
        credentials: store,
        syncState: syncState,
      );

      await expectLater(
        service.pushEncryptedItems(items: [_encryptedItem(id: 'item-1')]),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.pullEncryptedItems(),
        throwsA(isA<StateError>()),
      );
      expect(api.calls, isEmpty);

      await store.saveTokens(_tokens('access', 'refresh'));
      await expectLater(
        service.pushEncryptedItems(items: [_encryptedItem(id: 'item-1')]),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.pullEncryptedItems(),
        throwsA(isA<StateError>()),
      );
      expect(api.calls, isEmpty);
    },
  );
}

SyncAuthTokens _tokens(String access, String refresh) {
  return SyncAuthTokens(
    accessToken: access,
    refreshToken: refresh,
    tokenType: 'bearer',
  );
}

class _FakeSyncApiClient extends SyncApiClient {
  _FakeSyncApiClient()
    : super(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: (_) async => SyncHttpResponse(500, const {}),
      );

  final List<String> calls = [];
  final List<SyncApiException> listDevicesErrors = [];
  final List<SyncApiException> logoutErrors = [];
  final List<SyncApiException> pushErrors = [];
  final List<SyncApiException> pullErrors = [];
  final List<SyncApiException> getVaultMetaErrors = [];
  final List<SyncApiException> renameDeviceErrors = [];
  final List<SyncApiException> listEmergencyGrantsErrors = [];
  final List<SyncItem> pushedItems = [];
  final List<SyncBlob> pushedBlobs = [];
  SyncApiException? registerDeviceError;
  SyncApiException? logoutError;
  SyncVaultMetaPayload? vaultMeta = _syncVaultMeta();
  SyncVaultMetaPayload? savedVaultMeta;
  SyncPushResponse pushResponse = const SyncPushResponse(
    applied: [],
    conflicts: [],
  );
  SyncPullResponse pullResponse = const SyncPullResponse(
    serverTime: '2026-05-23T00:00:00Z',
    items: [],
  );
  SyncBlobPushResponse blobPushResponse = const SyncBlobPushResponse(
    applied: [],
    conflicts: [],
  );
  SyncVaultPushResponse vaultPushResponse = const SyncVaultPushResponse(
    items: SyncPushResponse(applied: [], conflicts: []),
    blobs: SyncBlobPushResponse(applied: [], conflicts: []),
  );
  SyncBlobPullResponse blobPullResponse = const SyncBlobPullResponse(
    serverTime: '2026-05-23T00:00:00Z',
    blobs: [],
  );

  @override
  Future<SyncAccount> register({
    required String email,
    required String password,
  }) async {
    calls.add('register:$email:$password');
    return const SyncAccount(id: 'account-1', email: 'new@example.test');
  }

  @override
  Future<SyncAuthTokens> login({
    required String email,
    required String password,
  }) async {
    calls.add('login:$email:$password');
    return _tokens('login-access', 'login-refresh');
  }

  @override
  Future<SyncAuthTokens> refresh({required String refreshToken}) async {
    calls.add('refresh:$refreshToken');
    return _tokens('refresh-access', 'refresh-2');
  }

  @override
  Future<void> logout({
    required String accessToken,
    required String refreshToken,
  }) async {
    calls.add('logout:$accessToken:$refreshToken');
    if (logoutErrors.isNotEmpty) {
      throw logoutErrors.removeAt(0);
    }
    final error = logoutError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<SyncDevice> registerDevice({
    required String accessToken,
    required String deviceName,
    String? deviceType,
    String? platform,
    String? clientVersion,
  }) async {
    calls.add(
      [
        'registerDevice',
        accessToken,
        deviceName,
        '$deviceType',
        if (platform != null || clientVersion != null) ...[
          '$platform',
          '$clientVersion',
        ],
      ].join(':'),
    );
    final error = registerDeviceError;
    if (error != null) {
      throw error;
    }
    return _device('device-1');
  }

  @override
  Future<SyncDevice> renameDevice({
    required String accessToken,
    required String deviceId,
    required String deviceName,
  }) async {
    calls.add('renameDevice:$accessToken:$deviceId:$deviceName');
    if (renameDeviceErrors.isNotEmpty) {
      throw renameDeviceErrors.removeAt(0);
    }
    return _device(deviceId, deviceName: deviceName);
  }

  @override
  Future<List<SyncDevice>> listDevices({required String accessToken}) async {
    calls.add('listDevices:$accessToken');
    if (listDevicesErrors.isNotEmpty) {
      throw listDevicesErrors.removeAt(0);
    }
    return [_device('device-1')];
  }

  @override
  Future<void> revokeDevice({
    required String accessToken,
    required String deviceId,
  }) async {
    calls.add('revokeDevice:$accessToken:$deviceId');
  }

  @override
  Future<SyncVaultMetaPayload> initVault({
    required String accessToken,
    required SyncVaultMetaPayload meta,
  }) async {
    calls.add('initVault:$accessToken');
    savedVaultMeta = meta;
    vaultMeta = meta;
    return meta;
  }

  @override
  Future<SyncVaultMetaPayload> getVaultMeta({
    required String accessToken,
    required String deviceId,
  }) async {
    calls.add('getVaultMeta:$accessToken:$deviceId');
    if (getVaultMetaErrors.isNotEmpty) {
      throw getVaultMetaErrors.removeAt(0);
    }
    return vaultMeta!;
  }

  @override
  Future<SyncVaultMetaPayload> updateVaultMeta({
    required String accessToken,
    required String deviceId,
    required SyncVaultMetaPayload meta,
  }) async {
    calls.add('updateVaultMeta:$accessToken:$deviceId');
    savedVaultMeta = meta;
    vaultMeta = meta;
    return meta;
  }

  @override
  Future<SyncPushResponse> push({
    required String accessToken,
    required String deviceId,
    required List<SyncItem> items,
  }) async {
    calls.add('push:$accessToken:$deviceId');
    pushedItems.addAll(items);
    if (pushErrors.isNotEmpty) {
      throw pushErrors.removeAt(0);
    }
    return pushResponse;
  }

  @override
  Future<SyncPullResponse> pull({
    required String accessToken,
    required String since,
    required String deviceId,
  }) async {
    calls.add('pull:$accessToken:$since:$deviceId');
    if (pullErrors.isNotEmpty) {
      throw pullErrors.removeAt(0);
    }
    return pullResponse;
  }

  @override
  Future<SyncBlobPushResponse> pushBlobs({
    required String accessToken,
    required String deviceId,
    required List<SyncBlob> blobs,
  }) async {
    calls.add('pushBlobs:$accessToken:$deviceId');
    pushedBlobs.addAll(blobs);
    return blobPushResponse;
  }

  @override
  Future<SyncVaultPushResponse> pushVault({
    required String accessToken,
    required String deviceId,
    required List<SyncItem> items,
    required List<SyncBlob> blobs,
  }) async {
    calls.add('pushVault:$accessToken:$deviceId');
    pushedItems.addAll(items);
    pushedBlobs.addAll(blobs);
    return vaultPushResponse;
  }

  @override
  Future<SyncBlobPullResponse> pullBlobs({
    required String accessToken,
    required String since,
    required String deviceId,
  }) async {
    calls.add('pullBlobs:$accessToken:$since:$deviceId');
    return blobPullResponse;
  }

  @override
  Future<EmergencyContact> createEmergencyContact({
    required String accessToken,
    required EmergencyContactCreateRequest request,
  }) async {
    calls.add('createEmergencyContact:$accessToken:${request.recipientEmail}');
    return _emergencyContact();
  }

  @override
  Future<List<EmergencyContact>> listEmergencyContacts({
    required String accessToken,
  }) async {
    calls.add('listEmergencyContacts:$accessToken');
    return [_emergencyContact()];
  }

  @override
  Future<EmergencyContact> revokeEmergencyContact({
    required String accessToken,
    required String contactId,
  }) async {
    calls.add('revokeEmergencyContact:$accessToken:$contactId');
    return _emergencyContact(
      status: 'revoked',
      revokedAt: '2026-05-24T01:00:00Z',
    );
  }

  @override
  Future<EmergencyGrant> createEmergencyGrant({
    required String accessToken,
    required EmergencyGrantCreateRequest request,
  }) async {
    calls.add('createEmergencyGrant:$accessToken:${request.contactId}');
    return _emergencyGrant();
  }

  @override
  Future<List<EmergencyGrant>> listEmergencyGrants({
    required String accessToken,
  }) async {
    calls.add('listEmergencyGrants:$accessToken');
    if (listEmergencyGrantsErrors.isNotEmpty) {
      throw listEmergencyGrantsErrors.removeAt(0);
    }
    return [_emergencyGrant()];
  }

  @override
  Future<EmergencyGrant> acceptEmergencyGrant({
    required String accessToken,
    required String grantId,
    required String recipientKeyFingerprint,
  }) async {
    calls.add(
      'acceptEmergencyGrant:$accessToken:$grantId:$recipientKeyFingerprint',
    );
    return _emergencyGrant(status: 'active');
  }

  @override
  Future<EmergencyGrant> requestEmergencyGrantAccess({
    required String accessToken,
    required String grantId,
    String? requestMessageCiphertext,
    String? requestMessageAad,
  }) async {
    calls.add(
      'requestEmergencyGrantAccess:$accessToken:$grantId:$requestMessageCiphertext:$requestMessageAad',
    );
    return _emergencyGrant(status: 'access_requested');
  }

  @override
  Future<EmergencyGrant> cancelEmergencyGrant({
    required String accessToken,
    required String grantId,
  }) async {
    calls.add('cancelEmergencyGrant:$accessToken:$grantId');
    return _emergencyGrant(status: 'cancelled');
  }

  @override
  Future<EmergencyGrant> revokeEmergencyGrant({
    required String accessToken,
    required String grantId,
  }) async {
    calls.add('revokeEmergencyGrant:$accessToken:$grantId');
    return _emergencyGrant(status: 'revoked');
  }

  @override
  Future<EmergencyAccessPackage> downloadEmergencyAccessPackage({
    required String accessToken,
    required String grantId,
  }) async {
    calls.add('downloadEmergencyAccessPackage:$accessToken:$grantId');
    return _emergencyAccessPackage();
  }
}

SyncDevice _device(String id, {String deviceName = 'Phone'}) {
  return SyncDevice(
    id: id,
    deviceName: deviceName,
    deviceType: 'mobile',
    trusted: true,
    createdAt: '2026-05-23T10:00:00Z',
  );
}

class _InMemorySyncSecureStorage implements SyncSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

EncryptedVaultItem _encryptedItem({
  required String id,
  String ciphertext = 'ciphertext',
  String nonce = 'nonce',
  String mac = 'mac',
}) {
  return EncryptedVaultItem(
    id: id,
    nonce: nonce,
    ciphertext: ciphertext,
    mac: mac,
    createdAt: 1779494400000,
    updatedAt: 1779494400000,
  );
}

EncryptedVaultBlob _encryptedBlob({
  String blobId = 'blob-1',
  String itemId = 'item-1',
}) {
  return EncryptedVaultBlob(
    blobId: blobId,
    itemId: itemId,
    metadataNonce: 'meta-nonce',
    metadataCiphertext: 'meta-ciphertext',
    metadataMac: 'meta-mac',
    nonce: 'content-nonce',
    ciphertext: 'content-ciphertext',
    mac: 'content-mac',
    createdAt: 1779494400000,
    updatedAt: 1779494400000,
  );
}

Map<String, Object?> _safeBlobJson({
  int revision = 1,
  String? serverUpdatedAt = '2026-05-23T10:00:00Z',
}) {
  return {
    'blob_id': 'blob-1',
    'item_id': 'item-1',
    'metadata_ciphertext': 'meta-ciphertext',
    'metadata_nonce': 'meta-nonce',
    'metadata_aad': '{"mac":"meta-mac","schema":"lockly-blob-meta-v1"}',
    'ciphertext': 'content-ciphertext',
    'nonce': 'content-nonce',
    'aad': '{"mac":"content-mac","schema":"lockly-blob-v1"}',
    'ciphertext_sha256':
        '32e09955ad05411c67617336e6a7026bd1828b3453f15f427b87667a61960d6e',
    'ciphertext_size': 18,
    'revision': revision,
    'deleted': false,
    'client_updated_at': '2026-05-23T09:00:00Z',
    'server_updated_at': serverUpdatedAt,
  };
}

SyncVaultMetaPayload _syncVaultMeta({int revision = 2}) {
  return SyncVaultMetaPayload.fromJson({
    'id': 'vault-1',
    'kdf': 'argon2id',
    'kdf_params': {
      'name': 'argon2id',
      'memoryKiB': 65536,
      'iterations': 3,
      'parallelism': 1,
      'bits': 256,
    },
    'salt': 'salt-b64',
    'encrypted_dek_by_master': jsonEncode({
      'ciphertext': 'dek-ciphertext',
      'nonce': 'dek-nonce',
      'mac': 'dek-mac',
    }),
    'manifest': {
      'version': 1,
      'epoch': 1,
      'counter': 5,
      'nonce': 'manifest-nonce',
      'ciphertext': 'manifest-ciphertext',
      'mac': 'manifest-mac',
      'updated_at': 1715552222,
    },
    'revision': revision,
    'created_at': '2026-05-13T10:00:00Z',
    'updated_at': '2026-05-13T10:05:00Z',
  });
}

const String _safeEmergencyPackageEnvelope =
    '{"ciphertext":"emergency-ciphertext","nonce":"emergency-nonce","mac":"emergency-mac"}';

const String _safeEmergencyPackageAad =
    '{"schema":"lockly-emergency-package-v1","mac":"emergency-mac","grant_id":"grant-1","recipient_key_fingerprint":"fingerprint-1"}';

const String _safeEmergencyRequestMessageAad =
    '{"schema":"lockly-emergency-request-v1","mac":"message-mac"}';

EmergencyContact _emergencyContact({
  String status = 'active',
  String? revokedAt,
}) {
  return EmergencyContact(
    id: 'contact-1',
    ownerUserId: 'owner-1',
    recipientUserId: 'recipient-1',
    recipientEmail: 'friend@example.test',
    recipientPublicKey: 'recipient-public-key',
    recipientKeyFingerprint: 'fingerprint-1',
    recipientLabel: 'Friend',
    status: status,
    createdAt: '2026-05-24T00:00:00Z',
    updatedAt: '2026-05-24T00:30:00Z',
    revokedAt: revokedAt,
  );
}

EmergencyGrant _emergencyGrant({String status = 'pending_acceptance'}) {
  return EmergencyGrant(
    id: 'grant-1',
    ownerUserId: 'owner-1',
    recipientUserId: 'recipient-1',
    contactId: 'contact-1',
    vaultId: 'vault-1',
    status: status,
    waitingPeriodHours: 24,
    packageAad: _safeEmergencyPackageAad,
    packageFingerprint: 'package-fingerprint-1',
    recipientKeyFingerprint: 'fingerprint-1',
    createdAt: '2026-05-24T00:00:00Z',
    updatedAt: '2026-05-24T00:30:00Z',
  );
}

EmergencyAccessPackage _emergencyAccessPackage() {
  return const EmergencyAccessPackage(
    grantId: 'grant-1',
    ownerUserId: 'owner-1',
    recipientUserId: 'recipient-1',
    contactId: 'contact-1',
    status: 'downloaded',
    encryptedRecoveryPackage: _safeEmergencyPackageEnvelope,
    packageAad: _safeEmergencyPackageAad,
    packageFingerprint: 'package-fingerprint-1',
    recipientKeyFingerprint: 'fingerprint-1',
    downloadedAt: '2026-05-24T01:00:00Z',
  );
}

class _InMemorySyncStateDao implements SyncStateDao {
  String? _deviceId;
  String? _lastPullCursor;
  final Map<String, SyncItemState> _itemStates = {};
  final Map<String, SyncConflictRecord> _conflicts = {};
  String? _lastBlobPullCursor;
  final Map<String, SyncBlobState> _blobStates = {};
  final Map<String, SyncBlobConflictRecord> _blobConflicts = {};

  @override
  Future<String?> deviceId() async => _deviceId;

  @override
  Future<void> setDeviceId(String deviceId) async {
    _deviceId = deviceId;
  }

  @override
  Future<void> clearDeviceId() async {
    _deviceId = null;
  }

  @override
  Future<void> clearAll() async {
    _deviceId = null;
    _lastPullCursor = null;
    _lastBlobPullCursor = null;
    _itemStates.clear();
    _conflicts.clear();
    _blobStates.clear();
    _blobConflicts.clear();
  }

  @override
  Future<String?> lastPullCursor() async => _lastPullCursor;

  @override
  Future<void> setLastPullCursor(String cursor) async {
    _lastPullCursor = cursor;
  }

  @override
  Future<SyncItemState?> itemState(String itemId) async {
    return _itemStates[itemId];
  }

  @override
  Future<void> saveItemState(SyncItemState state) async {
    _itemStates[state.itemId] = state;
  }

  @override
  Future<List<SyncConflictRecord>> conflicts() async {
    return _conflicts.values.toList();
  }

  @override
  Future<void> saveConflict(SyncConflictRecord conflict) async {
    _conflicts[conflict.itemId] = conflict;
  }

  @override
  Future<void> clearConflict(String itemId) async {
    _conflicts.remove(itemId);
  }

  @override
  Future<String?> lastBlobPullCursor() async => _lastBlobPullCursor;

  @override
  Future<void> setLastBlobPullCursor(String cursor) async {
    _lastBlobPullCursor = cursor;
  }

  @override
  Future<SyncBlobState?> blobState(String blobId) async {
    return _blobStates[blobId];
  }

  @override
  Future<void> saveBlobState(SyncBlobState state) async {
    _blobStates[state.blobId] = state;
  }

  @override
  Future<List<SyncBlobConflictRecord>> blobConflicts() async {
    return _blobConflicts.values.toList();
  }

  @override
  Future<void> saveBlobConflict(SyncBlobConflictRecord conflict) async {
    _blobConflicts[conflict.blobId] = conflict;
  }

  @override
  Future<void> clearBlobConflict(String blobId) async {
    _blobConflicts.remove(blobId);
  }
}
