import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/backup/backup_service.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/sync/sync_api_client.dart';
import 'package:secure_box/core/sync/sync_credential_store.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/core/sync/sync_service.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/password_history_dao.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/sync_state_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_manifest_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('cloud sync verifies local integrity before backend upload', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final repository = VaultRepository(
      metaDao: VaultMetaDao(db),
      itemsDao: VaultItemsDao(db),
      manifestDao: VaultManifestDao(db),
      settingsDao: SettingsDao(db),
      historyDao: PasswordHistoryDao(db),
    );
    final random = SecureRandom();
    final vaultService = VaultService(
      repository: repository,
      random: random,
      kdf: KdfService(),
      crypto: CryptoService(random: random),
    );
    await vaultService.createVault(masterPassword: 'master-passphrase');
    await vaultService.unlock(masterPassword: 'master-passphrase');
    await vaultService.createItem(
      PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: 'private note',
        tags: const ['dev'],
      ),
    );

    final api = _RecordingSyncApiClient();
    final credentialStore = SyncCredentialStore(_MemorySyncSecureStorage());
    await credentialStore.saveTokens(
      const SyncAuthTokens(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
      ),
    );
    await credentialStore.saveDeviceId('device-local');
    final services = AppServices(
      hasVault: true,
      vaultService: vaultService,
      backupService: BackupService(
        repository: repository,
        vaultService: vaultService,
      ),
      syncService: SyncService(
        api: api,
        credentials: credentialStore,
        syncState: SyncStateDao(db),
      ),
      initialShellState: AppShellState.unlocked,
      trackActivity: false,
    );
    addTearDown(services.dispose);

    final manifest = await repository.manifestDao.get();
    await repository.manifestDao.save(
      manifest!.copyWith(mac: '${manifest.mac}x'),
    );

    await expectLater(
      services.syncEncryptedVaultNow(masterPassword: 'master-passphrase'),
      throwsA(isA<VaultIntegrityException>()),
    );

    expect(api.calls, isEmpty);
    expect(vaultService.isUnlocked, isFalse);
    expect(services.shellState.value, AppShellState.locked);
  });

  test(
    'cloud sync downloads remote additions before local push and final merge',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final repository = VaultRepository(
        metaDao: VaultMetaDao(db),
        itemsDao: VaultItemsDao(db),
        manifestDao: VaultManifestDao(db),
        settingsDao: SettingsDao(db),
        historyDao: PasswordHistoryDao(db),
      );
      final random = SecureRandom();
      final vaultService = VaultService(
        repository: repository,
        random: random,
        kdf: KdfService(),
        crypto: CryptoService(random: random),
      );
      await vaultService.createVault(masterPassword: 'master-passphrase');
      await vaultService.unlock(masterPassword: 'master-passphrase');
      final itemId = await vaultService.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'private note',
          tags: const ['dev'],
        ),
      );

      final api = _RecordingSyncApiClient()
        ..vaultMeta = _syncVaultMeta()
        ..pullResponse = SyncPullResponse(
          serverTime: '2026-05-23T03:00:00Z',
          items: [
            SyncItem(
              id: 'remote-item',
              payload: SyncItemPayload.fromJson({
                'ciphertext': 'remote-ciphertext',
                'nonce': 'remote-nonce',
                'aad': '{"mac":"remote-mac","schema":"lockly-item-v1"}',
                'revision': 9,
                'deleted': false,
                'client_updated_at': '2026-05-23T00:00:00.000Z',
                'server_updated_at': '2026-05-23T03:00:00Z',
              }),
            ),
          ],
        );
      final credentialStore = SyncCredentialStore(_MemorySyncSecureStorage());
      await credentialStore.saveTokens(
        const SyncAuthTokens(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          tokenType: 'bearer',
        ),
      );
      await credentialStore.saveDeviceId('device-local');
      final services = AppServices(
        hasVault: true,
        vaultService: vaultService,
        backupService: BackupService(
          repository: repository,
          vaultService: vaultService,
        ),
        syncService: SyncService(
          api: api,
          credentials: credentialStore,
          syncState: SyncStateDao(db),
        ),
        importBackupOverride: (backupJson, masterPassword) async => 0,
        initialShellState: AppShellState.unlocked,
        trackActivity: false,
      );
      addTearDown(services.dispose);

      await services.syncEncryptedVaultNow(masterPassword: 'master-passphrase');

      expect(await repository.itemsDao.byId(itemId), isNotNull);
      expect((await repository.itemsDao.byId(itemId))!.deletedAt, isNull);
      expect(
        api.pushedItems
            .singleWhere((item) => item.id == itemId)
            .payload
            .deleted,
        isFalse,
      );
      expect(api.calls, [
        'getVaultMeta',
        'pull',
        'pullBlobs',
        'getVaultMeta',
        'push',
        'getVaultMeta',
        'updateVaultMeta',
        'getVaultMeta',
        'pull',
        'pullBlobs',
      ]);
      expect(await SyncStateDao(db).lastPullCursor(), '2026-05-23T03:00:00Z');
    },
  );

  test(
    'cloud download clears only conflicts for pulled items after successful commit',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final repository = VaultRepository(
        metaDao: VaultMetaDao(db),
        itemsDao: VaultItemsDao(db),
        manifestDao: VaultManifestDao(db),
        settingsDao: SettingsDao(db),
        historyDao: PasswordHistoryDao(db),
      );
      final random = SecureRandom();
      final vaultService = VaultService(
        repository: repository,
        random: random,
        kdf: KdfService(),
        crypto: CryptoService(random: random),
      );
      await vaultService.createVault(masterPassword: 'master-passphrase');
      await vaultService.unlock(masterPassword: 'master-passphrase');

      final syncState = SyncStateDao(db);
      await syncState.saveConflict(
        const SyncConflictRecord(
          itemId: 'item-pulled',
          clientRevision: 1,
          serverRevision: 2,
          remotePayload: '{}',
          createdAt: 1770000000000,
        ),
      );
      await syncState.saveConflict(
        const SyncConflictRecord(
          itemId: 'item-untouched',
          clientRevision: 3,
          serverRevision: 4,
          remotePayload: '{}',
          createdAt: 1770000001000,
        ),
      );
      await syncState.setLastPullCursor('2026-05-23T02:00:00Z');

      final api = _RecordingSyncApiClient()
        ..vaultMeta = _syncVaultMeta()
        ..pullResponse = SyncPullResponse(
          serverTime: '2026-05-23T03:00:00Z',
          items: [
            SyncItem(
              id: 'item-pulled',
              payload: SyncItemPayload.fromJson({
                'ciphertext': 'remote-ciphertext',
                'nonce': 'remote-nonce',
                'aad': '{"mac":"remote-mac","schema":"lockly-item-v1"}',
                'revision': 9,
                'deleted': false,
                'client_updated_at': '2026-05-23T00:00:00.000Z',
                'server_updated_at': '2026-05-23T03:00:00Z',
              }),
            ),
          ],
        );
      final credentialStore = SyncCredentialStore(_MemorySyncSecureStorage());
      await credentialStore.saveTokens(
        const SyncAuthTokens(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          tokenType: 'bearer',
        ),
      );
      await credentialStore.saveDeviceId('device-local');
      final services = AppServices(
        hasVault: true,
        vaultService: vaultService,
        backupService: BackupService(
          repository: repository,
          vaultService: vaultService,
        ),
        syncService: SyncService(
          api: api,
          credentials: credentialStore,
          syncState: syncState,
        ),
        importBackupOverride: (backupJson, masterPassword) async => 1,
        initialShellState: AppShellState.unlocked,
        trackActivity: false,
      );
      addTearDown(services.dispose);

      await services.downloadCloudEncryptedVault(
        masterPassword: 'master-passphrase',
        mode: BackupImportMode.merge,
      );

      expect(await syncState.lastPullCursor(), '2026-05-23T03:00:00Z');
      expect((await syncState.conflicts()).map((conflict) => conflict.itemId), [
        'item-untouched',
      ]);
    },
  );
}

