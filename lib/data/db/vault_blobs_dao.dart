import 'package:secure_box/data/models/encrypted_vault_blob.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

class VaultBlobsDao {
  VaultBlobsDao(this._db);

  final DatabaseExecutor _db;

  DatabaseExecutor get executor => _db;

  Future<void> upsert(EncryptedVaultBlob blob) async {
    final affectedRows = await _db.update(
      'vault_blobs',
      blob.toDb(),
      where: 'blob_id = ?',
      whereArgs: [blob.blobId],
    );
    if (affectedRows > 1) {
      throw StateError(
        'Expected to update at most one vault_blobs row for blob_id "${blob.blobId}", but updated $affectedRows rows.',
      );
    }
    if (affectedRows == 0) {
      await _db.insert('vault_blobs', blob.toDb());
    }
  }

  Future<List<EncryptedVaultBlob>> activeByItem(String itemId) async {
    final rows = await _db.query(
      'vault_blobs',
      where: 'item_id = ? AND deleted_at IS NULL',
      whereArgs: [itemId],
      orderBy: 'updated_at DESC, created_at DESC',
    );
    return rows.map(EncryptedVaultBlob.fromDb).toList(growable: false);
  }

  Future<EncryptedVaultBlob?> byBlobId(String blobId) async {
    final rows = await _db.query(
      'vault_blobs',
      where: 'blob_id = ?',
      whereArgs: [blobId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return EncryptedVaultBlob.fromDb(rows.single);
  }

  Future<List<EncryptedVaultBlob>> allForManifest() async {
    final rows = await _db.query('vault_blobs', orderBy: 'blob_id ASC');
    return rows.map(EncryptedVaultBlob.fromDb).toList(growable: false);
  }

  Future<void> softDelete(String blobId, int deletedAt) async {
    final affectedRows = await _db.update(
      'vault_blobs',
      {'updated_at': deletedAt, 'deleted_at': deletedAt},
      where: 'blob_id = ? AND deleted_at IS NULL',
      whereArgs: [blobId],
    );
    if (affectedRows != 1) {
      throw StateError(
        'Expected to soft-delete exactly one vault_blobs row for blob_id "$blobId", but updated $affectedRows rows.',
      );
    }
  }

  Future<void> softDeleteForItem(String itemId, int deletedAt) async {
    await _db.update(
      'vault_blobs',
      {'updated_at': deletedAt, 'deleted_at': deletedAt},
      where: 'item_id = ? AND deleted_at IS NULL',
      whereArgs: [itemId],
    );
  }

  Future<void> restoreForItem(
    String itemId, {
    required int updatedAt,
    int? deletedAt,
  }) async {
    await _db.update(
      'vault_blobs',
      {'updated_at': updatedAt, 'deleted_at': null},
      where: deletedAt == null
          ? 'item_id = ? AND deleted_at IS NOT NULL'
          : 'item_id = ? AND deleted_at = ?',
      whereArgs: deletedAt == null ? [itemId] : [itemId, deletedAt],
    );
  }

  Future<void> hardDelete(String blobId) async {
    await _db.delete('vault_blobs', where: 'blob_id = ?', whereArgs: [blobId]);
  }

  Future<void> hardDeleteForItem(String itemId) async {
    await _db.delete('vault_blobs', where: 'item_id = ?', whereArgs: [itemId]);
  }

  Future<List<Map<String, Object?>>> rawRowsForTest() async {
    return _db.query('vault_blobs');
  }

  Future<void> deleteAll() async {
    await _db.delete('vault_blobs');
  }
}
