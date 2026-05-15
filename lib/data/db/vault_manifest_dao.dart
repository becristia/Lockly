import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:sqflite/sqflite.dart';

class VaultManifestDao {
  VaultManifestDao(this._db);

  final DatabaseExecutor _db;

  DatabaseExecutor get executor => _db;

  Future<void> save(VaultManifest manifest) async {
    await _db.insert(
      'vault_manifest',
      manifest.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<VaultManifest?> get() async {
    final rows = await _db.query('vault_manifest', limit: 2);
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      throw StateError('Expected at most one vault_manifest row');
    }

    return VaultManifest.fromDb(rows.single);
  }

  Future<void> deleteAll() async {
    await _db.delete('vault_manifest');
  }
}