class _RecordingSyncApiClient extends SyncApiClient {
  _RecordingSyncApiClient()
    : super(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: (_) async => SyncHttpResponse(500, const {}),
      );

  final List<String> calls = [];
  SyncVaultMetaPayload? vaultMeta;
  SyncPullResponse pullResponse = const SyncPullResponse(
    serverTime: '2026-05-23T00:00:00Z',
    items: [],
  );
  SyncBlobPullResponse blobPullResponse = const SyncBlobPullResponse(
    serverTime: '2026-05-23T00:00:00Z',
    blobs: [],
  );
  final List<SyncItem> pushedItems = [];
  final List<SyncBlob> pushedBlobs = [];

  @override
  Future<SyncVaultMetaPayload> getVaultMeta({
    required String accessToken,
    required String deviceId,
  }) async {
    calls.add('getVaultMeta');
    final meta = vaultMeta;
    if (meta == null) {
      throw StateError('unexpected backend call');
    }
    return meta;
  }

  @override
  Future<SyncVaultMetaPayload> initVault({
    required String accessToken,
    required SyncVaultMetaPayload meta,
  }) async {
    calls.add('initVault');
    vaultMeta = _backendVaultMetaFromUpload(meta);
    return vaultMeta!;
  }

  @override
  Future<SyncVaultMetaPayload> updateVaultMeta({
    required String accessToken,
    required String deviceId,
    required SyncVaultMetaPayload meta,
  }) async {
    calls.add('updateVaultMeta');
    vaultMeta = _backendVaultMetaFromUpload(meta);
    return vaultMeta!;
  }

