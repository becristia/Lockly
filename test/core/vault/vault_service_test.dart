import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/encoding.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_session.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_manifest_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/data/models/vault_meta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<VaultService> buildService() async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    return VaultService(
      repository: VaultRepository(
        metaDao: VaultMetaDao(db),
        itemsDao: VaultItemsDao(db),
        manifestDao: VaultManifestDao(db),
        settingsDao: SettingsDao(db),
      ),
      random: SecureRandom(),
      kdf: KdfService(),
      crypto: CryptoService(random: SecureRandom()),
    );
  }

  test('creates vault and unlocks with correct password only', () async {
    final service = await buildService();
    await service.createVault(masterPassword: 'master-passphrase');

    final unlocked = await service.unlock(masterPassword: 'master-passphrase');
    expect(unlocked.isUnlocked, isTrue);

    expect(
      () => service.unlock(masterPassword: 'wrong-passphrase'),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test('new vaults use argon2id metadata by default', () async {
    final service = await buildService();

    await service.createVault(masterPassword: 'master-passphrase');

    final meta = await service.repository.metaDao.get();
    expect(meta, isNotNull);
    expect(meta!.kdf, 'argon2id');
    expect(meta.kdfParams.name, 'argon2id');
    expect(meta.kdfParams.memoryKiB, 65536);
    expect(meta.kdfParams.iterations, 3);
    expect(meta.kdfParams.parallelism, 1);
    expect(meta.kdfParams.bits, 256);
  });

  test(
    'item CRUD decrypts to original entry and database excludes plaintext',
    () async {
      final service = await buildService();
      await service.createVault(masterPassword: 'master-passphrase');
      await service.unlock(masterPassword: 'master-passphrase');

      final id = await service.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'private note',
          tags: ['dev'],
        ),
      );

      final entry = await service.getItem(id);
      expect(entry.title, 'GitHub');
      expect(entry.password, 'secret-password');

      final rawRows = await service.repository.itemsDao.rawRowsForTest();
      final rawText = rawRows.toString();
      expect(rawText, isNot(contains('secret-password')));
      expect(rawText, isNot(contains('user@example.com')));
      expect(rawText, isNot(contains('private note')));
    },
  );

  test('master password rotation invalidates old password', () async {
    final service = await buildService();
    await service.createVault(masterPassword: 'old-master');
    await service.unlock(masterPassword: 'old-master');

    await service.changeMasterPassword(
      oldPassword: 'old-master',
      newPassword: 'new-master',
    );

    expect(
      () => service.unlock(masterPassword: 'old-master'),
      throwsA(isA<VaultUnlockException>()),
    );
    expect(
      (await service.unlock(masterPassword: 'new-master')).isUnlocked,
      isTrue,
    );
  });

  test(
    'changing a pbkdf2 vault password migrates metadata to argon2id',
    () async {
      final service = await buildService();
      final now = DateTime.utc(2026, 5, 15).millisecondsSinceEpoch;
      final salt = SecureRandom().bytes(16);
      final dek = SecureRandom().bytes(32);
      final oldParams = KdfParams.pbkdf2(iterations: 120000, bits: 256);
      final oldKek = await KdfService().deriveKey(
        password: 'old-master',
        salt: salt,
        params: oldParams,
      );
      final wrappedDek = await CryptoService(
        random: SecureRandom(),
      ).encryptBytes(key: oldKek, plaintext: dek);

      await service.repository.metaDao.save(
        VaultMeta(
          id: 'legacy-vault',
          version: 1,
          kdf: oldParams.name,
          kdfParams: oldParams,
          salt: b64(salt),
          encryptedDekByMaster: b64(wrappedDek.ciphertext),
          encryptedDekByMasterNonce: b64(wrappedDek.nonce),
          encryptedDekByMasterMac: b64(wrappedDek.mac),
          biometricEnabled: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await service.unlock(masterPassword: 'old-master');
      await service.changeMasterPassword(
        oldPassword: 'old-master',
        newPassword: 'new-master',
      );

      final meta = await service.repository.metaDao.get();
      expect(meta!.kdf, 'argon2id');
      expect(meta.kdfParams.name, 'argon2id');
      expect(
        () => service.unlock(masterPassword: 'old-master'),
        throwsA(isA<VaultUnlockException>()),
      );
      expect(
        (await service.unlock(masterPassword: 'new-master')).isUnlocked,
        isTrue,
      );
    },
  );

  test('locked item operations fail with VaultLockedException', () async {
    final service = await buildService();
    await service.createVault(masterPassword: 'master-passphrase');
    final session = await service.unlock(masterPassword: 'master-passphrase');

    final existingId = await service.createItem(
      PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: 'private note',
        tags: ['dev'],
      ),
    );

    session.lock();

    expect(
      () => service.createItem(
        PasswordEntry(
          title: 'Locked',
          website: 'https://locked.example',
          username: 'locked-user',
          password: 'locked-password',
          notes: 'locked-note',
          tags: ['locked'],
        ),
      ),
      throwsA(isA<VaultLockedException>()),
    );
    expect(
      () => service.getItem(existingId),
      throwsA(isA<VaultLockedException>()),
    );
    expect(() => service.listItems(), throwsA(isA<VaultLockedException>()));
    expect(
      () => service.updateItem(
        existingId,
        PasswordEntry(
          title: 'Updated',
          website: 'https://github.com',
          username: 'updated-user',
          password: 'updated-password',
          notes: 'updated-note',
          tags: ['updated'],
        ),
      ),
      throwsA(isA<VaultLockedException>()),
    );
    expect(
      () => service.deleteItem(existingId),
      throwsA(isA<VaultLockedException>()),
    );
  });

  test(
    'password rotation preserves readability of preexisting items after relock',
    () async {
      final service = await buildService();
      await service.createVault(masterPassword: 'old-master');
      final session = await service.unlock(masterPassword: 'old-master');
      final id = await service.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'private note',
          tags: ['dev'],
        ),
      );

      await service.changeMasterPassword(
        oldPassword: 'old-master',
        newPassword: 'new-master',
      );

      session.lock();
      await service.unlock(masterPassword: 'new-master');

      final entry = await service.getItem(id);
      expect(entry.title, 'GitHub');
      expect(entry.password, 'secret-password');
      expect(entry.notes, 'private note');
    },
  );

  test('stale update and delete throw VaultItemNotFoundException', () async {
    final service = await buildService();
    await service.createVault(masterPassword: 'master-passphrase');
    await service.unlock(masterPassword: 'master-passphrase');

    final id = await service.createItem(
      PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: 'private note',
        tags: ['dev'],
      ),
    );

    await service.deleteItem(id);

    expect(
      () => service.updateItem(
        id,
        PasswordEntry(
          title: 'Updated',
          website: 'https://github.com',
          username: 'updated-user',
          password: 'updated-password',
          notes: 'updated-note',
          tags: ['updated'],
        ),
      ),
      throwsA(isA<VaultItemNotFoundException>()),
    );
    expect(
      () => service.deleteItem(id),
      throwsA(isA<VaultItemNotFoundException>()),
    );
  });

  test(
    'updateItem throws not found when the row is deleted after read and before write',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final itemsDao = _DeleteDuringUpdateVaultItemsDao(db);
      final service = VaultService(
        repository: VaultRepository(
          metaDao: VaultMetaDao(db),
          itemsDao: itemsDao,
          manifestDao: VaultManifestDao(db),
          settingsDao: SettingsDao(db),
        ),
        random: SecureRandom(),
        kdf: KdfService(),
        crypto: CryptoService(random: SecureRandom()),
      );
      await service.createVault(masterPassword: 'master-passphrase');
      await service.unlock(masterPassword: 'master-passphrase');

      final id = await service.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'private note',
          tags: ['dev'],
        ),
      );
      itemsDao.targetId = id;

      await expectLater(
        service.updateItem(
          id,
          PasswordEntry(
            title: 'Updated',
            website: 'https://github.com',
            username: 'updated-user',
            password: 'updated-password',
            notes: 'updated-note',
            tags: ['updated'],
          ),
        ),
        throwsA(isA<VaultItemNotFoundException>()),
      );

      final rawRows = await itemsDao.rawRowsForTest();
      expect(rawRows, hasLength(1));
      expect(rawRows.single['deleted_at'], isNotNull);
    },
  );

  test(
    'list update and delete operate on decrypted active items with in-memory query filtering',
    () async {
      final service = await buildService();
      await service.createVault(masterPassword: 'master-passphrase');
      await service.unlock(masterPassword: 'master-passphrase');

      final githubId = await service.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'private note',
          tags: ['dev'],
        ),
      );
      final bankingId = await service.createItem(
        PasswordEntry(
          title: 'Bank',
          website: 'https://bank.example',
          username: 'cash-user',
          password: 'bank-secret',
          notes: 'monthly bills',
          tags: ['finance'],
        ),
      );

      final byNotes = await service.listItems(query: 'private');
      expect(byNotes.map((item) => item.id), [githubId]);

      await service.updateItem(
        githubId,
        PasswordEntry(
          title: 'GitHub Prod',
          website: 'https://github.com',
          username: 'ops@example.com',
          password: 'rotated-secret',
          notes: 'incident access',
          tags: ['ops'],
        ),
      );

      final updatedEntry = await service.getItem(githubId);
      expect(updatedEntry.title, 'GitHub Prod');
      expect(updatedEntry.password, 'rotated-secret');

      final byTag = await service.listItems(query: 'ops');
      expect(byTag.map((item) => item.id), [githubId]);

      await service.deleteItem(bankingId);

      final remainingItems = await service.listItems();
      expect(remainingItems.map((item) => item.id), [githubId]);
    },
  );
}

class _DeleteDuringUpdateVaultItemsDao extends VaultItemsDao {
  _DeleteDuringUpdateVaultItemsDao(super.db);

  String? targetId;
  bool _deletedDuringUpdate = false;

  @override
  Future<bool> updateActive(EncryptedVaultItem item) async {
    if (!_deletedDuringUpdate && targetId == item.id) {
      _deletedDuringUpdate = true;
      await softDelete(item.id, item.updatedAt + 1);
    }
    return super.updateActive(item);
  }
}
