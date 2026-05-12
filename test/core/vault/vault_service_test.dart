import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:secure_box/data/models/password_entry.dart';
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