  @override
  Future<SyncPushResponse> push({
    required String accessToken,
    required String deviceId,
    required List<SyncItem> items,
  }) async {
    calls.add('push');
    pushedItems.addAll(items);
    return const SyncPushResponse(applied: [], conflicts: []);
  }

  @override
  Future<SyncBlobPushResponse> pushBlobs({
    required String accessToken,
    required String deviceId,
    required List<SyncBlob> blobs,
  }) async {
    calls.add('pushBlobs');
    pushedBlobs.addAll(blobs);
    return const SyncBlobPushResponse(applied: [], conflicts: []);
  }

  @override
  Future<SyncVaultPushResponse> pushVault({
    required String accessToken,
    required String deviceId,
    required List<SyncItem> items,
    required List<SyncBlob> blobs,
  }) async {
    calls.add('pushVault');
    pushedItems.addAll(items);
    pushedBlobs.addAll(blobs);
    return const SyncVaultPushResponse(
      items: SyncPushResponse(applied: [], conflicts: []),
      blobs: SyncBlobPushResponse(applied: [], conflicts: []),
    );
  }

  @override
  Future<SyncPullResponse> pull({
    required String accessToken,
    required String since,
    required String deviceId,
  }) async {
    calls.add('pull');
    return pullResponse;
  }

  @override
  Future<SyncBlobPullResponse> pullBlobs({
    required String accessToken,
    required String since,
    required String deviceId,
  }) async {
    calls.add('pullBlobs');
    return blobPullResponse;
  }
}

SyncVaultMetaPayload _syncVaultMeta() {
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
    'encrypted_dek_by_master':
        '{"ciphertext":"dek-ciphertext","nonce":"dek-nonce","mac":"dek-mac"}',
    'manifest': {
      'version': 1,
      'epoch': 1,
      'counter': 5,
      'nonce': 'manifest-nonce',
      'ciphertext': 'manifest-ciphertext',
      'mac': 'manifest-mac',
      'updated_at': 1715552222,
    },
    'revision': 2,
    'created_at': '2026-05-13T10:00:00Z',
    'updated_at': '2026-05-13T10:05:00Z',
  });
}

SyncVaultMetaPayload _backendVaultMetaFromUpload(SyncVaultMetaPayload meta) {
  return SyncVaultMetaPayload.fromJson({
    ...meta.toJson(),
    'id': meta.id ?? 'vault-1',
    'revision': meta.revision,
    'created_at': meta.createdAt ?? '2026-05-13T10:00:00Z',
    'updated_at': '2026-05-23T00:00:00Z',
  });
}

class _MemorySyncSecureStorage implements SyncSecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }
}
