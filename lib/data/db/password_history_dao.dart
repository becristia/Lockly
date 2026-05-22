import 'package:sqflite/sqflite.dart';

class PasswordHistoryDao {
  PasswordHistoryDao(this._db);

  final DatabaseExecutor _db;

  DatabaseExecutor get executor => _db;

  Future<void> insert(
    String entryId,
    String encryptedPassword,
    String nonce,
    String mac,
    int recordedAt,
  ) async {
    await _db.insert('password_history', {
      'entry_id': entryId,
      'encrypted_password': encryptedPassword,
      'password_nonce': nonce,
      'password_mac': mac,
      'recorded_at': recordedAt,
    });
    // Enforce max 5 per entry
    final count =
        Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM password_history WHERE entry_id = ?',
            [entryId],
          ),
        ) ??
        0;
    if (count > 5) {
      await _db.rawDelete(
        'DELETE FROM password_history WHERE id IN '
        '(SELECT id FROM password_history WHERE entry_id = ? '
        'ORDER BY recorded_at ASC LIMIT ?)',
        [entryId, count - 5],
      );
    }
  }

  Future<void> insertRaw(
    Map<String, Object?> row, {
    bool preserveId = true,
  }) async {
    await _db.insert('password_history', {
      if (preserveId) 'id': row['id'],
      'entry_id': row['entry_id'],
      'encrypted_password': row['encrypted_password'],
      'password_nonce': row['password_nonce'],
      'password_mac': row['password_mac'],
      'recorded_at': row['recorded_at'],
    });
  }

  Future<List<Map<String, dynamic>>> byEntryId(String entryId) async {
    return _db.query(
      'password_history',
      where: 'entry_id = ?',
      whereArgs: [entryId],
      orderBy: 'recorded_at DESC',
    );
  }

  Future<Map<String, dynamic>?> byId(int id) async {
    final rows = await _db.query(
      'password_history',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.single;
  }

  Future<List<Map<String, dynamic>>> allRowsForManifest() async {
    return _db.query(
      'password_history',
      orderBy: 'entry_id ASC, recorded_at ASC, id ASC',
    );
  }

  Future<void> delete(int id) async {
    await _db.delete('password_history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForDeletedEntries() async {
    await _db.rawDelete(
      'DELETE FROM password_history WHERE entry_id IN '
      '(SELECT id FROM vault_items WHERE deleted_at IS NOT NULL)',
    );
  }

  Future<void> deleteAllForEntry(String entryId) async {
    await _db.delete(
      'password_history',
      where: 'entry_id = ?',
      whereArgs: [entryId],
    );
  }

  Future<void> deleteAll() async {
    await _db.delete('password_history');
  }
}
