import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:secure_box/core/biometric/biometric_service.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/vault/vault_anchor.dart';
import 'package:secure_box/core/vault/vault_anchor_service.dart';
import 'package:secure_box/core/vault/vault_anchor_store.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_manifest_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<_Harness> buildHarness({
    String? path,
    MemoryVaultAnchorStore? anchorStore,
    bool autoClose = true,
    VaultRepository Function(Database db)? repositoryBuilder,
  }) async {
    final db = path == null
        ? await AppDatabase.openInMemory()
        : await AppDatabase.open(path);
    if (autoClose) {
      addTearDown(db.close);
    }
    final store = anchorStore ?? MemoryVaultAnchorStore();
    final repository =
        repositoryBuilder?.call(db) ??
        VaultRepository(
          metaDao: VaultMetaDao(db),
          itemsDao: VaultItemsDao(db),
          manifestDao: VaultManifestDao(db),
          settingsDao: SettingsDao(db),
        );
    final service = VaultService(
      repository: repository,
      random: SecureRandom(),
      kdf: KdfService(),
      crypto: CryptoService(random: SecureRandom()),
      anchorService: VaultAnchorService(store: store),
    );
    return _Harness(service: service, anchorStore: store, db: db);
  }

  test('createVault writes anchor for initial manifest', () async {
    final harness = await buildHarness();

    await harness.service.createVault(masterPassword: 'master-passphrase');

    final meta = await harness.service.repository.metaDao.get();
    final anchor = await harness.anchorStore.read(vaultId: meta!.id);
    final manifest = await harness.service.repository.manifestDao.get();
    expect(anchor, isNotNull);
    expect(anchor!.manifestEpoch, manifest!.epoch);
    expect(anchor.manifestCounter, manifest.counter);
  });

  test('master unlock succeeds when anchor matches', () async {
    final harness = await buildHarness();
    await harness.service.createVault(masterPassword: 'master-passphrase');
    harness.service.lock();

    final session = await harness.service.unlock(
      masterPassword: 'master-passphrase',
    );

    expect(session.isUnlocked, isTrue);
  });

  test(
    'master unlock rejects database rollback below anchor counter',
    () async {
      final harness = await buildHarness();
      await harness.service.createVault(masterPassword: 'master-passphrase');
      final meta = await harness.service.repository.metaDao.get();
      final manifest = await harness.service.repository.manifestDao.get();
      await VaultAnchorService(
        store: harness.anchorStore,
      ).writeAcceptedManifest(
        vaultId: meta!.id,
        manifest: manifest!.copyWith(counter: manifest.counter + 1),
        updatedAt: manifest.updatedAt + 1,
      );

      await expectLater(
        harness.service.unlock(masterPassword: 'master-passphrase'),
        throwsA(isA<VaultIntegrityException>()),
      );
      expect(harness.service.isUnlocked, isFalse);
    },
  );

  test(
    'unlocked reads reject database rollback below anchor counter',
    () async {
      final harness = await buildHarness();
      await harness.service.createVault(masterPassword: 'master-passphrase');
      await harness.service.unlock(masterPassword: 'master-passphrase');
      final oldManifest = await harness.service.repository.manifestDao.get();
      await harness.service.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'rollback test',
          tags: const ['dev'],
        ),
      );

      await harness.service.repository.itemsDao.deleteAll();
      await harness.service.repository.manifestDao.save(oldManifest!);

      await expectLater(
        harness.service.listItems(),
        throwsA(isA<VaultIntegrityException>()),
      );
      expect(harness.service.isUnlocked, isFalse);
    },
  );

  test(
    'backup export rejects database rollback below anchor counter',
    () async {
      final harness = await buildHarness();
      await harness.service.createVault(masterPassword: 'master-passphrase');
      await harness.service.unlock(masterPassword: 'master-passphrase');
      final oldManifest = await harness.service.repository.manifestDao.get();
      await harness.service.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'rollback test',
          tags: const ['dev'],
        ),
      );

      await harness.service.repository.itemsDao.deleteAll();
      await harness.service.repository.manifestDao.save(oldManifest!);

      await expectLater(
        harness.service.createVerifiedManifestForBackup(
          items: const [],
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
        throwsA(isA<VaultIntegrityException>()),
      );
      expect(harness.service.isUnlocked, isFalse);
    },
  );

  test(
    'master unlock repairs a missing anchor after manifest verification',
    () async {
      final harness = await buildHarness();
      await harness.service.createVault(masterPassword: 'master-passphrase');
      final meta = await harness.service.repository.metaDao.get();
      await harness.anchorStore.delete(vaultId: meta!.id);
      harness.service.lock();

      final session = await harness.service.unlock(
        masterPassword: 'master-passphrase',
      );

      expect(session.isUnlocked, isTrue);
      expect(await harness.anchorStore.read(vaultId: meta.id), isNotNull);
    },
  );

  test('biometric unlock fails when anchor is missing', () async {
    final harness = await buildHarness();
    final biometric = BiometricService(
      authenticator: FakeBiometricAuthenticator(
        canAuthenticate: true,
        succeeds: true,
      ),
      store: MemorySecureDekStore(),
    );
    await harness.service.createVault(masterPassword: 'master-passphrase');
    await harness.service.enableBiometricUnlock(
      masterPassword: 'master-passphrase',
      biometricService: biometric,
    );
    final meta = await harness.service.repository.metaDao.get();
    await harness.anchorStore.delete(vaultId: meta!.id);
    harness.service.lock();

    await expectLater(
      harness.service.unlockWithBiometrics(biometricService: biometric),
      throwsA(isA<VaultIntegrityException>()),
    );

    expect(harness.service.isUnlocked, isFalse);
    expect(await harness.anchorStore.read(vaultId: meta.id), isNull);
  });

  test('item mutations update anchor counter after manifest rewrite', () async {
    final harness = await buildHarness();
    await harness.service.createVault(masterPassword: 'master-passphrase');
    await harness.service.unlock(masterPassword: 'master-passphrase');
    final meta = await harness.service.repository.metaDao.get();

    final id = await harness.service.createItem(_entry('One'));
    final afterCreate = await harness.anchorStore.read(vaultId: meta!.id);
    final manifestAfterCreate = await harness.service.repository.manifestDao
        .get();
    expect(afterCreate!.manifestCounter, manifestAfterCreate!.counter);

    await harness.service.updateItem(id, _entry('Two'));
    final afterUpdate = await harness.anchorStore.read(vaultId: meta.id);
    final manifestAfterUpdate = await harness.service.repository.manifestDao
        .get();
    expect(afterUpdate!.manifestCounter, manifestAfterUpdate!.counter);

    await harness.service.deleteItem(id);
    final afterDelete = await harness.anchorStore.read(vaultId: meta.id);
    final manifestAfterDelete = await harness.service.repository.manifestDao
        .get();
    expect(afterDelete!.manifestCounter, manifestAfterDelete!.counter);
  });

  test('item mutation rejects rollback before writing new data', () async {
    final harness = await buildHarness();
    await harness.service.createVault(masterPassword: 'master-passphrase');
    await harness.service.unlock(masterPassword: 'master-passphrase');
    final meta = await harness.service.repository.metaDao.get();
    final manifest = await harness.service.repository.manifestDao.get();
    await VaultAnchorService(store: harness.anchorStore).writeAcceptedManifest(
      vaultId: meta!.id,
      manifest: manifest!.copyWith(counter: manifest.counter + 2),
      updatedAt: manifest.updatedAt + 2,
    );

    await expectLater(
      harness.service.createItem(_entry('Blocked')),
      throwsA(isA<VaultIntegrityException>()),
    );
    expect(await harness.service.repository.itemsDao.rawRowsForTest(), isEmpty);
    expect(harness.service.isUnlocked, isFalse);
  });

  test(
    'item mutation rollback after manifest rewrite does not advance anchor',
    () async {
      final harness = await buildHarness();
      await harness.service.createVault(masterPassword: 'master-passphrase');
      await harness.service.unlock(masterPassword: 'master-passphrase');
      final meta = await harness.service.repository.metaDao.get();
      final before = await harness.anchorStore.read(vaultId: meta!.id);

      final rollbackService = VaultService(
        repository: _RollbackAfterTransactionActionRepository(harness.db),
        random: SecureRandom(),
        kdf: KdfService(),
        crypto: CryptoService(random: SecureRandom()),
        anchorService: VaultAnchorService(store: harness.anchorStore),
      );
      await rollbackService.unlock(masterPassword: 'master-passphrase');

      await expectLater(
        rollbackService.createItem(_entry('Rolled back')),
        throwsA(isA<_RollbackAfterTransactionAction>()),
      );

      expect(
        await rollbackService.repository.itemsDao.rawRowsForTest(),
        isEmpty,
      );
      final after = await harness.anchorStore.read(vaultId: meta.id);
      expect(after!.manifestCounter, before!.manifestCounter);
      expect(after.manifestDigest, before.manifestDigest);
    },
  );

  test(
    'item mutation locks when anchor write fails after database commit',
    () async {
      final anchorStore = _FailingAnchorWriteStore();
      final harness = await buildHarness(anchorStore: anchorStore);
      await harness.service.createVault(masterPassword: 'master-passphrase');
      await harness.service.unlock(masterPassword: 'master-passphrase');
      final meta = await harness.service.repository.metaDao.get();
      final before = await harness.anchorStore.read(vaultId: meta!.id);
      anchorStore.failNextAcceptedWrite = true;

      await expectLater(
        harness.service.createItem(_entry('Anchor failure')),
        throwsA(isA<VaultIntegrityException>()),
      );

      expect(harness.service.isUnlocked, isFalse);
      final after = await harness.anchorStore.read(vaultId: meta.id);
      expect(after!.manifestCounter, before!.manifestCounter);
      final manifest = await harness.service.repository.manifestDao.get();
      expect(manifest!.counter, greaterThan(after.manifestCounter));
    },
  );

  test(
    'item mutation rolls back database when pending anchor write fails',
    () async {
      final anchorStore = _FailingAnchorWriteStore();
      final harness = await buildHarness(anchorStore: anchorStore);
      await harness.service.createVault(masterPassword: 'master-passphrase');
      await harness.service.unlock(masterPassword: 'master-passphrase');
      final meta = await harness.service.repository.metaDao.get();
      final beforeAnchor = await harness.anchorStore.read(vaultId: meta!.id);
      final beforeManifest = await harness.service.repository.manifestDao.get();
      anchorStore.failNextWrite = true;

      await expectLater(
        harness.service.createItem(_entry('Pending anchor failure')),
        throwsA(isA<VaultIntegrityException>()),
      );

      expect(harness.service.isUnlocked, isFalse);
      expect(
        await harness.service.repository.itemsDao.rawRowsForTest(),
        isEmpty,
      );
      final afterManifest = await harness.service.repository.manifestDao.get();
      expect(afterManifest!.counter, beforeManifest!.counter);
      final afterAnchor = await harness.anchorStore.read(vaultId: meta.id);
      expect(afterAnchor!.manifestCounter, beforeAnchor!.manifestCounter);

      final session = await harness.service.unlock(
        masterPassword: 'master-passphrase',
      );
      expect(session.isUnlocked, isTrue);
    },
  );

  test(
    'master unlock repairs verified pending manifest after anchor write failure',
    () async {
      final anchorStore = _FailingAnchorWriteStore();
      final harness = await buildHarness(anchorStore: anchorStore);
      await harness.service.createVault(masterPassword: 'master-passphrase');
      await harness.service.unlock(masterPassword: 'master-passphrase');
      final meta = await harness.service.repository.metaDao.get();
      final before = await harness.anchorStore.read(vaultId: meta!.id);
      anchorStore.failNextAcceptedWrite = true;

      await expectLater(
        harness.service.createItem(_entry('Anchor failure')),
        throwsA(isA<VaultIntegrityException>()),
      );
      expect(harness.service.isUnlocked, isFalse);

      await harness.service.unlock(masterPassword: 'master-passphrase');

      expect(harness.service.isUnlocked, isTrue);
      final after = await harness.anchorStore.read(vaultId: meta.id);
      final manifest = await harness.service.repository.manifestDao.get();
      expect(after!.manifestCounter, greaterThan(before!.manifestCounter));
      expect(after.manifestCounter, manifest!.counter);
    },
  );

  test(
    'biometric unlock repairs verified pending manifest after anchor write failure',
    () async {
      final anchorStore = _FailingAnchorWriteStore();
      final harness = await buildHarness(anchorStore: anchorStore);
      final biometric = BiometricService(
        authenticator: FakeBiometricAuthenticator(
          canAuthenticate: true,
          succeeds: true,
        ),
        store: MemorySecureDekStore(),
      );
      await harness.service.createVault(masterPassword: 'master-passphrase');
      await harness.service.enableBiometricUnlock(
        masterPassword: 'master-passphrase',
        biometricService: biometric,
      );
      await harness.service.unlock(masterPassword: 'master-passphrase');
      final meta = await harness.service.repository.metaDao.get();
      final before = await harness.anchorStore.read(vaultId: meta!.id);
      anchorStore.failNextAcceptedWrite = true;

      await expectLater(
        harness.service.createItem(_entry('Anchor failure')),
        throwsA(isA<VaultIntegrityException>()),
      );
      expect(harness.service.isUnlocked, isFalse);

      final unlocked = await harness.service.unlockWithBiometrics(
        biometricService: biometric,
      );

      expect(unlocked, isTrue);
      expect(harness.service.isUnlocked, isTrue);
      final after = await harness.anchorStore.read(vaultId: meta.id);
      final manifest = await harness.service.repository.manifestDao.get();
      expect(after!.manifestCounter, greaterThan(before!.manifestCounter));
      expect(after.manifestCounter, manifest!.counter);
    },
  );

  test('master unlock rejects database advanced beyond stale anchor', () async {
    final harness = await buildHarness();
    await harness.service.createVault(masterPassword: 'master-passphrase');
    await harness.service.unlock(masterPassword: 'master-passphrase');
    final meta = await harness.service.repository.metaDao.get();
    final initialManifest = await harness.service.repository.manifestDao.get();

    await harness.service.createItem(_entry('Advanced'));
    await VaultAnchorService(store: harness.anchorStore).writeAcceptedManifest(
      vaultId: meta!.id,
      manifest: initialManifest!,
      updatedAt: initialManifest.updatedAt,
    );
    harness.service.lock();

    await expectLater(
      harness.service.unlock(masterPassword: 'master-passphrase'),
      throwsA(isA<VaultIntegrityException>()),
    );
    expect(harness.service.isUnlocked, isFalse);
  });

  test('master unlock rejects forged SQLite pending anchor marker', () async {
    final harness = await buildHarness();
    await harness.service.createVault(masterPassword: 'master-passphrase');
    await harness.service.unlock(masterPassword: 'master-passphrase');
    final meta = await harness.service.repository.metaDao.get();
    final initialManifest = await harness.service.repository.manifestDao.get();

    await harness.service.createItem(_entry('Forged pending marker'));
    final advancedManifest = await harness.service.repository.manifestDao.get();
    final anchorService = VaultAnchorService(store: harness.anchorStore);
    await anchorService.writeAcceptedManifest(
      vaultId: meta!.id,
      manifest: initialManifest!,
      updatedAt: initialManifest.updatedAt,
    );
    await harness.service.repository.settingsDao.setValue(
      '_lockly_pending_anchor_v1',
      jsonEncode({
        'vault_id': meta.id,
        'epoch': advancedManifest!.epoch,
        'counter': advancedManifest.counter,
        'digest': await anchorService.digestManifest(advancedManifest),
      }),
    );
    harness.service.lock();

    await expectLater(
      harness.service.unlock(masterPassword: 'master-passphrase'),
      throwsA(isA<VaultIntegrityException>()),
    );
    expect(harness.service.isUnlocked, isFalse);
  });

  test('master unlock rejects restored older SQLite database file', () async {
    final dir = await Directory.systemTemp.createTemp(
      'secure_box_rollback_anchor_',
    );
    addTearDown(() => dir.delete(recursive: true));
    final dbPath = p.join(dir.path, 'vault.db');
    final snapshotPath = p.join(dir.path, 'vault.snapshot.db');
    final anchorStore = MemoryVaultAnchorStore();

    var harness = await buildHarness(
      path: dbPath,
      anchorStore: anchorStore,
      autoClose: false,
    );
    await harness.service.createVault(masterPassword: 'master-passphrase');
    await harness.db.close();
    await _copyClosedDatabaseFile(from: dbPath, to: snapshotPath);

    harness = await buildHarness(
      path: dbPath,
      anchorStore: anchorStore,
      autoClose: false,
    );
    await harness.service.unlock(masterPassword: 'master-passphrase');
    await harness.service.createItem(_entry('After snapshot'));
    await harness.db.close();

    await _copyClosedDatabaseFile(from: snapshotPath, to: dbPath);
    final rolledBack = await buildHarness(
      path: dbPath,
      anchorStore: anchorStore,
      autoClose: false,
    );
    addTearDown(rolledBack.db.close);

    await expectLater(
      rolledBack.service.unlock(masterPassword: 'master-passphrase'),
      throwsA(isA<VaultIntegrityException>()),
    );
    expect(rolledBack.service.isUnlocked, isFalse);
  });

  test('clearLocalVault deletes anchor state', () async {
    final harness = await buildHarness();
    await harness.service.createVault(masterPassword: 'master-passphrase');
    final meta = await harness.service.repository.metaDao.get();
    expect(await harness.anchorStore.read(vaultId: meta!.id), isNotNull);

    await harness.service.clearLocalVault();

    expect(await harness.anchorStore.read(vaultId: meta.id), isNull);
  });

  test('biometric metadata rewrites update anchor counter', () async {
    final harness = await buildHarness();
    final biometric = BiometricService(
      authenticator: FakeBiometricAuthenticator(
        canAuthenticate: true,
        succeeds: true,
      ),
      store: MemorySecureDekStore(),
    );
    await harness.service.createVault(masterPassword: 'master-passphrase');
    final meta = await harness.service.repository.metaDao.get();

    await harness.service.enableBiometricUnlock(
      masterPassword: 'master-passphrase',
      biometricService: biometric,
    );
    final afterEnable = await harness.anchorStore.read(vaultId: meta!.id);
    final manifestAfterEnable = await harness.service.repository.manifestDao
        .get();
    expect(afterEnable!.manifestCounter, manifestAfterEnable!.counter);

    await harness.service.disableBiometricUnlock(biometricService: biometric);
    final afterDisable = await harness.anchorStore.read(vaultId: meta.id);
    final manifestAfterDisable = await harness.service.repository.manifestDao
        .get();
    expect(afterDisable!.manifestCounter, manifestAfterDisable!.counter);
  });

  test(
    'biometric metadata commit serializes concurrent item mutation through anchor write',
    () async {
      final anchorStore = _BlockingAnchorWriteStore(blockOnWriteNumber: 5);
      late _SignalingTransactionRepository signalingRepository;
      final harness = await buildHarness(
        anchorStore: anchorStore,
        repositoryBuilder: (db) {
          signalingRepository = _SignalingTransactionRepository(
            db,
            signalOnTransactionNumber: 3,
          );
          return signalingRepository;
        },
      );
      final biometric = BiometricService(
        authenticator: FakeBiometricAuthenticator(
          canAuthenticate: true,
          succeeds: true,
        ),
        store: MemorySecureDekStore(),
      );
      await harness.service.createVault(masterPassword: 'master-passphrase');
      await harness.service.unlock(masterPassword: 'master-passphrase');

      final enableFuture = harness.service.enableBiometricUnlock(
        masterPassword: 'master-passphrase',
        biometricService: biometric,
      );
      await anchorStore.waitUntilBlocked();

      final createResult = harness.service
          .createItem(_entry('During biometric enable'))
          .then<Object?>(
            (_) => 'created',
            onError: (error, stackTrace) => error,
          );
      final startedBeforeAnchorWriteFinished = await signalingRepository
          .targetTransactionStarted
          .then((_) => true)
          .timeout(const Duration(milliseconds: 200), onTimeout: () => false);
      anchorStore.release();

      await expectLater(enableFuture, completes);
      expect(startedBeforeAnchorWriteFinished, isFalse);
      expect(await createResult, 'created');
      expect(harness.service.isUnlocked, isTrue);
    },
  );

  test('master password rotation rewrites update anchor counter', () async {
    final harness = await buildHarness();
    await harness.service.createVault(masterPassword: 'master-passphrase');
    final meta = await harness.service.repository.metaDao.get();

    await harness.service.changeMasterPassword(
      oldPassword: 'master-passphrase',
      newPassword: 'new-master-passphrase',
      biometricService: _memoryBiometricService(),
    );

    final anchor = await harness.anchorStore.read(vaultId: meta!.id);
    final manifest = await harness.service.repository.manifestDao.get();
    expect(anchor!.manifestCounter, manifest!.counter);
  });

  test(
    'enable biometric fails before writing store when anchor is rolled back',
    () async {
      final harness = await buildHarness();
      final store = _CountingSecureDekStore();
      final biometric = BiometricService(
        authenticator: FakeBiometricAuthenticator(
          canAuthenticate: true,
          succeeds: true,
        ),
        store: store,
      );
      await harness.service.createVault(masterPassword: 'master-passphrase');
      await _advanceAnchorPastCurrentManifest(harness);

      await expectLater(
        harness.service.enableBiometricUnlock(
          masterPassword: 'master-passphrase',
          biometricService: biometric,
        ),
        throwsA(isA<VaultIntegrityException>()),
      );

      expect(store.writeCount, 0);
      expect(await store.readDek(), isNull);
    },
  );

  test(
    'master password change fails before biometric delete on rolled back anchor',
    () async {
      final harness = await buildHarness();
      final store = _CountingSecureDekStore();
      final biometric = BiometricService(
        authenticator: FakeBiometricAuthenticator(
          canAuthenticate: true,
          succeeds: true,
        ),
        store: store,
      );
      await harness.service.createVault(masterPassword: 'master-passphrase');
      await harness.service.enableBiometricUnlock(
        masterPassword: 'master-passphrase',
        biometricService: biometric,
      );
      await _advanceAnchorPastCurrentManifest(harness);

      await expectLater(
        harness.service.changeMasterPassword(
          oldPassword: 'master-passphrase',
          newPassword: 'new-master-passphrase',
          biometricService: biometric,
          beforePersist: biometric.disable,
        ),
        throwsA(isA<VaultIntegrityException>()),
      );

      expect(store.deleteCount, 0);
      expect(await store.readDek(), isNotNull);
    },
  );
}

