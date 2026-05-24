import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/sync_state_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'current schema creates sync state tables without plaintext fields',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);

      expect(await db.getVersion(), AppDatabase.schemaVersion);

      final stateColumns = await db.rawQuery('PRAGMA table_info(sync_state)');
      final itemColumns = await db.rawQuery(
        'PRAGMA table_info(sync_item_state)',
      );
      final conflictColumns = await db.rawQuery(
        'PRAGMA table_info(sync_conflicts)',
      );
      final blobStateColumns = await db.rawQuery(
        'PRAGMA table_info(sync_blob_state)',
      );
      final blobConflictColumns = await db.rawQuery(
        'PRAGMA table_info(sync_blob_conflicts)',
      );

      expect(
        stateColumns.map((column) => column['name']),
        containsAll(['key', 'value']),
      );
      expect(
        itemColumns.map((column) => column['name']),
        containsAll(['item_id', 'server_revision', 'server_updated_at']),
      );
      expect(
        conflictColumns.map((column) => column['name']),
        containsAll([
          'item_id',
          'client_revision',
          'server_revision',
          'remote_payload',
          'created_at',
        ]),
      );
      expect(
        blobStateColumns.map((column) => column['name']),
        containsAll(['blob_id', 'server_revision', 'server_updated_at']),
      );
      expect(
        blobConflictColumns.map((column) => column['name']),
        containsAll([
          'blob_id',
          'client_revision',
          'server_revision',
          'remote_payload',
          'created_at',
        ]),
      );
      expect(
        _allColumnNames([
          stateColumns,
          itemColumns,
          conflictColumns,
          blobStateColumns,
          blobConflictColumns,
        ]),
        isNot(contains('password')),
      );
      expect(
        _allColumnNames([
          stateColumns,
          itemColumns,
          conflictColumns,
          blobStateColumns,
          blobConflictColumns,
        ]),
        isNot(contains('master_key')),
      );
      expect(
        _allColumnNames([
          stateColumns,
          itemColumns,
          conflictColumns,
          blobStateColumns,
          blobConflictColumns,
        ]),
        isNot(contains('username')),
      );
      expect(
        _allColumnNames([
          stateColumns,
          itemColumns,
          conflictColumns,
          blobStateColumns,
          blobConflictColumns,
        ]),
        isNot(contains('notes')),
      );
    },
  );

  test('upgrade from schema version 3 creates sync state tables', () async {
    final path = await databaseFactoryFfi.getDatabasesPath();
    final dbPath = '$path/sync_state_migration_test.db';
    await databaseFactoryFfi.deleteDatabase(dbPath);
    addTearDown(() => databaseFactoryFfi.deleteDatabase(dbPath));

    final oldDb = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
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
    expect(await _tableExists(upgradedDb, 'sync_state'), isTrue);
    expect(await _tableExists(upgradedDb, 'sync_item_state'), isTrue);
    expect(await _tableExists(upgradedDb, 'sync_conflicts'), isTrue);
    expect(await _tableExists(upgradedDb, 'sync_blob_state'), isTrue);
    expect(await _tableExists(upgradedDb, 'sync_blob_conflicts'), isTrue);
  });

  test(
    'sync state dao persists cursor, device id, and item revision',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final dao = SyncStateDao(db);

      await dao.setDeviceId('device-1');
      await dao.clearDeviceId();

      expect(await dao.deviceId(), isNull);

      await dao.setDeviceId('device-2');
      await dao.setLastPullCursor('2026-05-23T00:00:00Z');
      await dao.setLastBlobPullCursor('2026-05-23T00:30:00Z');
      await dao.saveItemState(
        const SyncItemState(
          itemId: 'item-1',
          serverRevision: 7,
          serverUpdatedAt: '2026-05-23T00:00:00Z',
        ),
      );
      await dao.saveBlobState(
        const SyncBlobState(
          blobId: 'blob-1',
          serverRevision: 3,
          serverUpdatedAt: '2026-05-23T00:30:00Z',
        ),
      );

      expect(await dao.deviceId(), 'device-2');
      expect(await dao.lastPullCursor(), '2026-05-23T00:00:00Z');
      expect(await dao.lastBlobPullCursor(), '2026-05-23T00:30:00Z');
      expect(
        await dao.itemState('item-1'),
        const SyncItemState(
          itemId: 'item-1',
          serverRevision: 7,
          serverUpdatedAt: '2026-05-23T00:00:00Z',
        ),
      );
      expect(await dao.itemState('missing'), isNull);
      expect(
        await dao.blobState('blob-1'),
        const SyncBlobState(
          blobId: 'blob-1',
          serverRevision: 3,
          serverUpdatedAt: '2026-05-23T00:30:00Z',
        ),
      );
      expect(await dao.blobState('missing'), isNull);
    },
  );

  test('sync conflict records can be retained and cleared', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = SyncStateDao(db);
    final conflict = SyncConflictRecord(
      itemId: 'item-1',
      clientRevision: 3,
      serverRevision: 4,
      remotePayload: '{"item_id":"item-1","ciphertext":"remote-ciphertext"}',
      createdAt: 1779465600000,
    );

    await dao.saveConflict(conflict);
    await dao.saveConflict(conflict.copyWith(serverRevision: 5));

    expect(await dao.conflicts(), [conflict.copyWith(serverRevision: 5)]);

    await dao.clearConflict('item-1');

    expect(await dao.conflicts(), isEmpty);
  });

  test('sync blob conflict records can be retained and cleared', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = SyncStateDao(db);
    final conflict = SyncBlobConflictRecord(
      blobId: 'blob-1',
      clientRevision: 3,
      serverRevision: 4,
      remotePayload: '{"blob_id":"blob-1"}',
      createdAt: 1779465600000,
    );

    await dao.saveBlobConflict(conflict);
    await dao.saveBlobConflict(conflict.copyWith(serverRevision: 5));

    expect(await dao.blobConflicts(), [conflict.copyWith(serverRevision: 5)]);

    await dao.clearBlobConflict('blob-1');

    expect(await dao.blobConflicts(), isEmpty);
  });

  test('clearAll removes account-scoped sync state', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = SyncStateDao(db);

    await dao.setDeviceId('device-1');
    await dao.setLastPullCursor('2026-05-23T00:00:00Z');
    await dao.setLastBlobPullCursor('2026-05-23T00:30:00Z');
    await dao.saveItemState(
      const SyncItemState(
        itemId: 'item-1',
        serverRevision: 7,
        serverUpdatedAt: '2026-05-23T00:00:00Z',
      ),
    );
    await dao.saveBlobState(
      const SyncBlobState(
        blobId: 'blob-1',
        serverRevision: 3,
        serverUpdatedAt: '2026-05-23T00:30:00Z',
      ),
    );
    await dao.saveConflict(
      const SyncConflictRecord(
        itemId: 'item-1',
        clientRevision: 7,
        serverRevision: 8,
        remotePayload: '{}',
        createdAt: 1779465600000,
      ),
    );
    await dao.saveBlobConflict(
      const SyncBlobConflictRecord(
        blobId: 'blob-1',
        clientRevision: 3,
        serverRevision: 4,
        remotePayload: '{}',
        createdAt: 1779465600000,
      ),
    );

    await dao.clearAll();

    expect(await dao.deviceId(), isNull);
    expect(await dao.lastPullCursor(), isNull);
    expect(await dao.lastBlobPullCursor(), isNull);
    expect(await dao.itemState('item-1'), isNull);
    expect(await dao.blobState('blob-1'), isNull);
    expect(await dao.conflicts(), isEmpty);
    expect(await dao.blobConflicts(), isEmpty);
  });
}

Set<Object?> _allColumnNames(List<List<Map<String, Object?>>> tables) {
  return {
    for (final table in tables)
      for (final column in table) column['name'],
  };
}

Future<bool> _tableExists(Database db, String tableName) async {
  final rows = await db.query(
    'sqlite_master',
    columns: ['name'],
    where: 'type = ? AND name = ?',
    whereArgs: ['table', tableName],
    limit: 1,
  );
  return rows.isNotEmpty;
}
