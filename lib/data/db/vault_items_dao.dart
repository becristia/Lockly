import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:sqflite/sqflite.dart';

class VaultItemsDao {
  VaultItemsDao(this._db);

  final DatabaseExecutor _db;

  DatabaseExecutor get executor => _db;

  Future<void> upsert(EncryptedVaultItem item) async {
    await _db.insert(
      'vault_items',
      item.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<EncryptedVaultItem>> activeItems() async {
    final rows = await _db.query(
      'vault_items',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC, created_at DESC',
    );

    return rows.map(EncryptedVaultItem.fromDb).toList(growable: false);
  }

  Future<List<EncryptedVaultItem>> allItemsForManifest() async {
    final rows = await _db.query('vault_items', orderBy: 'id ASC');

    return rows.map(EncryptedVaultItem.fromDb).toList(growable: false);
  }

  Future<EncryptedVaultItem?> byId(String id) async {
    final rows = await _db.query(
      'vault_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return EncryptedVaultItem.fromDb(rows.single);
  }

  Future<List<Map<String, Object?>>> rawRowsForTest() async {
    return _db.query('vault_items');
  }

  Future<bool> updateActive(EncryptedVaultItem item) async {
    final affectedRows = await _db.update(
      'vault_items',
      {
        'nonce': item.nonce,
        'ciphertext': item.ciphertext,
        'mac': item.mac,
        'updated_at': item.updatedAt,
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [item.id],
    );
    if (affectedRows > 1) {
      throw StateError(
        'Expected to update at most one active vault_items row for id "${item.id}", but updated $affectedRows rows.',
      );
    }

    return affectedRows == 1;
  }

  Future<void> softDelete(String id, int deletedAt) async {
    final affectedRows = await _db.update(
      'vault_items',
      {'updated_at': deletedAt, 'deleted_at': deletedAt},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (affectedRows != 1) {
      throw StateError(
        'Expected to soft-delete exactly one vault_items row for id "$id", but updated $affectedRows rows.',
      );
    }
  }
}
