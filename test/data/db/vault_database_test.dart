import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_manifest_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:secure_box/data/models/vault_meta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('vault items store only encrypted fields', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultItemsDao(db);
    final now = DateTime.utc(2026, 5, 12).millisecondsSinceEpoch;

    await dao.upsert(
      EncryptedVaultItem(
        id: 'item-1',
        nonce: 'nonce-value',
        ciphertext: 'ciphertext-value',
        mac: 'mac-value',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final rows = await db.query('vault_items');
    expect(
      rows.single.keys,
      containsAll([
        'id',
        'nonce',
        'ciphertext',
        'mac',
        'created_at',
        'updated_at',
        'deleted_at',
      ]),
    );
    expect(rows.single.keys, isNot(contains('password')));
    expect(rows.single.keys, isNot(contains('username')));
    expect(rows.single.keys, isNot(contains('notes')));
    expect(rows.single.keys, isNot(contains('title')));
    expect(rows.single['ciphertext'], 'ciphertext-value');
  });

  test('database enables secure delete for removed vault rows', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);

    final pragmaRows = await db.rawQuery('PRAGMA secure_delete');

    expect(pragmaRows.single.values.single, 1);
  });

  test(
    'database enables foreign key enforcement for cascade deletes',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);

      final pragmaRows = await db.rawQuery('PRAGMA foreign_keys');

      expect(pragmaRows.single.values.single, 1);
    },
  );

  test(
    'current schema creates vault manifest without plaintext fields',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);

      expect(await db.getVersion(), AppDatabase.schemaVersion);

      final columns = await db.rawQuery('PRAGMA table_info(vault_manifest)');
      final columnNames = columns.map((column) => column['name']).toSet();

      expect(
        columnNames,
        containsAll({
          'singleton_key',
          'version',
          'epoch',
          'counter',
          'nonce',
          'ciphertext',
          'mac',
          'updated_at',
        }),
      );
      expect(columnNames, isNot(contains('password')));
      expect(columnNames, isNot(contains('username')));
      expect(columnNames, isNot(contains('notes')));
      expect(columnNames, isNot(contains('title')));
    },
  );

  test('current schema creates vault blobs without plaintext fields', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);

    expect(AppDatabase.schemaVersion, 7);

    final columns = await db.rawQuery('PRAGMA table_info(vault_blobs)');
    final columnNames = columns.map((column) => column['name']).toSet();

    expect(
      columnNames,
      containsAll({
        'blob_id',
        'item_id',
        'metadata_nonce',
        'metadata_ciphertext',
        'metadata_mac',
        'nonce',
        'ciphertext',
        'mac',
        'created_at',
        'updated_at',
        'deleted_at',
      }),
    );
    expect(columnNames, isNot(contains('filename')));
    expect(columnNames, isNot(contains('plaintext')));
    expect(columnNames, isNot(contains('file_bytes')));
    expect(columnNames, isNot(contains('raw_key')));
  });

  test('current schema omits cloud sync state tables', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);

    expect(AppDatabase.schemaVersion, 7);
    expect(await _tableExists(db, 'sync_state'), isFalse);
    expect(await _tableExists(db, 'sync_item_state'), isFalse);
    expect(await _tableExists(db, 'sync_conflicts'), isFalse);
    expect(await _tableExists(db, 'sync_blob_state'), isFalse);
    expect(await _tableExists(db, 'sync_blob_conflicts'), isFalse);
  });

  test('upgrade to schema 7 drops only cloud sync state tables', () async {
    final path = await databaseFactoryFfi.getDatabasesPath();
    final dbPath = '$path/cloud_sync_drop_migration_test.db';
    await databaseFactoryFfi.deleteDatabase(dbPath);
    addTearDown(() => databaseFactoryFfi.deleteDatabase(dbPath));

    final oldDb = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE vault_meta (
              singleton_key INTEGER NOT NULL DEFAULT 1
                CHECK (singleton_key = 1)
                UNIQUE,
              id TEXT PRIMARY KEY,
              version INTEGER NOT NULL,
              kdf TEXT NOT NULL,
              kdf_params TEXT NOT NULL,
              salt TEXT NOT NULL,
              encrypted_dek_by_master TEXT NOT NULL,
              encrypted_dek_by_master_nonce TEXT NOT NULL,
              encrypted_dek_by_master_mac TEXT NOT NULL,
              encrypted_dek_by_biometric TEXT,
              encrypted_dek_by_biometric_nonce TEXT,
              encrypted_dek_by_biometric_mac TEXT,
              biometric_enabled INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE vault_items (
              id TEXT PRIMARY KEY,
              nonce TEXT NOT NULL,
              ciphertext TEXT NOT NULL,
              mac TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE vault_manifest (
              singleton_key INTEGER NOT NULL DEFAULT 1
                CHECK (singleton_key = 1)
                UNIQUE,
              version INTEGER NOT NULL,
              epoch INTEGER NOT NULL,
              counter INTEGER NOT NULL,
              nonce TEXT NOT NULL,
              ciphertext TEXT NOT NULL,
              mac TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE password_history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              entry_id TEXT NOT NULL,
              encrypted_password TEXT NOT NULL,
              password_nonce TEXT NOT NULL,
              password_mac TEXT NOT NULL,
              recorded_at INTEGER NOT NULL,
              FOREIGN KEY (entry_id) REFERENCES vault_items(id)
                ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE vault_blobs (
              blob_id TEXT PRIMARY KEY,
              item_id TEXT NOT NULL,
              metadata_nonce TEXT NOT NULL,
              metadata_ciphertext TEXT NOT NULL,
              metadata_mac TEXT NOT NULL,
              nonce TEXT NOT NULL,
              ciphertext TEXT NOT NULL,
              mac TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              FOREIGN KEY (item_id) REFERENCES vault_items(id)
                ON DELETE CASCADE
            )
          ''');
          await db.execute('CREATE TABLE sync_state (id TEXT PRIMARY KEY)');
          await db.execute(
            'CREATE TABLE sync_item_state (item_id TEXT PRIMARY KEY)',
          );
          await db.execute(
            'CREATE TABLE sync_conflicts (item_id TEXT PRIMARY KEY)',
          );
          await db.execute(
            'CREATE TABLE sync_blob_state (blob_id TEXT PRIMARY KEY)',
          );
          await db.execute(
            'CREATE TABLE sync_blob_conflicts (blob_id TEXT PRIMARY KEY)',
          );
          await db.insert('settings', {
            'key': 'clipboard_clear_seconds',
            'value': '45',
          });
          await db.insert('vault_meta', {
            'singleton_key': 1,
            'id': 'vault-v6',
            'version': 1,
            'kdf': 'pbkdf2-hmac-sha256',
            'kdf_params': '{"iterations":120000,"bits":256}',
            'salt': 'legacy-salt',
            'encrypted_dek_by_master': 'legacy-master-dek',
            'encrypted_dek_by_master_nonce': 'legacy-master-nonce',
            'encrypted_dek_by_master_mac': 'legacy-master-mac',
            'encrypted_dek_by_biometric': 'legacy-biometric-dek',
            'encrypted_dek_by_biometric_nonce': 'legacy-biometric-nonce',
            'encrypted_dek_by_biometric_mac': 'legacy-biometric-mac',
            'biometric_enabled': 1,
            'created_at': 1747000000000,
            'updated_at': 1747000001111,
          });
          await db.insert('vault_items', {
            'id': 'item-v6',
            'nonce': 'item-nonce',
            'ciphertext': 'item-ciphertext',
            'mac': 'item-mac',
            'created_at': 1747000002222,
            'updated_at': 1747000003333,
            'deleted_at': null,
          });
          await db.insert('vault_manifest', {
            'singleton_key': 1,
            'version': 1,
            'epoch': 2,
            'counter': 3,
            'nonce': 'manifest-nonce',
            'ciphertext': 'manifest-ciphertext',
            'mac': 'manifest-mac',
            'updated_at': 1747000004444,
          });
          await db.insert('password_history', {
            'entry_id': 'item-v6',
            'encrypted_password': 'history-ciphertext',
            'password_nonce': 'history-nonce',
            'password_mac': 'history-mac',
            'recorded_at': 1747000005555,
          });
          await db.insert('vault_blobs', {
            'blob_id': 'blob-v6',
            'item_id': 'item-v6',
            'metadata_nonce': 'metadata-nonce',
            'metadata_ciphertext': 'metadata-ciphertext',
            'metadata_mac': 'metadata-mac',
            'nonce': 'blob-nonce',
            'ciphertext': 'blob-ciphertext',
            'mac': 'blob-mac',
            'created_at': 1747000006666,
            'updated_at': 1747000007777,
            'deleted_at': null,
          });
          await db.insert('sync_state', {'id': 'sync-state-v6'});
          await db.insert('sync_item_state', {'item_id': 'item-v6'});
          await db.insert('sync_conflicts', {'item_id': 'item-v6'});
          await db.insert('sync_blob_state', {'blob_id': 'blob-v6'});
          await db.insert('sync_blob_conflicts', {'blob_id': 'blob-v6'});
        },
      ),
    );
    await oldDb.close();

    final upgradedDb = await AppDatabase.open(dbPath);
    addTearDown(upgradedDb.close);

    expect(await upgradedDb.getVersion(), AppDatabase.schemaVersion);
    expect(await _tableExists(upgradedDb, 'settings'), isTrue);
    expect(await _tableExists(upgradedDb, 'vault_items'), isTrue);
    expect(await _tableExists(upgradedDb, 'vault_manifest'), isTrue);
    expect(await _tableExists(upgradedDb, 'vault_meta'), isTrue);
    expect(await _tableExists(upgradedDb, 'password_history'), isTrue);
    expect(await _tableExists(upgradedDb, 'vault_blobs'), isTrue);

    expect((await upgradedDb.query('settings')).single, {
      'key': 'clipboard_clear_seconds',
      'value': '45',
    });
    expect((await upgradedDb.query('vault_meta')).single['id'], 'vault-v6');
    expect(
      (await upgradedDb.query('vault_items')).single['ciphertext'],
      'item-ciphertext',
    );
    expect(
      (await upgradedDb.query('vault_manifest')).single['ciphertext'],
      'manifest-ciphertext',
    );
    expect(
      (await upgradedDb.query('password_history')).single['encrypted_password'],
      'history-ciphertext',
    );
    expect(
      (await upgradedDb.query('vault_blobs')).single['ciphertext'],
      'blob-ciphertext',
    );
    expect(await _tableExists(upgradedDb, 'sync_state'), isFalse);
    expect(await _tableExists(upgradedDb, 'sync_item_state'), isFalse);
    expect(await _tableExists(upgradedDb, 'sync_conflicts'), isFalse);
    expect(await _tableExists(upgradedDb, 'sync_blob_state'), isFalse);
    expect(await _tableExists(upgradedDb, 'sync_blob_conflicts'), isFalse);
  });

  test('vault manifest dao stores exactly one singleton row', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultManifestDao(db);

    await dao.save(
      VaultManifest(
        version: 1,
        epoch: 1,
        counter: 1,
        nonce: 'nonce-a',
        ciphertext: 'ciphertext-a',
        mac: 'mac-a',
        updatedAt: 1747000000000,
      ),
    );
    await dao.save(
      VaultManifest(
        version: 1,
        epoch: 1,
        counter: 2,
        nonce: 'nonce-b',
        ciphertext: 'ciphertext-b',
        mac: 'mac-b',
        updatedAt: 1747000001111,
      ),
    );

    final rows = await db.query('vault_manifest');
    final manifest = await dao.get();

    expect(rows, hasLength(1));
    expect(manifest, isNotNull);
    expect(manifest!.counter, 2);
    expect(manifest.ciphertext, 'ciphertext-b');
  });

  test('upgrade from schema version 1 creates vault manifest table', () async {
    final path = await databaseFactoryFfi.getDatabasesPath();
    final dbPath = '$path/vault_manifest_migration_test.db';
    await databaseFactoryFfi.deleteDatabase(dbPath);
    addTearDown(() => databaseFactoryFfi.deleteDatabase(dbPath));

    final oldDb = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    await oldDb.close();

    final upgradedDb = await AppDatabase.open(dbPath);
    addTearDown(upgradedDb.close);

    expect(await upgradedDb.getVersion(), AppDatabase.schemaVersion);
    final columns = await upgradedDb.rawQuery(
      'PRAGMA table_info(vault_manifest)',
    );
    expect(columns.map((column) => column['name']), contains('ciphertext'));
  });

  test('vault items can be read, filtered, and soft-deleted', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultItemsDao(db);
    final createdAt = DateTime.utc(2026, 5, 12).millisecondsSinceEpoch;
    final deletedAt = createdAt + 1000;

    final activeItem = EncryptedVaultItem(
      id: 'active-item',
      nonce: 'active-nonce',
      ciphertext: 'active-ciphertext',
      mac: 'active-mac',
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final deletedItem = EncryptedVaultItem(
      id: 'deleted-item',
      nonce: 'deleted-nonce',
      ciphertext: 'deleted-ciphertext',
      mac: 'deleted-mac',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await dao.upsert(activeItem);
    await dao.upsert(deletedItem);

    expect(await dao.byId(activeItem.id), isNotNull);
    expect(await dao.byId('missing-item'), isNull);

    await dao.softDelete(deletedItem.id, deletedAt);

    final activeItems = await dao.activeItems();
    final storedDeletedItem = await dao.byId(deletedItem.id);

    expect(activeItems.map((item) => item.id), [activeItem.id]);
    expect(storedDeletedItem?.deletedAt, deletedAt);
    expect(storedDeletedItem?.updatedAt, deletedAt);
  });

  test('daos can be used inside a database transaction', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final item = EncryptedVaultItem(
      id: 'txn-item',
      nonce: 'txn-nonce',
      ciphertext: 'txn-ciphertext',
      mac: 'txn-mac',
      createdAt: 1747000000000,
      updatedAt: 1747000000000,
    );
    final meta = _buildVaultMeta(
      biometricEnabled: false,
      encryptedDekByBiometric: null,
      encryptedDekByBiometricNonce: null,
      encryptedDekByBiometricMac: null,
    );

    await db.transaction((txn) async {
      await SettingsDao(txn).setValue('clipboard_clear_seconds', '45');
      await VaultMetaDao(txn).save(meta);
      await VaultItemsDao(txn).upsert(item);
    });

    expect(await SettingsDao(db).getValue('clipboard_clear_seconds'), '45');
    expect((await VaultMetaDao(db).get())!.toDb(), meta.toDb());
    expect((await VaultItemsDao(db).byId(item.id))!.toDb(), item.toDb());
  });

  test(
    'repository transaction wires vault manifest dao to transaction',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final repository = VaultRepository(
        metaDao: VaultMetaDao(db),
        itemsDao: VaultItemsDao(db),
        manifestDao: VaultManifestDao(db),
        settingsDao: SettingsDao(db),
      );
      final manifest = VaultManifest(
        version: 1,
        epoch: 2,
        counter: 3,
        nonce: 'txn-manifest-nonce',
        ciphertext: 'txn-manifest-ciphertext',
        mac: 'txn-manifest-mac',
        updatedAt: 1747000002222,
      );

      final savedManifest = await repository.transaction((txn) async {
        await txn.manifestDao.save(manifest);
        return txn.manifestDao.get();
      });

      expect(savedManifest, isNotNull);
      expect(savedManifest!.toDb(), manifest.toDb());
      expect((await repository.manifestDao.get())!.toDb(), manifest.toDb());
    },
  );

  test('settings can be saved and read', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = SettingsDao(db);

    await dao.setValue('clipboard_clear_seconds', '30');

    expect(await dao.getValue('clipboard_clear_seconds'), '30');
    expect(await dao.getValue('missing-key'), isNull);
  });

  test('vault meta can be saved and read', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultMetaDao(db);
    final meta = _buildVaultMeta(
      biometricEnabled: true,
      encryptedDekByBiometric: null,
      encryptedDekByBiometricNonce: null,
      encryptedDekByBiometricMac: null,
    );

    await dao.save(meta);

    expect(await dao.get(), isNotNull);
    expect((await dao.get())!.toDb(), meta.toDb());
  });

  test('vault meta save preserves a single persisted row', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultMetaDao(db);
    final firstMeta = _buildVaultMeta(
      id: 'vault-1',
      biometricEnabled: false,
      encryptedDekByBiometric: null,
      encryptedDekByBiometricNonce: null,
      encryptedDekByBiometricMac: null,
      updatedAt: 1747000000000,
    );
    final secondMeta = _buildVaultMeta(
      id: 'vault-2',
      biometricEnabled: true,
      encryptedDekByBiometric: null,
      encryptedDekByBiometricNonce: null,
      encryptedDekByBiometricMac: null,
      updatedAt: 1747000001111,
    );

    await dao.save(firstMeta);
    await dao.save(secondMeta);

    final rows = await db.query('vault_meta');
    final storedMeta = await dao.get();

    expect(rows, hasLength(1));
    expect(storedMeta, isNotNull);
    expect(storedMeta!.toDb(), secondMeta.toDb());
  });

  test(
    'vault meta table rejects a second row outside dao replace semantics',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final firstMeta = _buildVaultMeta(
        id: 'vault-1',
        biometricEnabled: false,
        encryptedDekByBiometric: null,
        encryptedDekByBiometricNonce: null,
        encryptedDekByBiometricMac: null,
      );
      final secondMeta = _buildVaultMeta(
        id: 'vault-2',
        biometricEnabled: false,
        encryptedDekByBiometric: null,
        encryptedDekByBiometricNonce: null,
        encryptedDekByBiometricMac: null,
      );

      await db.insert('vault_meta', firstMeta.toDb());

      expect(
        () => db.insert('vault_meta', secondMeta.toDb()),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('vault_meta'), hasLength(1));
    },
  );

  test(
    'vault meta save scrubs disabled legacy biometric tuple columns',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final dao = VaultMetaDao(db);
      final meta = _buildVaultMeta(
        biometricEnabled: false,
        encryptedDekByBiometric: 'stale-biometric-dek',
        encryptedDekByBiometricNonce: 'stale-biometric-nonce',
        encryptedDekByBiometricMac: 'stale-biometric-mac',
      );

      await dao.save(meta);

      final row = (await db.query('vault_meta')).single;
      final storedMeta = await dao.get();

      expect(row['biometric_enabled'], 0);
      expect(row['encrypted_dek_by_biometric'], isNull);
      expect(row['encrypted_dek_by_biometric_nonce'], isNull);
      expect(row['encrypted_dek_by_biometric_mac'], isNull);
      expect(storedMeta, isNotNull);
      expect(storedMeta!.biometricEnabled, isFalse);
      expect(storedMeta.encryptedDekByBiometric, isNull);
      expect(storedMeta.encryptedDekByBiometricNonce, isNull);
      expect(storedMeta.encryptedDekByBiometricMac, isNull);
    },
  );

  test('clearing biometric DEK disables biometric unlock state', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultMetaDao(db);
    final initialMeta = _buildVaultMeta(
      biometricEnabled: true,
      encryptedDekByBiometric: 'encrypted-biometric-dek',
      encryptedDekByBiometricNonce: 'biometric-nonce',
      encryptedDekByBiometricMac: 'biometric-mac',
      updatedAt: 1747000000000,
    );
    final clearedAt = 1747000009999;

    await dao.save(initialMeta);
    await dao.clearBiometricDek(clearedAt);

    final clearedMeta = await dao.get();

    expect(clearedMeta, isNotNull);
    expect(clearedMeta!.biometricEnabled, isFalse);
    expect(clearedMeta.encryptedDekByBiometric, isNull);
    expect(clearedMeta.encryptedDekByBiometricNonce, isNull);
    expect(clearedMeta.encryptedDekByBiometricMac, isNull);
    expect(clearedMeta.updatedAt, clearedAt);
    expect(clearedMeta.encryptedDekByMaster, initialMeta.encryptedDekByMaster);
  });

  test(
    'clearing biometric DEK also works when biometric is enabled without legacy tuple columns',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final dao = VaultMetaDao(db);
      final initialMeta = _buildVaultMeta(
        biometricEnabled: true,
        encryptedDekByBiometric: null,
        encryptedDekByBiometricNonce: null,
        encryptedDekByBiometricMac: null,
        updatedAt: 1747000000000,
      );
      final clearedAt = 1747000011111;

      await dao.save(initialMeta);
      await dao.clearBiometricDek(clearedAt);

      final clearedMeta = await dao.get();

      expect(clearedMeta, isNotNull);
      expect(clearedMeta!.biometricEnabled, isFalse);
      expect(clearedMeta.encryptedDekByBiometric, isNull);
      expect(clearedMeta.encryptedDekByBiometricNonce, isNull);
      expect(clearedMeta.encryptedDekByBiometricMac, isNull);
      expect(clearedMeta.updatedAt, clearedAt);
    },
  );

  test('soft delete requires an existing item row', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultItemsDao(db);

    expect(
      () => dao.softDelete('missing-item', 1747000009999),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('vault_items'),
        ),
      ),
    );
  });

  test('soft delete fails when the item is already deleted', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultItemsDao(db);
    final createdAt = DateTime.utc(2026, 5, 12).millisecondsSinceEpoch;
    final firstDeletedAt = createdAt + 1000;
    final secondDeletedAt = createdAt + 2000;
    final item = EncryptedVaultItem(
      id: 'deleted-once',
      nonce: 'nonce-value',
      ciphertext: 'ciphertext-value',
      mac: 'mac-value',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await dao.upsert(item);
    await dao.softDelete(item.id, firstDeletedAt);

    expect(
      () => dao.softDelete(item.id, secondDeletedAt),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('vault_items'),
        ),
      ),
    );
  });

  test('clearing biometric DEK requires an existing singleton row', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultMetaDao(db);

    expect(
      () => dao.clearBiometricDek(1747000009999),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('vault_meta'),
        ),
      ),
    );
  });

  test(
    'clearing biometric DEK fails when biometric unlock is already cleared',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final dao = VaultMetaDao(db);
      final meta = _buildVaultMeta(
        biometricEnabled: true,
        encryptedDekByBiometric: 'encrypted-biometric-dek',
        encryptedDekByBiometricNonce: 'biometric-nonce',
        encryptedDekByBiometricMac: 'biometric-mac',
        updatedAt: 1747000000000,
      );

      await dao.save(meta);
      await dao.clearBiometricDek(1747000001111);

      expect(
        () => dao.clearBiometricDek(1747000002222),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('vault_meta'),
          ),
        ),
      );
    },
  );
}

Future<bool> _tableExists(Database db, String tableName) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [tableName],
  );
  return rows.isNotEmpty;
}

VaultMeta _buildVaultMeta({
  String id = 'vault-1',
  required bool biometricEnabled,
  required String? encryptedDekByBiometric,
  required String? encryptedDekByBiometricNonce,
  required String? encryptedDekByBiometricMac,
  int createdAt = 1747000000000,
  int updatedAt = 1747000000000,
}) {
  return VaultMeta(
    id: id,
    version: 1,
    kdf: 'pbkdf2-hmac-sha256',
    kdfParams: KdfParams.pbkdf2(iterations: 120000, bits: 256),
    salt: 'base64-salt',
    encryptedDekByMaster: 'encrypted-master-dek',
    encryptedDekByMasterNonce: 'master-nonce',
    encryptedDekByMasterMac: 'master-mac',
    biometricEnabled: biometricEnabled,
    createdAt: createdAt,
    updatedAt: updatedAt,
    encryptedDekByBiometric: encryptedDekByBiometric,
    encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
    encryptedDekByBiometricMac: encryptedDekByBiometricMac,
  );
}
