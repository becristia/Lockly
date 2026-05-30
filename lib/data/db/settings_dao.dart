import 'package:sqflite/sqflite.dart';

class SettingsDao {
  SettingsDao(this._db);

  final DatabaseExecutor _db;

  DatabaseExecutor get executor => _db;

  Future<void> setValue(String key, String value) async {
    await _db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getValue(String key) async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final value = rows.single['value'];
    if (value is! String) {
      throw const FormatException(
        'Invalid settings row: expected string value',
      );
    }

    return value;
  }

  Future<void> deleteValue(String key) async {
    await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<void> deleteAll() async {
    await _db.delete('settings');
  }
}
