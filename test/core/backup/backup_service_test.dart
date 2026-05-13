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
import 'package:secure_box/data/models/vault_meta.dart';
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
    'importBackup skip preserves existing vault meta and biometric state while importing from a different vault envelope',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final sharedSourceId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'Remote Shared',
          website: 'https://shared.example',
          username: 'remote@example.com',
          password: 'remote-password',
          notes: 'from backup',
          tags: ['shared'],
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
      final exportedBackup = await source.backupService.exportBackup();

      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'target-master');
      await target.vaultService.unlock(masterPassword: 'target-master');
      final sharedId = await target.vaultService.createItem(
        PasswordEntry(
          title: 'Local Shared',
          website: 'https://shared.example',
          username: 'local@example.com',
          password: 'local-password',
          notes: 'local copy',
          tags: ['shared'],
        ),
      );
      final originalMeta = await _setBiometricMeta(target.repository);
      final importedJson = _backupJsonWithItemIdReplacement(
        backup: exportedBackup,
        fromId: sharedSourceId,
        toId: sharedId,
      );

      final importedCount = await target.backupService.importBackup(
        json: importedJson,
        masterPassword: 'source-master',
        mode: BackupImportMode.skip,
      );

      final importedMeta = await target.repository.metaDao.get();
      final preserved = await target.vaultService.getItem(sharedId);
      final added = await target.vaultService.getItem(newId);

      expect(importedCount, 1);
      expect(importedMeta, isNotNull);
      _expectMetaPreserved(importedMeta!, originalMeta);
      expect(preserved.password, 'local-password');
      expect(preserved.notes, 'local copy');
      expect(added.password, 'docs-password');
      expect(added.notes, 'new item');
    },
  );

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

  test(
    'importBackup merge preserves existing vault meta and biometric state while replacing duplicate rows from a different vault envelope',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final sharedSourceId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'Remote Shared',
          website: 'https://shared.example',
          username: 'remote@example.com',
          password: 'remote-password',
          notes: 'updated from backup',
          tags: ['shared'],
        ),
      );
      final exportedBackup = await source.backupService.exportBackup();

      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'target-master');
      await target.vaultService.unlock(masterPassword: 'target-master');
      final sharedId = await target.vaultService.createItem(
        PasswordEntry(
          title: 'Local Shared',
          website: 'https://shared.example',
          username: 'local@example.com',
          password: 'local-password',
          notes: 'local copy',
          tags: ['shared'],
        ),
      );
      final localOnlyId = await target.vaultService.createItem(
        PasswordEntry(
          title: 'Local Only',
          website: 'https://local.example',
          username: 'local-only@example.com',
          password: 'local-only-password',
          notes: 'target only',
          tags: ['local'],
        ),
      );
      final originalMeta = await _setBiometricMeta(target.repository);
      final importedJson = _backupJsonWithItemIdReplacement(
        backup: exportedBackup,
        fromId: sharedSourceId,
        toId: sharedId,
      );

      final importedCount = await target.backupService.importBackup(
        json: importedJson,
        masterPassword: 'source-master',
        mode: BackupImportMode.merge,
      );

      final importedMeta = await target.repository.metaDao.get();
      final merged = await target.vaultService.getItem(sharedId);
      final localOnly = await target.vaultService.getItem(localOnlyId);

      expect(importedCount, 1);
      expect(importedMeta, isNotNull);
      _expectMetaPreserved(importedMeta!, originalMeta);
      expect(merged.username, 'remote@example.com');
      expect(merged.password, 'remote-password');
      expect(merged.notes, 'updated from backup');
      expect(localOnly.password, 'local-only-password');
      expect(localOnly.notes, 'target only');
    },
  );

  test(
    'importBackup skip requires the target vault to be unlocked when re-encryption is needed',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      await source.vaultService.createItem(
        PasswordEntry(
          title: 'Docs',
          website: 'https://docs.example',
          username: 'docs@example.com',
          password: 'docs-password',
          notes: 'new item',
          tags: ['docs'],
        ),
      );
      final backup = await source.backupService.exportBackup();

      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'target-master');

      await expectLater(
        target.backupService.importBackup(
          json: backup.toJson(),
          masterPassword: 'source-master',
          mode: BackupImportMode.skip,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('must already be unlocked'),
          ),
        ),
      );
    },
  );

  test(
    'importBackup skip with a different envelope succeeds as a no-op while locked when there are no new items',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final sharedSourceId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'Remote Shared',
          website: 'https://shared.example',
          username: 'remote@example.com',
          password: 'remote-password',
          notes: 'from backup',
          tags: ['shared'],
        ),
      );
      final exportedBackup = await source.backupService.exportBackup();

      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'target-master');
      await target.vaultService.unlock(masterPassword: 'target-master');
      final sharedId = await target.vaultService.createItem(
        PasswordEntry(
          title: 'Local Shared',
          website: 'https://shared.example',
          username: 'local@example.com',
          password: 'local-password',
          notes: 'local copy',
          tags: ['shared'],
        ),
      );
      final importedJson = _backupJsonWithItemIdReplacement(
        backup: exportedBackup,
        fromId: sharedSourceId,
        toId: sharedId,
      );
      target.vaultService.lock();

      final importedCount = await target.backupService.importBackup(
        json: importedJson,
        masterPassword: 'source-master',
        mode: BackupImportMode.skip,
      );

      expect(importedCount, 0);
      await target.vaultService.unlock(masterPassword: 'target-master');
      final preserved = await target.vaultService.getItem(sharedId);
      expect(preserved.password, 'local-password');
      expect(preserved.notes, 'local copy');
    },
  );

  test(
    'overwrite import clears the active session so later different-envelope imports stay decryptable after relock',
    () async {
      final sourceA = await _buildHarness();
      await sourceA.vaultService.createVault(masterPassword: 'source-a-master');
      await sourceA.vaultService.unlock(masterPassword: 'source-a-master');
      final sourceAId = await sourceA.vaultService.createItem(
        PasswordEntry(
          title: 'Primary',
          website: 'https://primary.example',
          username: 'primary@example.com',
          password: 'primary-password',
          notes: 'first backup',
          tags: ['primary'],
        ),
      );
      final backupA = await sourceA.backupService.exportBackup();

      final sourceB = await _buildHarness();
      await sourceB.vaultService.createVault(masterPassword: 'source-b-master');
      await sourceB.vaultService.unlock(masterPassword: 'source-b-master');
      final sourceBId = await sourceB.vaultService.createItem(
        PasswordEntry(
          title: 'Secondary',
          website: 'https://secondary.example',
          username: 'secondary@example.com',
          password: 'secondary-password',
          notes: 'second backup',
          tags: ['secondary'],
        ),
      );
      final backupB = await sourceB.backupService.exportBackup();

      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'target-master');
      await target.vaultService.unlock(masterPassword: 'target-master');

      await target.backupService.importBackup(
        json: backupA.toJson(),
        masterPassword: 'source-a-master',
        mode: BackupImportMode.overwrite,
      );

      expect(target.vaultService.isUnlocked, isFalse);

      await target.vaultService.unlock(masterPassword: 'source-a-master');
      await target.backupService.importBackup(
        json: backupB.toJson(),
        masterPassword: 'source-b-master',
        mode: BackupImportMode.skip,
      );

      target.vaultService.lock();
      await target.vaultService.unlock(masterPassword: 'source-a-master');

      final primary = await target.vaultService.getItem(sourceAId);
      final secondary = await target.vaultService.getItem(sourceBId);
      expect(primary.password, 'primary-password');
      expect(primary.notes, 'first backup');
      expect(secondary.password, 'secondary-password');
      expect(secondary.notes, 'second backup');
    },
  );
}

