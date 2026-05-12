import 'package:secure_box/data/models/vault_meta.dart';
import 'package:sqflite/sqflite.dart';

class VaultMetaDao {
  VaultMetaDao(this._db);

  final Database _db;

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
    await _db.update('vault_meta', {
      'encrypted_dek_by_biometric': null,
      'encrypted_dek_by_biometric_nonce': null,
      'encrypted_dek_by_biometric_mac': null,
      'biometric_enabled': 0,
      'updated_at': updatedAt,
    });
  }
}
