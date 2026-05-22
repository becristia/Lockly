import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';
import 'package:secure_box/core/backup/backup_service.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/encoding.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/vault/vault_anchor_service.dart';
import 'package:secure_box/core/vault/vault_anchor_store.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_session.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/password_history_dao.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_manifest_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/data/models/vault_meta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('version 2 backup JSON requires manifest integrity fields', () async {
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
    final json = backup.toJson();
    final jsonText = jsonEncode(json);

    expect(backup.version, 2);
    expect(json['magic'], 'secure-box-backup');
    expect(json['created_at'], isA<int>());
    expect(json['item_count'], 1);
    expect(json['manifest'], isA<Map<String, Object?>>());
    expect(jsonText, isNot(contains('secret-password')));
    expect(jsonText, isNot(contains('user@example.com')));
    expect(jsonText, isNot(contains('private note')));
  });

  test('unsupported backup version is rejected', () {
    expect(
      () => VaultBackup.fromJson({'version': 99}),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('import rejects excessive KDF work factors before verification', () {
    expect(
      () => VaultBackup(
        version: 1,
        kdf: 'argon2id',
        kdfParams: {
          'name': 'argon2id',
          'iterations': 3,
          'bits': 256,
          'memoryKiB': 1048576,
          'parallelism': 1,
        },
        salt: 'salt',
        encryptedDekByMaster: 'encrypted-dek',
        encryptedDekByMasterNonce: 'nonce',
        encryptedDekByMasterMac: 'mac',
        items: const [],
      ),
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

      expect(backup.version, 2);
      expect(backup.magic, 'secure-box-backup');
      expect(backup.itemCount, 1);
      expect(backup.manifest, isNotNull);
      expect(backup.items.map((item) => item.id), [activeId]);
      expect(jsonText, contains('encrypted_dek_by_master'));
      expect(jsonText, contains(backup.items.single.ciphertext));
      expect(jsonText, isNot(contains('secret-password')));
      expect(jsonText, isNot(contains('user@example.com')));
      expect(jsonText, isNot(contains('private note')));
    },
  );

  test('exportItemBackup exports only the requested active item', () async {
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
    final docsId = await source.vaultService.createItem(
      PasswordEntry(
        title: 'Docs',
        website: 'https://docs.example',
        username: 'docs@example.com',
        password: 'docs-password',
        notes: 'not exported',
        tags: ['docs'],
      ),
    );

    final backup = await source.backupService.exportItemBackup(githubId);

    expect(backup.version, 2);
    expect(backup.itemCount, 1);
    expect(backup.items.map((item) => item.id), [githubId]);
    expect(backup.items.map((item) => item.id), isNot(contains(docsId)));
    expect(jsonEncode(backup.toJson()), isNot(contains('secret-password')));
    expect(jsonEncode(backup.toJson()), isNot(contains('docs-password')));
  });

  test('item backup cannot be imported with overwrite mode', () async {
    final source = await _buildHarness();
    await source.vaultService.createVault(masterPassword: 'source-master');
    await source.vaultService.unlock(masterPassword: 'source-master');
    final itemId = await source.vaultService.createItem(
      PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: 'private note',
        tags: const ['dev'],
      ),
    );
    final itemBackup = await source.backupService.exportItemBackup(itemId);

    final target = await _buildHarness();
    await target.vaultService.createVault(masterPassword: 'target-master');
    await target.vaultService.unlock(masterPassword: 'target-master');
    final localId = await target.vaultService.createItem(
      PasswordEntry(
        title: 'Docs',
        website: 'https://docs.example',
        username: 'docs@example.com',
        password: 'docs-password',
        notes: 'local item',
        tags: const ['docs'],
      ),
    );

    await expectLater(
      target.backupService.importBackup(
        json: itemBackup.toJson(),
        masterPassword: 'source-master',
        mode: BackupImportMode.overwrite,
      ),
      throwsA(isA<BackupFormatException>()),
    );

    expect(
      (await target.vaultService.getItem(localId)).password,
      'docs-password',
    );
  });

  test('exportBackup fails when the live manifest is tampered', () async {
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
    final manifest = await source.repository.manifestDao.get();
    await source.repository.manifestDao.save(
      manifest!.copyWith(mac: _tamperBase64(manifest.mac)),
    );

    await expectLater(
      source.backupService.exportBackup(),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

  test('exportBackup fails while the vault is locked', () async {
    final source = await _buildHarness();
    await source.vaultService.createVault(masterPassword: 'source-master');

    await expectLater(
      source.backupService.exportBackup(),
      throwsA(isA<VaultLockedException>()),
    );
  });

  test('argon2id backup export preserves full kdf params', () async {
    final source = await _buildHarness();
    await _createEmptyArgon2idVault(source, masterPassword: 'source-master');
    await source.vaultService.unlock(masterPassword: 'source-master');

    final backup = await source.backupService.exportBackup();

    expect(backup.kdf, 'argon2id');
    expect(backup.kdfParams, {
      'name': 'argon2id',
      'iterations': 3,
      'bits': 256,
      'memoryKiB': 1024,
      'parallelism': 1,
    });
    expect(backup.parsedKdfParams.name, 'argon2id');
    expect(backup.parsedKdfParams.memoryKiB, 1024);
    expect(backup.parsedKdfParams.parallelism, 1);
  });

  test('legacy v1 backup import is rejected by default', () async {
    final source = await _buildHarness();
    await _createEmptyArgon2idVault(source, masterPassword: 'source-master');
    await source.vaultService.unlock(masterPassword: 'source-master');
    final backup = await source.backupService.exportBackup();

    final target = await _buildHarness();
    expect(
      target.backupService.importBackup(
        json: _asLegacyBackupJson(backup.toJson()),
        masterPassword: 'source-master',
        mode: BackupImportMode.overwrite,
      ),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test(
    'v1 import generates a target manifest and leaves imported vault unlockable',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final itemId = await source.vaultService.createItem(
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
        json: _asLegacyBackupJson(backup.toJson()),
        masterPassword: 'source-master',
        mode: BackupImportMode.overwrite,
        allowLegacyBackups: true,
      );

      expect(await target.repository.manifestDao.get(), isNotNull);
      await target.vaultService.unlock(masterPassword: 'source-master');
      final imported = await target.vaultService.getItem(itemId);
      expect(imported.password, 'secret-password');
    },
  );

  test('AppServices rejects oversized backup JSON before parsing', () async {
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      trackActivity: false,
      importBackupOverride: (backupJson, masterPassword) async {
        throw StateError('import override should not be called');
      },
    );
    addTearDown(services.dispose);

    final oversizedBackup = ' ' * (AppServices.maxImportedBackupJsonBytes + 1);

    await expectLater(
      services.importEncryptedBackupJson(
        backupJson: oversizedBackup,
        masterPassword: 'source-master',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'v2 import rejects tampered item ciphertext before writing target data',
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
      await target.vaultService.createVault(masterPassword: 'target-master');
      await target.vaultService.unlock(masterPassword: 'target-master');
      final localId = await target.vaultService.createItem(
        PasswordEntry(
          title: 'Local',
          website: 'https://local.example',
          username: 'local@example.com',
          password: 'local-password',
          notes: 'target item',
          tags: ['local'],
        ),
      );
      final originalMeta = await target.repository.metaDao.get();
      final originalManifest = await target.repository.manifestDao.get();
      final backupJson = backup.toJson();
      final items = List<Map<String, Object?>>.from(
        (backupJson['items']! as List<Object?>).map(
          (item) => Map<String, Object?>.from(item! as Map<Object?, Object?>),
        ),
      );
      items[0] = {
        ...items[0],
        'ciphertext': _tamperBase64(items[0]['ciphertext']! as String),
      };

      await expectLater(
        target.backupService.importBackup(
          json: {...backupJson, 'items': items},
          masterPassword: 'source-master',
          mode: BackupImportMode.overwrite,
        ),
        throwsA(isA<VaultIntegrityException>()),
      );

      expect((await target.repository.metaDao.get())!.id, originalMeta!.id);
      expect(
        (await target.repository.manifestDao.get())!.counter,
        originalManifest!.counter,
      );
      final local = await target.vaultService.getItem(localId);
      expect(local.password, 'local-password');
    },
  );

  test(
    'v2 import from biometric-enabled source succeeds and disables biometric on target',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final itemId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: 'private note',
          tags: ['dev'],
        ),
      );
      await _enableBiometricMeta(source, masterPassword: 'source-master');

      final backup = await source.backupService.exportBackup();
      final backupJson = backup.toJson();
      expect(backupJson['biometric_enabled'], isTrue);

      final target = await _buildHarness();
      await target.backupService.importBackup(
        json: backupJson,
        masterPassword: 'source-master',
        mode: BackupImportMode.overwrite,
      );

      final targetMeta = await target.repository.metaDao.get();
      expect(targetMeta, isNotNull);
      expect(targetMeta!.biometricEnabled, isFalse);
      expect(targetMeta.encryptedDekByBiometric, isNull);
      await target.vaultService.unlock(masterPassword: 'source-master');
      final imported = await target.vaultService.getItem(itemId);
      expect(imported.password, 'secret-password');
    },
  );

  test(
    'v2 import rejects tampered biometric metadata before writing target data',
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
      await _enableBiometricMeta(source, masterPassword: 'source-master');
      final backup = await source.backupService.exportBackup();

      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'target-master');
      final originalMeta = await target.repository.metaDao.get();

      await expectLater(
        target.backupService.importBackup(
          json: {...backup.toJson(), 'biometric_enabled': false},
          masterPassword: 'source-master',
          mode: BackupImportMode.overwrite,
        ),
        throwsA(isA<VaultIntegrityException>()),
      );

      expect((await target.repository.metaDao.get())!.id, originalMeta!.id);
      expect(await target.repository.itemsDao.rawRowsForTest(), isEmpty);
    },
  );

  test('v2 import rejects item_count mismatch and invalid magic', () async {
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
        json: {...backup.toJson(), 'item_count': 2},
        masterPassword: 'source-master',
        mode: BackupImportMode.overwrite,
      ),
      throwsA(
        anyOf(isA<BackupFormatException>(), isA<VaultIntegrityException>()),
      ),
    );
    expect(await target.repository.metaDao.get(), isNull);

    await expectLater(
      target.backupService.importBackup(
        json: {...backup.toJson(), 'magic': 'tampered'},
        masterPassword: 'source-master',
        mode: BackupImportMode.overwrite,
      ),
      throwsA(
        anyOf(isA<BackupFormatException>(), isA<VaultIntegrityException>()),
      ),
    );
    expect(await target.repository.metaDao.get(), isNull);
  });

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

  test(
    'importBackup overwrite accepts rewritten target manifest into anchor',
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
          tags: const ['dev'],
        ),
      );
      final backup = await source.backupService.exportBackup();

      final target = await _buildHarness();
      await target.backupService.importBackup(
        json: backup.toJson(),
        masterPassword: 'source-master',
        mode: BackupImportMode.overwrite,
      );

      final meta = await target.repository.metaDao.get();
      final manifest = await target.repository.manifestDao.get();
      final anchor = await target.anchorStore.read(vaultId: meta!.id);
      expect(anchor, isNotNull);
      expect(anchor!.manifestCounter, manifest!.counter);
    },
  );

  test(
    'importBackup overwrite rejects target rollback before writing data',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'shared-master');
      await source.vaultService.unlock(masterPassword: 'shared-master');
      final sourceId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'Source',
          website: 'https://source.example',
          username: 'source@example.com',
          password: 'source-password',
          notes: 'source note',
          tags: const ['source'],
        ),
      );
      final backup = await source.backupService.exportBackup();

      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'shared-master');
      await target.vaultService.unlock(masterPassword: 'shared-master');
      final targetId = await target.vaultService.createItem(
        PasswordEntry(
          title: 'Target',
          website: 'https://target.example',
          username: 'target@example.com',
          password: 'target-password',
          notes: 'target note',
          tags: const ['target'],
        ),
      );
      final targetMeta = await target.repository.metaDao.get();
      final targetManifest = await target.repository.manifestDao.get();
      await VaultAnchorService(store: target.anchorStore).writeAcceptedManifest(
        vaultId: targetMeta!.id,
        manifest: targetManifest!.copyWith(counter: targetManifest.counter + 2),
        updatedAt: targetManifest.updatedAt + 2,
      );
      target.vaultService.lock();

      await expectLater(
        target.backupService.importBackup(
          json: backup.toJson(),
          masterPassword: 'shared-master',
          mode: BackupImportMode.overwrite,
        ),
        throwsA(isA<VaultIntegrityException>()),
      );

      final rows = await target.repository.itemsDao.rawRowsForTest();
      expect(rows, hasLength(1));
      expect(rows.single['id'], targetId);
      expect(rows.single['id'], isNot(sourceId));
      final preservedMeta = await target.repository.metaDao.get();
      expect(preservedMeta!.id, targetMeta.id);
      expect(
        preservedMeta.encryptedDekByMaster,
        targetMeta.encryptedDekByMaster,
      );
      expect(target.vaultService.isUnlocked, isFalse);
    },
  );

  test(
    'importBackup overwrite rejects stale anchor for imported vault id',
    () async {
      final sourceA = await _buildHarness();
      await sourceA.vaultService.createVault(masterPassword: 'source-a-master');
      await sourceA.vaultService.unlock(masterPassword: 'source-a-master');
      await sourceA.vaultService.createItem(
        PasswordEntry(
          title: 'Source A',
          website: 'https://a.example',
          username: 'a@example.com',
          password: 'a-password',
          notes: 'older backup',
          tags: const ['a'],
        ),
      );
      final backupA = await sourceA.backupService.exportBackup();
      final sourceAMeta = await sourceA.repository.metaDao.get();
      final sourceAManifest = await sourceA.repository.manifestDao.get();

      final sourceB = await _buildHarness();
      await sourceB.vaultService.createVault(masterPassword: 'source-b-master');
      await sourceB.vaultService.unlock(masterPassword: 'source-b-master');
      final sourceBId = await sourceB.vaultService.createItem(
        PasswordEntry(
          title: 'Source B',
          website: 'https://b.example',
          username: 'b@example.com',
          password: 'b-password',
          notes: 'current backup',
          tags: const ['b'],
        ),
      );
      final backupB = await sourceB.backupService.exportBackup();

      final target = await _buildHarness();
      final advancedAAnchorManifest = sourceAManifest!.copyWith(
        counter: sourceAManifest.counter + 5,
      );
      await VaultAnchorService(store: target.anchorStore).writeAcceptedManifest(
        vaultId: sourceAMeta!.id,
        manifest: advancedAAnchorManifest,
        updatedAt: sourceAManifest.updatedAt + 5,
      );

      await target.backupService.importBackup(
        json: backupB.toJson(),
        masterPassword: 'source-b-master',
        mode: BackupImportMode.overwrite,
      );
      await target.vaultService.unlock(masterPassword: 'source-b-master');
      final targetMetaAfterB = await target.repository.metaDao.get();

      await expectLater(
        target.backupService.importBackup(
          json: backupA.toJson(),
          masterPassword: 'source-a-master',
          mode: BackupImportMode.overwrite,
        ),
        throwsA(isA<VaultIntegrityException>()),
      );

      final preservedAAnchor = await target.anchorStore.read(
        vaultId: sourceAMeta.id,
      );
      expect(
        preservedAAnchor!.manifestCounter,
        advancedAAnchorManifest.counter,
      );
      final targetMetaAfterFailedA = await target.repository.metaDao.get();
      expect(targetMetaAfterFailedA!.id, targetMetaAfterB!.id);
      final rows = await target.repository.itemsDao.rawRowsForTest();
      expect(rows.map((row) => row['id']), contains(sourceBId));
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

  test('importBackup skip restores a soft-deleted duplicate row', () async {
    final source = await _buildHarness();
    await source.vaultService.createVault(masterPassword: 'source-master');
    await source.vaultService.unlock(masterPassword: 'source-master');
    final sourceId = await source.vaultService.createItem(
      PasswordEntry(
        title: 'Imported',
        website: 'https://import.example',
        username: 'import@example.com',
        password: 'imported-password',
        notes: 'from backup',
        tags: const ['backup'],
      ),
    );
    final backup = await source.backupService.exportBackup();

    final target = await _buildHarness();
    await target.vaultService.createVault(masterPassword: 'target-master');
    await target.vaultService.unlock(masterPassword: 'target-master');
    final localId = await target.vaultService.createItem(
      PasswordEntry(
        title: 'Local',
        website: 'https://local.example',
        username: 'local@example.com',
        password: 'local-password',
        notes: 'deleted local row',
        tags: const ['local'],
      ),
    );
    await target.vaultService.deleteItem(localId);
    final importedJson = _backupJsonWithItemIdReplacement(
      backup: backup,
      fromId: sourceId,
      toId: localId,
    );

    final importedCount = await target.backupService.importBackup(
      json: importedJson,
      masterPassword: 'source-master',
      mode: BackupImportMode.skip,
      allowLegacyBackups: true,
    );

    final restored = await target.vaultService.getItem(localId);
    expect(importedCount, 1);
    expect(restored.title, 'Imported');
    expect(restored.password, 'imported-password');
    expect((await target.repository.itemsDao.byId(localId))!.deletedAt, isNull);
  });

  test(
    'locked same-envelope skip import preserves existing password history manifest',
    () async {
      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'target-master');
      await target.vaultService.unlock(masterPassword: 'target-master');
      final existingId = await target.vaultService.createItem(
        PasswordEntry(
          title: 'Existing',
          website: 'https://existing.example',
          username: 'existing@example.com',
          password: 'old-password',
          notes: 'with history',
          tags: const ['local'],
        ),
      );
      await target.vaultService.updateItem(
        existingId,
        PasswordEntry(
          title: 'Existing',
          website: 'https://existing.example',
          username: 'existing@example.com',
          password: 'new-password',
          notes: 'with history',
          tags: const ['local'],
        ),
      );
      final importedId = await target.vaultService.createItem(
        PasswordEntry(
          title: 'Imported Later',
          website: 'https://later.example',
          username: 'later@example.com',
          password: 'later-password',
          notes: 'same envelope backup',
          tags: const ['backup'],
        ),
      );
      final backup = await target.backupService.exportBackup();
      await target.vaultService.deleteItem(importedId);
      await target.vaultService.permanentlyDeleteItem(importedId);
      target.vaultService.lock();

      final importedCount = await target.backupService.importBackup(
        json: backup.toJson(),
        masterPassword: 'target-master',
        mode: BackupImportMode.skip,
      );

      expect(importedCount, 1);
      await target.vaultService.unlock(masterPassword: 'target-master');
      expect(
        (await target.vaultService.getItem(importedId)).password,
        'later-password',
      );
      expect(
        (await target.vaultService.listPasswordHistory(
          existingId,
        )).single['password'],
        'old-password',
      );
    },
  );

  test(
    'importBackup skip increments target manifest once when data changes',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final firstId = await source.vaultService.createItem(
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
      final before = await target.repository.manifestDao.get();

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
      final updatedBackup = await source.backupService.exportBackup();

      final importedCount = await target.backupService.importBackup(
        json: updatedBackup.toJson(),
        masterPassword: 'source-master',
        mode: BackupImportMode.skip,
      );

      final after = await target.repository.manifestDao.get();
      expect(importedCount, 1);
      expect(after!.counter, before!.counter + 1);
      expect(
        (await target.vaultService.getItem(firstId)).password,
        'secret-password',
      );
    },
  );

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
      final originalMeta = await _enableBiometricMeta(
        target,
        masterPassword: 'target-master',
      );
      final importedJson = _backupJsonWithItemIdReplacement(
        backup: exportedBackup,
        fromId: sharedSourceId,
        toId: sharedId,
      );

      final importedCount = await target.backupService.importBackup(
        json: importedJson,
        masterPassword: 'source-master',
        mode: BackupImportMode.skip,
        allowLegacyBackups: true,
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
    'AppServices import re-encrypts imported rows under the current vault',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
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
      final sourceNewRow = await source.repository.itemsDao.byId(newId);

      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'target-master');
      await target.vaultService.unlock(masterPassword: 'target-master');
      final services = AppServices(
        hasVault: true,
        initialShellState: AppShellState.unlocked,
        trackActivity: false,
        vaultService: target.vaultService,
        backupService: target.backupService,
      );
      addTearDown(services.dispose);

      final importedCount = await services.importEncryptedBackupJson(
        backupJson: jsonEncode(exportedBackup.toJson()),
        masterPassword: 'source-master',
      );

      final added = await target.vaultService.getItem(newId);
      final targetNewRow = await target.repository.itemsDao.byId(newId);

      expect(importedCount, 1);
      expect(added.password, 'docs-password');
      expect(targetNewRow, isNotNull);
      expect(targetNewRow!.ciphertext, isNot(sourceNewRow!.ciphertext));
      expect(targetNewRow.nonce, isNot(sourceNewRow.nonce));
      target.vaultService.lock();
      await target.vaultService.unlock(masterPassword: 'target-master');
      expect(
        (await target.vaultService.getItem(newId)).password,
        'docs-password',
      );
    },
  );

  test(
    'AppServices import into an empty app restores history and locks shell',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final itemId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'Docs',
          website: 'https://docs.example',
          username: 'docs@example.com',
          password: 'old-password',
          notes: 'new app restore',
          tags: ['docs'],
        ),
      );
      await source.vaultService.updateItem(
        itemId,
        PasswordEntry(
          title: 'Docs',
          website: 'https://docs.example',
          username: 'docs@example.com',
          password: 'new-password',
          notes: 'new app restore',
          tags: ['docs'],
        ),
      );
      final exportedBackup = await source.backupService.exportBackup();

      final target = await _buildHarness();
      final services = AppServices(
        hasVault: false,
        initialShellState: AppShellState.setupRequired,
        trackActivity: false,
        vaultService: target.vaultService,
        backupService: target.backupService,
      );
      addTearDown(services.dispose);

      final importedCount = await services.importEncryptedBackupJson(
        backupJson: jsonEncode(exportedBackup.toJson()),
        masterPassword: 'source-master',
      );

      expect(importedCount, 1);
      expect(services.hasVault, isTrue);
      expect(services.shellState.value, AppShellState.locked);
      expect(target.vaultService.isUnlocked, isFalse);

      await target.vaultService.unlock(masterPassword: 'source-master');
      expect(
        (await target.vaultService.getItem(itemId)).password,
        'new-password',
      );
      final history = await target.vaultService.listPasswordHistory(itemId);
      expect(
        history.map((entry) => entry['password']),
        contains('old-password'),
      );
    },
  );

  test('item backup preserves selected item password history', () async {
    final source = await _buildHarness();
    await source.vaultService.createVault(masterPassword: 'source-master');
    await source.vaultService.unlock(masterPassword: 'source-master');
    final itemId = await source.vaultService.createItem(
      PasswordEntry(
        title: 'Docs',
        website: 'https://docs.example',
        username: 'docs@example.com',
        password: 'old-password',
        notes: 'item backup',
        tags: ['docs'],
      ),
    );
    await source.vaultService.updateItem(
      itemId,
      PasswordEntry(
        title: 'Docs',
        website: 'https://docs.example',
        username: 'docs@example.com',
        password: 'new-password',
        notes: 'item backup',
        tags: ['docs'],
      ),
    );
    final unrelatedId = await source.vaultService.createItem(
      PasswordEntry(
        title: 'Mail',
        website: 'https://mail.example',
        username: 'mail@example.com',
        password: 'mail-old',
        notes: 'unrelated history',
        tags: ['mail'],
      ),
    );
    await source.vaultService.updateItem(
      unrelatedId,
      PasswordEntry(
        title: 'Mail',
        website: 'https://mail.example',
        username: 'mail@example.com',
        password: 'mail-new',
        notes: 'unrelated history',
        tags: ['mail'],
      ),
    );
    final itemBackup = await source.backupService.exportItemBackup(itemId);

    final target = await _buildHarness();
    await target.backupService.importBackup(
      json: itemBackup.toJson(),
      masterPassword: 'source-master',
      mode: BackupImportMode.skip,
    );
    await target.vaultService.unlock(masterPassword: 'source-master');

    expect(
      (await target.vaultService.getItem(itemId)).password,
      'new-password',
    );
    final history = await target.vaultService.listPasswordHistory(itemId);
    expect(history.map((entry) => entry['password']), contains('old-password'));
    await expectLater(
      target.vaultService.getItem(unrelatedId),
      throwsA(isA<VaultItemNotFoundException>()),
    );
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

  test(
    'importBackup merge preserves local password history for duplicates',
    () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final sourceId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'Imported',
          website: 'https://imported.example',
          username: 'imported@example.com',
          password: 'imported-password',
          notes: 'incoming duplicate',
          tags: const ['backup'],
        ),
      );
      final backup = await source.backupService.exportBackup();

      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'target-master');
      await target.vaultService.unlock(masterPassword: 'target-master');
      final localId = await target.vaultService.createItem(
        PasswordEntry(
          title: 'Local',
          website: 'https://local.example',
          username: 'local@example.com',
          password: 'local-old-password',
          notes: 'local duplicate',
          tags: const ['local'],
        ),
      );
      await target.vaultService.updateItem(
        localId,
        PasswordEntry(
          title: 'Local',
          website: 'https://local.example',
          username: 'local@example.com',
          password: 'local-new-password',
          notes: 'local duplicate',
          tags: const ['local'],
        ),
      );
      final importedJson = _backupJsonWithItemIdReplacement(
        backup: backup,
        fromId: sourceId,
        toId: localId,
      );

      await target.backupService.importBackup(
        json: importedJson,
        masterPassword: 'source-master',
        mode: BackupImportMode.merge,
        allowLegacyBackups: true,
      );

      final imported = await target.vaultService.getItem(localId);
      final history = await target.vaultService.listPasswordHistory(localId);
      expect(imported.password, 'imported-password');
      expect(
        history.map((entry) => entry['password']),
        contains('local-old-password'),
      );
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
      final originalMeta = await _enableBiometricMeta(
        target,
        masterPassword: 'target-master',
      );
      final importedJson = _backupJsonWithItemIdReplacement(
        backup: exportedBackup,
        fromId: sharedSourceId,
        toId: sharedId,
      );

      final importedCount = await target.backupService.importBackup(
        json: importedJson,
        masterPassword: 'source-master',
        mode: BackupImportMode.merge,
        allowLegacyBackups: true,
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
    'importBackup skip with a different envelope requires unlock even as a no-op',
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

      await expectLater(
        target.backupService.importBackup(
          json: importedJson,
          masterPassword: 'source-master',
          mode: BackupImportMode.skip,
          allowLegacyBackups: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('must already be unlocked'),
          ),
        ),
      );
      await target.vaultService.unlock(masterPassword: 'target-master');
      final preserved = await target.vaultService.getItem(sharedId);
      expect(preserved.password, 'local-password');
      expect(preserved.notes, 'local copy');
    },
  );

  test('importBackup skip no-op rejects target rollback', () async {
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
        tags: const ['dev'],
      ),
    );
    final backup = await source.backupService.exportBackup();

    final target = await _buildHarness();
    await target.backupService.importBackup(
      json: backup.toJson(),
      masterPassword: 'source-master',
      mode: BackupImportMode.overwrite,
    );
    final targetMeta = await target.repository.metaDao.get();
    final targetManifest = await target.repository.manifestDao.get();
    await VaultAnchorService(store: target.anchorStore).writeAcceptedManifest(
      vaultId: targetMeta!.id,
      manifest: targetManifest!.copyWith(counter: targetManifest.counter + 2),
      updatedAt: targetManifest.updatedAt + 2,
    );
    target.vaultService.lock();

    await expectLater(
      target.backupService.importBackup(
        json: backup.toJson(),
        masterPassword: 'source-master',
        mode: BackupImportMode.skip,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

  test('unlocked skip no-op rejects tampered target items', () async {
    final source = await _buildHarness();
    await source.vaultService.createVault(masterPassword: 'source-master');
    await source.vaultService.unlock(masterPassword: 'source-master');
    final sourceId = await source.vaultService.createItem(
      PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: 'private note',
        tags: const ['dev'],
      ),
    );
    final backup = await source.backupService.exportBackup();

    final target = await _buildHarness();
    await target.backupService.importBackup(
      json: backup.toJson(),
      masterPassword: 'source-master',
      mode: BackupImportMode.overwrite,
    );
    await target.vaultService.unlock(masterPassword: 'source-master');
    await target.repository.itemsDao.executor.update(
      'vault_items',
      {'ciphertext': _tamperBase64(backup.items.single.ciphertext)},
      where: 'id = ?',
      whereArgs: [sourceId],
    );

    await expectLater(
      target.backupService.importBackup(
        json: backup.toJson(),
        masterPassword: 'source-master',
        mode: BackupImportMode.skip,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
    expect(target.vaultService.isUnlocked, isFalse);
  });

  test('locked skip no-op rejects tampered target items', () async {
    final source = await _buildHarness();
    await source.vaultService.createVault(masterPassword: 'source-master');
    await source.vaultService.unlock(masterPassword: 'source-master');
    final sourceId = await source.vaultService.createItem(
      PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: 'private note',
        tags: const ['dev'],
      ),
    );
    final backup = await source.backupService.exportBackup();

    final target = await _buildHarness();
    await target.backupService.importBackup(
      json: backup.toJson(),
      masterPassword: 'source-master',
      mode: BackupImportMode.overwrite,
    );
    await target.repository.itemsDao.executor.update(
      'vault_items',
      {'ciphertext': _tamperBase64(backup.items.single.ciphertext)},
      where: 'id = ?',
      whereArgs: [sourceId],
    );
    target.vaultService.lock();

    await expectLater(
      target.backupService.importBackup(
        json: backup.toJson(),
        masterPassword: 'source-master',
        mode: BackupImportMode.skip,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

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

  test('full backup overwrite restores encrypted password history', () async {
    final source = await _buildHarness();
    await source.vaultService.createVault(masterPassword: 'source-master');
    await source.vaultService.unlock(masterPassword: 'source-master');
    final itemId = await source.vaultService.createItem(
      PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'old-password',
        notes: 'with history',
        tags: const ['dev'],
      ),
    );
    await source.vaultService.updateItem(
      itemId,
      PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'new-password',
        notes: 'with history',
        tags: const ['dev'],
      ),
    );
    final backup = await source.backupService.exportBackup();
    expect(jsonEncode(backup.toJson()), isNot(contains('old-password')));

    final target = await _buildHarness();
    await target.backupService.importBackup(
      json: backup.toJson(),
      masterPassword: 'source-master',
      mode: BackupImportMode.overwrite,
    );
    await target.vaultService.unlock(masterPassword: 'source-master');

    final history = await target.vaultService.listPasswordHistory(itemId);
    expect(history.map((entry) => entry['password']), contains('old-password'));
  });
}

Map<String, Object?> _backupJsonWithItemIdReplacement({
  required VaultBackup backup,
  required String fromId,
  required String toId,
}) {
  final json = _asLegacyBackupJson(backup.toJson());
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

Map<String, Object?> _asLegacyBackupJson(Map<String, Object?> json) {
  final legacy = Map<String, Object?>.from(json);
  legacy['version'] = 1;
  legacy.remove('magic');
  legacy.remove('created_at');
  legacy.remove('item_count');
  legacy.remove('vault_id');
  legacy.remove('vault_created_at');
  legacy.remove('vault_updated_at');
  legacy.remove('biometric_enabled');
  legacy.remove('encrypted_dek_by_biometric');
  legacy.remove('encrypted_dek_by_biometric_nonce');
  legacy.remove('encrypted_dek_by_biometric_mac');
  legacy.remove('manifest');
  return legacy;
}

String _tamperBase64(String value) {
  final bytes = fromB64(value);
  bytes[bytes.length - 1] = bytes.last ^ 0x01;
  return b64(bytes);
}

Future<VaultMeta> _enableBiometricMeta(
  _BackupHarness harness, {
  required String masterPassword,
}) async {
  final biometricService = BiometricService(
    authenticator: FakeBiometricAuthenticator(
      canAuthenticate: true,
      succeeds: true,
    ),
    store: MemorySecureDekStore(),
  );
  await harness.vaultService.enableBiometricUnlock(
    masterPassword: masterPassword,
    biometricService: biometricService,
  );
  return (await harness.repository.metaDao.get())!;
}

Future<void> _createEmptyArgon2idVault(
  _BackupHarness harness, {
  required String masterPassword,
}) async {
  final random = SecureRandom();
  final crypto = CryptoService(random: random);
  final kdf = KdfService();
  final salt = random.bytes(16);
  final dek = random.bytes(32);
  final params = KdfParams.argon2id(
    memoryKiB: 1024,
    iterations: 3,
    parallelism: 1,
    bits: 256,
  );
  final kek = await kdf.deriveKey(
    password: masterPassword,
    salt: salt,
    params: params,
  );
  final wrappedDek = await crypto.encryptBytes(key: kek, plaintext: dek);
  final now = DateTime.utc(2026, 5, 15).millisecondsSinceEpoch;

  final meta = VaultMeta(
    id: 'argon-vault',
    version: 1,
    kdf: params.name,
    kdfParams: params,
    salt: b64(salt),
    encryptedDekByMaster: b64(wrappedDek.ciphertext),
    encryptedDekByMasterNonce: b64(wrappedDek.nonce),
    encryptedDekByMasterMac: b64(wrappedDek.mac),
    biometricEnabled: false,
    createdAt: now,
    updatedAt: now,
  );
  final manifest = await VaultManifestService(crypto: crypto).createManifest(
    dek: dek,
    meta: meta,
    items: const [],
    previous: null,
    updatedAt: now,
  );

  await harness.repository.transaction((txn) async {
    await txn.metaDao.save(meta);
    await txn.manifestDao.save(manifest);
  });
  await harness.vaultService.acceptManifestForCurrentState(
    meta: meta,
    manifest: manifest,
  );
}

void _expectMetaPreserved(VaultMeta actual, VaultMeta expected) {
  expect(actual.id, expected.id);
  expect(actual.version, expected.version);
  expect(actual.kdf, expected.kdf);
  expect(actual.kdfParams.name, expected.kdfParams.name);
  expect(actual.kdfParams.iterations, expected.kdfParams.iterations);
  expect(actual.kdfParams.bits, expected.kdfParams.bits);
  expect(actual.kdfParams.memoryKiB, expected.kdfParams.memoryKiB);
  expect(actual.kdfParams.parallelism, expected.kdfParams.parallelism);
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
    manifestDao: VaultManifestDao(db),
    settingsDao: SettingsDao(db),
    historyDao: PasswordHistoryDao(db),
  );
  final anchorStore = MemoryVaultAnchorStore();
  final vaultService = VaultService(
    repository: repository,
    random: SecureRandom(),
    kdf: KdfService(),
    crypto: CryptoService(random: SecureRandom()),
    anchorService: VaultAnchorService(store: anchorStore),
  );

  return _BackupHarness(
    repository: repository,
    vaultService: vaultService,
    anchorStore: anchorStore,
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
    required this.anchorStore,
    required this.backupService,
  });

  final VaultRepository repository;
  final VaultService vaultService;
  final MemoryVaultAnchorStore anchorStore;
  final BackupService backupService;
}
