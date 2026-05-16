import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
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

  Future<_Harness> buildHarness() async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final anchorStore = MemoryVaultAnchorStore();
    final service = VaultService(
      repository: VaultRepository(
        metaDao: VaultMetaDao(db),
        itemsDao: VaultItemsDao(db),
        manifestDao: VaultManifestDao(db),
        settingsDao: SettingsDao(db),
      ),
      random: SecureRandom(),
      kdf: KdfService(),
      crypto: CryptoService(random: SecureRandom()),
      anchorService: VaultAnchorService(store: anchorStore),
    );
    return _Harness(service: service, anchorStore: anchorStore);
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
    'master unlock recreates missing anchor after manifest verification',
    () async {
      final harness = await buildHarness();
      await harness.service.createVault(masterPassword: 'master-passphrase');
      final meta = await harness.service.repository.metaDao.get();
      await harness.anchorStore.delete(vaultId: meta!.id);
      harness.service.lock();

      await harness.service.unlock(masterPassword: 'master-passphrase');

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

    final unlocked = await harness.service.unlockWithBiometrics(
      biometricService: biometric,
    );

    expect(unlocked, isFalse);
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

  test('master password rotation rewrites update anchor counter', () async {
    final harness = await buildHarness();
    await harness.service.createVault(masterPassword: 'master-passphrase');
    final meta = await harness.service.repository.metaDao.get();

    await harness.service.changeMasterPassword(
      oldPassword: 'master-passphrase',
      newPassword: 'new-master-passphrase',
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
          beforePersist: biometric.disable,
        ),
        throwsA(isA<VaultIntegrityException>()),
      );

      expect(store.deleteCount, 0);
      expect(await store.readDek(), isNotNull);
    },
  );
}

class _Harness {
  _Harness({required this.service, required this.anchorStore});

  final VaultService service;
  final MemoryVaultAnchorStore anchorStore;
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