BiometricService _memoryBiometricService() {
  return BiometricService(
    authenticator: FakeBiometricAuthenticator(
      canAuthenticate: true,
      succeeds: true,
    ),
    store: MemorySecureDekStore(),
  );
}

class _Harness {
  _Harness({
    required this.service,
    required this.anchorStore,
    required this.db,
  });

  final VaultService service;
  final MemoryVaultAnchorStore anchorStore;
  final Database db;
}

class _RollbackAfterTransactionAction implements Exception {
  const _RollbackAfterTransactionAction();
}

class _RollbackAfterTransactionActionRepository extends VaultRepository {
  _RollbackAfterTransactionActionRepository(Database db)
    : _db = db,
      super(
        metaDao: VaultMetaDao(db),
        itemsDao: VaultItemsDao(db),
        manifestDao: VaultManifestDao(db),
        settingsDao: SettingsDao(db),
      );

  final Database _db;

  @override
  Future<T> transaction<T>(
    Future<T> Function(VaultRepository repository) action,
  ) async {
    return _db.transaction((txn) async {
      await action(
        VaultRepository(
          metaDao: VaultMetaDao(txn),
          itemsDao: VaultItemsDao(txn),
          manifestDao: VaultManifestDao(txn),
          settingsDao: SettingsDao(txn),
        ),
      );
      throw const _RollbackAfterTransactionAction();
    });
  }
}