Map<String, Object?> _backupJsonWithItemIdReplacement({
  required VaultBackup backup,
  required String fromId,
  required String toId,
}) {
  final json = backup.toJson();
  final items = List<Map<String, Object?>>.from(
    (json['items']! as List<Object?>).map(
      (item) => Map<String, Object?>.from(item! as Map<Object?, Object?>),
    ),
  );
  final itemIndex = items.indexWhere((item) => item['id'] == fromId);
  if (itemIndex == -1) {
    throw StateError('Expected backup item with id "$fromId"');
  }
  items[itemIndex] = {...items[itemIndex], 'id': toId};

  return {...json, 'items': items};
}

Future<VaultMeta> _setBiometricMeta(VaultRepository repository) async {
  final meta = (await repository.metaDao.get())!;
  final updatedMeta = VaultMeta(
    id: meta.id,
    version: meta.version,
    kdf: meta.kdf,
    kdfParams: meta.kdfParams,
    salt: meta.salt,
    encryptedDekByMaster: meta.encryptedDekByMaster,
    encryptedDekByMasterNonce: meta.encryptedDekByMasterNonce,
    encryptedDekByMasterMac: meta.encryptedDekByMasterMac,
    biometricEnabled: true,
    createdAt: meta.createdAt,
    updatedAt: meta.updatedAt,
    encryptedDekByBiometric: 'encrypted-biometric-dek',
    encryptedDekByBiometricNonce: 'biometric-nonce',
    encryptedDekByBiometricMac: 'biometric-mac',
  );
  await repository.metaDao.save(updatedMeta);
  return updatedMeta;
}

void _expectMetaPreserved(VaultMeta actual, VaultMeta expected) {
  expect(actual.id, expected.id);
  expect(actual.version, expected.version);
  expect(actual.kdf, expected.kdf);
  expect(actual.kdfParams.name, expected.kdfParams.name);
  expect(actual.kdfParams.iterations, expected.kdfParams.iterations);
  expect(actual.kdfParams.bits, expected.kdfParams.bits);
  expect(actual.salt, expected.salt);
  expect(actual.encryptedDekByMaster, expected.encryptedDekByMaster);
  expect(actual.encryptedDekByMasterNonce, expected.encryptedDekByMasterNonce);
  expect(actual.encryptedDekByMasterMac, expected.encryptedDekByMasterMac);
  expect(actual.biometricEnabled, expected.biometricEnabled);
  expect(actual.encryptedDekByBiometric, expected.encryptedDekByBiometric);
  expect(
    actual.encryptedDekByBiometricNonce,
    expected.encryptedDekByBiometricNonce,
  );
  expect(
    actual.encryptedDekByBiometricMac,
    expected.encryptedDekByBiometricMac,
  );
  expect(actual.createdAt, expected.createdAt);
  expect(actual.updatedAt, expected.updatedAt);
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
