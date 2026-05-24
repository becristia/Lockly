import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, DatabaseExecutor;

class SyncStateDao {
  SyncStateDao(this._db);

  static const _deviceIdKey = 'device_id';
  static const _lastPullCursorKey = 'last_pull_cursor';
  static const _lastBlobPullCursorKey = 'last_blob_pull_cursor';

  final DatabaseExecutor _db;

  Future<String?> deviceId() {
    return _stringValue(_deviceIdKey);
  }

  Future<void> setDeviceId(String deviceId) {
    return _setValue(_deviceIdKey, deviceId);
  }

  Future<void> clearDeviceId() {
    return _db.delete(
      'sync_state',
      where: 'key = ?',
      whereArgs: [_deviceIdKey],
    );
  }

  Future<void> clearAll() async {
    await _db.delete('sync_state');
    await _db.delete('sync_item_state');
    await _db.delete('sync_conflicts');
    await _db.delete('sync_blob_state');
    await _db.delete('sync_blob_conflicts');
  }

  Future<String?> lastPullCursor() {
    return _stringValue(_lastPullCursorKey);
  }

  Future<void> setLastPullCursor(String cursor) {
    if (cursor.isEmpty) {
      throw ArgumentError.value(cursor, 'cursor', 'must not be empty');
    }
    return _setValue(_lastPullCursorKey, cursor);
  }