class _SignalingTransactionRepository extends VaultRepository {
  _SignalingTransactionRepository(
    Database db, {
    required this.signalOnTransactionNumber,
  }) : _db = db,
       super(
         metaDao: VaultMetaDao(db),
         itemsDao: VaultItemsDao(db),
         manifestDao: VaultManifestDao(db),
         settingsDao: SettingsDao(db),
       );

  final Database _db;
  final int signalOnTransactionNumber;
  var _transactionCount = 0;
  final _targetTransactionStarted = Completer<void>();

  Future<void> get targetTransactionStarted => _targetTransactionStarted.future;

  @override
  Future<T> transaction<T>(
    Future<T> Function(VaultRepository repository) action,
  ) async {
    _transactionCount += 1;
    if (_transactionCount == signalOnTransactionNumber &&
        !_targetTransactionStarted.isCompleted) {
      _targetTransactionStarted.complete();
    }
    return _db.transaction((txn) async {
      return action(
        VaultRepository(
          metaDao: VaultMetaDao(txn),
          itemsDao: VaultItemsDao(txn),
          manifestDao: VaultManifestDao(txn),
          settingsDao: SettingsDao(txn),
        ),
      );
    });
  }
}

class _FailingAnchorWriteStore extends MemoryVaultAnchorStore {
  var failNextWrite = false;
  var failNextAcceptedWrite = false;

