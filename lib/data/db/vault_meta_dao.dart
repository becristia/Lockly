import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/models/vault_meta.dart';
import 'package:sqflite/sqflite.dart';

class VaultMetaDao {
  VaultMetaDao(this._db);

  final DatabaseExecutor _db;

  DatabaseExecutor get executor => _db;

  Future<void> save(VaultMeta meta) async {
    await _db.insert(
      'vault_meta',
      meta.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<VaultMeta?> get() async {
    final rows = await _db.query('vault_meta', limit: 2);
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      throw StateError('Expected at most one vault_meta row');
    }

    return VaultMeta.fromDb(rows.single);
  }

  Future<void> clearBiometricDek(int updatedAt) async {
    final affectedRows = await _db.update(
      'vault_meta',
      {
        'encrypted_dek_by_biometric': null,
        'encrypted_dek_by_biometric_nonce': null,
        'encrypted_dek_by_biometric_mac': null,
        'biometric_enabled': 0,
        'updated_at': updatedAt,
      },
      where:
          'singleton_key = ? AND biometric_enabled = 1 AND '
          'encrypted_dek_by_biometric IS NOT NULL AND '
          'encrypted_dek_by_biometric_nonce IS NOT NULL AND '
          'encrypted_dek_by_biometric_mac IS NOT NULL',
      whereArgs: [AppDatabase.vaultMetaSingletonKey],
    );
    if (affectedRows != 1) {
      throw StateError(
        'Expected to clear biometric DEK from exactly one vault_meta row, but updated $affectedRows rows.',
      );
    }
  }
}
