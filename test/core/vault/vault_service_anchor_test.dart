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
}

class _Harness {
  _Harness({required this.service, required this.anchorStore});

  final VaultService service;
  final MemoryVaultAnchorStore anchorStore;
}