  @override
  Future<void> write(VaultAnchor anchor) {
    final failAccepted =
        failNextAcceptedWrite && !anchor.vaultId.endsWith(':pending');
    if (failNextWrite || failAccepted) {
      failNextWrite = false;
      failNextAcceptedWrite = false;
      throw const VaultAnchorException();
    }
    return super.write(anchor);
  }
}

class _BlockingAnchorWriteStore extends MemoryVaultAnchorStore {
  _BlockingAnchorWriteStore({required this.blockOnWriteNumber});

  final int blockOnWriteNumber;
  var _writeCount = 0;
  final _blocked = Completer<void>();
  final _release = Completer<void>();

  Future<void> waitUntilBlocked() => _blocked.future;

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  Future<void> write(VaultAnchor anchor) async {
    _writeCount += 1;
    if (_writeCount == blockOnWriteNumber) {
      _blocked.complete();
      await _release.future;
    }
    return super.write(anchor);
  }
}

PasswordEntry _entry(String title) {
  return PasswordEntry(
    title: title,
    website: 'https://example.test',
    username: 'user@example.test',
    password: 'secret-password',
    notes: 'private note',
    tags: const ['tag'],
  );
}

Future<void> _advanceAnchorPastCurrentManifest(_Harness harness) async {
  final meta = await harness.service.repository.metaDao.get();
  final manifest = await harness.service.repository.manifestDao.get();
  await VaultAnchorService(store: harness.anchorStore).writeAcceptedManifest(
    vaultId: meta!.id,
    manifest: manifest!.copyWith(counter: manifest.counter + 2),
    updatedAt: manifest.updatedAt + 2,
  );
}

Future<void> _copyClosedDatabaseFile({
  required String from,
  required String to,
}) async {
  await _deleteIfExists(to);
  await _deleteIfExists('$to-wal');
  await _deleteIfExists('$to-shm');
  await File(from).copy(to);
}

Future<void> _deleteIfExists(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

class _CountingSecureDekStore implements SecureDekStore {
  Uint8List? _dek;
  var writeCount = 0;
  var deleteCount = 0;

  @override
  SecureDekReadRequirement get readRequirement =>
      SecureDekReadRequirement.explicitBiometricAuthentication;

  @override
  Future<bool> canUseBiometricProtection() async => true;

  @override
  Future<void> writeDek(Uint8List dek) async {
    writeCount += 1;
    _dek = Uint8List.fromList(dek);
  }

  @override
  Future<Uint8List?> readDek() async {
    final dek = _dek;
    return dek == null ? null : Uint8List.fromList(dek);
  }

  @override
  Future<void> deleteDek() async {
    deleteCount += 1;
    _dek = null;
  }
}