  Future<SyncItemState?> itemState(String itemId) async {
    final rows = await _db.query(
      'sync_item_state',
      where: 'item_id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return SyncItemState.fromDb(rows.single);
  }

  Future<void> saveItemState(SyncItemState state) async {
    await _db.insert(
      'sync_item_state',
      state.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SyncConflictRecord>> conflicts() async {
    final rows = await _db.query('sync_conflicts', orderBy: 'created_at ASC');
    return rows.map(SyncConflictRecord.fromDb).toList(growable: false);
  }

  Future<void> saveConflict(SyncConflictRecord conflict) async {
    await _db.insert(
      'sync_conflicts',
      conflict.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearConflict(String itemId) async {
    await _db.delete(
      'sync_conflicts',
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
  }

  Future<String?> lastBlobPullCursor() {
    return _stringValue(_lastBlobPullCursorKey);
  }

  Future<void> setLastBlobPullCursor(String cursor) {
    if (cursor.isEmpty) {
      throw ArgumentError.value(cursor, 'cursor', 'must not be empty');
    }
    return _setValue(_lastBlobPullCursorKey, cursor);
  }

  Future<SyncBlobState?> blobState(String blobId) async {
    final rows = await _db.query(
      'sync_blob_state',
      where: 'blob_id = ?',
      whereArgs: [blobId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return SyncBlobState.fromDb(rows.single);
  }

  Future<void> saveBlobState(SyncBlobState state) async {
    await _db.insert(
      'sync_blob_state',
      state.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SyncBlobConflictRecord>> blobConflicts() async {
    final rows = await _db.query(
      'sync_blob_conflicts',
      orderBy: 'created_at ASC',
    );
    return rows.map(SyncBlobConflictRecord.fromDb).toList(growable: false);
  }

  Future<void> saveBlobConflict(SyncBlobConflictRecord conflict) async {
    await _db.insert(
      'sync_blob_conflicts',
      conflict.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearBlobConflict(String blobId) async {
    await _db.delete(
      'sync_blob_conflicts',
      where: 'blob_id = ?',
      whereArgs: [blobId],
    );
  }

  Future<String?> _stringValue(String key) async {
    final rows = await _db.query(
      'sync_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.single['value'] as String;
  }

  Future<void> _setValue(String key, String value) async {
    await _db.insert('sync_state', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

class SyncItemState {
  const SyncItemState({
    required this.itemId,
    required this.serverRevision,
    required this.serverUpdatedAt,
  });

  final String itemId;
  final int serverRevision;
  final String? serverUpdatedAt;

  factory SyncItemState.fromDb(Map<String, Object?> row) {
    return SyncItemState(
      itemId: row['item_id'] as String,
      serverRevision: row['server_revision'] as int,
      serverUpdatedAt: row['server_updated_at'] as String?,
    );
  }

  Map<String, Object?> toDb() {
    return {
      'item_id': itemId,
      'server_revision': serverRevision,
      'server_updated_at': serverUpdatedAt,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is SyncItemState &&
        other.itemId == itemId &&
        other.serverRevision == serverRevision &&
        other.serverUpdatedAt == serverUpdatedAt;
  }

  @override
  int get hashCode => Object.hash(itemId, serverRevision, serverUpdatedAt);
}

class SyncConflictRecord {
  const SyncConflictRecord({
    required this.itemId,
    required this.clientRevision,
    required this.serverRevision,
    required this.remotePayload,
    required this.createdAt,
  });

  final String itemId;
  final int clientRevision;
  final int serverRevision;
  final String remotePayload;
  final int createdAt;

  factory SyncConflictRecord.fromDb(Map<String, Object?> row) {
    return SyncConflictRecord(
      itemId: row['item_id'] as String,
      clientRevision: row['client_revision'] as int,
      serverRevision: row['server_revision'] as int,
      remotePayload: row['remote_payload'] as String,
      createdAt: row['created_at'] as int,
    );
  }

  Map<String, Object?> toDb() {
    return {
      'item_id': itemId,
      'client_revision': clientRevision,
      'server_revision': serverRevision,
      'remote_payload': remotePayload,
      'created_at': createdAt,
    };
  }

  SyncConflictRecord copyWith({
    int? clientRevision,
    int? serverRevision,
    String? remotePayload,
    int? createdAt,
  }) {
    return SyncConflictRecord(
      itemId: itemId,
      clientRevision: clientRevision ?? this.clientRevision,
      serverRevision: serverRevision ?? this.serverRevision,
      remotePayload: remotePayload ?? this.remotePayload,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SyncConflictRecord &&
        other.itemId == itemId &&
        other.clientRevision == clientRevision &&
        other.serverRevision == serverRevision &&
        other.remotePayload == remotePayload &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      itemId,
      clientRevision,
      serverRevision,
      remotePayload,
      createdAt,
    );
  }
}

class SyncBlobState {
  const SyncBlobState({
    required this.blobId,
    required this.serverRevision,
    required this.serverUpdatedAt,
  });

  final String blobId;
  final int serverRevision;
  final String? serverUpdatedAt;

  factory SyncBlobState.fromDb(Map<String, Object?> row) {
    return SyncBlobState(
      blobId: row['blob_id'] as String,
      serverRevision: row['server_revision'] as int,
      serverUpdatedAt: row['server_updated_at'] as String?,
    );
  }

  Map<String, Object?> toDb() {
    return {
      'blob_id': blobId,
      'server_revision': serverRevision,
      'server_updated_at': serverUpdatedAt,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is SyncBlobState &&
        other.blobId == blobId &&
        other.serverRevision == serverRevision &&
        other.serverUpdatedAt == serverUpdatedAt;
  }

  @override
  int get hashCode => Object.hash(blobId, serverRevision, serverUpdatedAt);
}

class SyncBlobConflictRecord {
  const SyncBlobConflictRecord({
    required this.blobId,
    required this.clientRevision,
    required this.serverRevision,
    required this.remotePayload,
    required this.createdAt,
  });

  final String blobId;
  final int clientRevision;
  final int serverRevision;
  final String remotePayload;
  final int createdAt;

  factory SyncBlobConflictRecord.fromDb(Map<String, Object?> row) {
    return SyncBlobConflictRecord(
      blobId: row['blob_id'] as String,
      clientRevision: row['client_revision'] as int,
      serverRevision: row['server_revision'] as int,
      remotePayload: row['remote_payload'] as String,
      createdAt: row['created_at'] as int,
    );
  }

  Map<String, Object?> toDb() {
    return {
      'blob_id': blobId,
      'client_revision': clientRevision,
      'server_revision': serverRevision,
      'remote_payload': remotePayload,
      'created_at': createdAt,
    };
  }

  SyncBlobConflictRecord copyWith({
    int? clientRevision,
    int? serverRevision,
    String? remotePayload,
    int? createdAt,
  }) {
    return SyncBlobConflictRecord(
      blobId: blobId,
      clientRevision: clientRevision ?? this.clientRevision,
      serverRevision: serverRevision ?? this.serverRevision,
      remotePayload: remotePayload ?? this.remotePayload,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SyncBlobConflictRecord &&
        other.blobId == blobId &&
        other.clientRevision == clientRevision &&
        other.serverRevision == serverRevision &&
        other.remotePayload == remotePayload &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      blobId,
      clientRevision,
      serverRevision,
      remotePayload,
      createdAt,
    );
  }
}
