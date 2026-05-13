import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:secure_box/core/backup/backup_service.dart';
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

  test('backup JSON contains encrypted item fields only', () {
    final backup = VaultBackup(
      version: 1,
      kdf: 'pbkdf2-hmac-sha256',
      kdfParams: {'iterations': 120000, 'bits': 256},
      salt: 'salt',
      encryptedDekByMaster: 'encrypted-dek',
      encryptedDekByMasterNonce: 'nonce',
      encryptedDekByMasterMac: 'mac',
      items: const [
        BackupItem(
          id: '1',
          nonce: 'item-nonce',
          ciphertext: 'item-ciphertext',
          mac: 'item-mac',
        ),
      ],
    );

    final jsonText = jsonEncode(backup.toJson());
    expect(jsonText, contains('item-ciphertext'));
    expect(jsonText, isNot(contains('secret-password')));
    expect(jsonText, isNot(contains('user@example.com')));
  });

  test('unsupported backup version is rejected', () {
    expect(
      () => VaultBackup.fromJson({'version': 99}),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test(
    'exportBackup includes encrypted vault metadata and active items only',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');

      final activeId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'private note',
          tags: ['dev'],
        ),
      );
      final deletedId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'Bank',
          website: 'https://bank.example',
          username: 'cash-user',
          password: 'bank-password',
          notes: 'monthly bills',
          tags: ['finance'],
        ),
      );
      await source.vaultService.deleteItem(deletedId);

      final backup = await source.backupService.exportBackup();
      final jsonText = jsonEncode(backup.toJson());

      expect(backup.version, 1);
      expect(backup.items.map((item) => item.id), [activeId]);
      expect(jsonText, contains('encrypted_dek_by_master'));
      expect(jsonText, contains(backup.items.single.ciphertext));
      expect(jsonText, isNot(contains('secret-password')));
      expect(jsonText, isNot(contains('user@example.com')));
      expect(jsonText, isNot(contains('private note')));
    },
  );

  test(
    'importBackup rejects a wrong backup master password without writing data',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      await source.vaultService.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'private note',
          tags: ['dev'],
        ),
      );

      final backup = await source.backupService.exportBackup();
      final target = await _buildHarness();

      await expectLater(
        target.backupService.importBackup(
          json: backup.toJson(),
          masterPassword: 'wrong-master',
          mode: BackupImportMode.overwrite,
        ),
        throwsA(isA<VaultUnlockException>()),
      );
      expect(await target.repository.metaDao.get(), isNull);
      expect(await target.repository.itemsDao.rawRowsForTest(), isEmpty);
    },
  );

  test(
    'importBackup overwrite restores the encrypted vault and replaces target items',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final githubId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'private note',
          tags: ['dev'],
        ),
      );
      final backup = await source.backupService.exportBackup();

      final target = await _buildHarness();
      await target.backupService.importBackup(
        json: backup.toJson(),
        masterPassword: 'source-master',
        mode: BackupImportMode.overwrite,
      );

      final unlocked = await target.vaultService.unlock(
        masterPassword: 'source-master',
      );
      expect(unlocked.isUnlocked, isTrue);

      final importedEntry = await target.vaultService.getItem(githubId);
      expect(importedEntry.title, 'GitHub');
      expect(importedEntry.username, 'user@example.com');
      expect(importedEntry.password, 'secret-password');
      expect(importedEntry.notes, 'private note');
    },
  );

  test('importBackup skip keeps duplicate rows and adds new ones', () async {
    final source = await _buildHarness();
    await source.vaultService.createVault(masterPassword: 'source-master');
    await source.vaultService.unlock(masterPassword: 'source-master');
    final githubId = await source.vaultService.createItem(
      PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: 'private note',
        tags: ['dev'],
      ),
    );

    final initialBackup = await source.backupService.exportBackup();
    final target = await _buildHarness();
    await target.backupService.importBackup(
      json: initialBackup.toJson(),
      masterPassword: 'source-master',
      mode: BackupImportMode.overwrite,
    );
    await target.vaultService.unlock(masterPassword: 'source-master');
    final beforeSkip = await target.vaultService.getItem(githubId);
    expect(beforeSkip.password, 'secret-password');

    await source.vaultService.updateItem(
      githubId,
      PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'rotated-password',
        notes: 'rotated note',
        tags: ['dev'],
      ),
    );
    final newId = await source.vaultService.createItem(
      PasswordEntry(
        title: 'Docs',
        website: 'https://docs.example',
        username: 'docs@example.com',
        password: 'docs-password',
        notes: 'new item',
        tags: ['docs'],
      ),
    );
    final updatedBackup = await source.backupService.exportBackup();

    await target.backupService.importBackup(
      json: updatedBackup.toJson(),
      masterPassword: 'source-master',
      mode: BackupImportMode.skip,
    );

    final preserved = await target.vaultService.getItem(githubId);
    final added = await target.vaultService.getItem(newId);

    expect(preserved.password, 'secret-password');
    expect(preserved.notes, 'private note');
    expect(added.password, 'docs-password');
  });

  test(
    'importBackup merge overwrites duplicates and keeps non-conflicting rows',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final githubId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'private note',
          tags: ['dev'],
        ),
      );

      final initialBackup = await source.backupService.exportBackup();
      final target = await _buildHarness();
      await target.backupService.importBackup(
        json: initialBackup.toJson(),
        masterPassword: 'source-master',
        mode: BackupImportMode.overwrite,
      );
      await target.vaultService.unlock(masterPassword: 'source-master');
      final localOnlyId = await target.vaultService.createItem(
        PasswordEntry(
          title: 'Local',
          website: 'https://local.example',
          username: 'local-user',
          password: 'local-password',
          notes: 'target only',
          tags: ['local'],
        ),
      );

      await source.vaultService.updateItem(
        githubId,
        PasswordEntry(
          title: 'GitHub Admin',
          website: 'https://github.com',
          username: 'admin@example.com',
          password: 'rotated-password',
          notes: 'updated remotely',
          tags: ['admin'],
        ),
      );
      final mergedBackup = await source.backupService.exportBackup();

      await target.backupService.importBackup(
        json: mergedBackup.toJson(),
        masterPassword: 'source-master',
        mode: BackupImportMode.merge,
      );

      final merged = await target.vaultService.getItem(githubId);
      final localOnly = await target.vaultService.getItem(localOnlyId);

      expect(merged.title, 'GitHub Admin');
      expect(merged.username, 'admin@example.com');
      expect(merged.password, 'rotated-password');
      expect(merged.notes, 'updated remotely');
      expect(localOnly.password, 'local-password');
    },
  );
}

Future<_BackupHarness> _buildHarness() async {
  final tempDir = await Directory.systemTemp.createTemp('secure_box_backup_');
  addTearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final db = await AppDatabase.open(p.join(tempDir.path, 'vault.db'));
  addTearDown(db.close);
  final repository = VaultRepository(
    metaDao: VaultMetaDao(db),
    itemsDao: VaultItemsDao(db),
    settingsDao: SettingsDao(db),
  );
  final vaultService = VaultService(
    repository: repository,
    random: SecureRandom(),
    kdf: KdfService(),
    crypto: CryptoService(random: SecureRandom()),
  );

  return _BackupHarness(
    repository: repository,
    vaultService: vaultService,
    backupService: BackupService(
      repository: repository,
      vaultService: vaultService,
    ),
  );
}

class _BackupHarness {
  const _BackupHarness({
    required this.repository,
    required this.vaultService,
    required this.backupService,
  });

  final VaultRepository repository;
  final VaultService vaultService;
  final BackupService backupService;
}
