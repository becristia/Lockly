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
    final count = Sqflite.firstIntValue(await _db.rawQuery(
      'SELECT COUNT(*) FROM password_history WHERE entry_id = ?',
      [entryId],
    )) ?? 0;
    if (count > 5) {
      await _db.rawDelete(
        'DELETE FROM password_history WHERE id IN '
        '(SELECT id FROM password_history WHERE entry_id = ? '
        'ORDER BY recorded_at ASC LIMIT ?)',
        [entryId, count - 5],
      );
    }
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
}
