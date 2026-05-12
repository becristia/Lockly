import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:sqflite/sqflite.dart';

class VaultItemsDao {
  VaultItemsDao(this._db);

  final Database _db;

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

  Future<void> softDelete(String id, int deletedAt) async {
    await _db.update(
      'vault_items',
      {'updated_at': deletedAt, 'deleted_at': deletedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
