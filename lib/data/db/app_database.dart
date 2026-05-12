import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const int schemaVersion = 1;
  static const int vaultMetaSingletonKey = 1;

  static Future<Database> open(String path) {
    return _openDatabase(path);
  }

  static Future<Database> openInMemory() {
    return _openDatabase(inMemoryDatabasePath);
  }

  static Future<Database> _openDatabase(String path) {
    return openDatabase(
      path,
      version: schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vault_meta (
            singleton_key INTEGER NOT NULL DEFAULT 1
              CHECK (singleton_key = ${AppDatabase.vaultMetaSingletonKey})
              UNIQUE,
            id TEXT PRIMARY KEY,
            version INTEGER NOT NULL,
            kdf TEXT NOT NULL,
            kdf_params TEXT NOT NULL,
            salt TEXT NOT NULL,
            encrypted_dek_by_master TEXT NOT NULL,
            encrypted_dek_by_master_nonce TEXT NOT NULL,
            encrypted_dek_by_master_mac TEXT NOT NULL,
            encrypted_dek_by_biometric TEXT,
            encrypted_dek_by_biometric_nonce TEXT,
            encrypted_dek_by_biometric_mac TEXT,
            biometric_enabled INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE vault_items (
            id TEXT PRIMARY KEY,
            nonce TEXT NOT NULL,
            ciphertext TEXT NOT NULL,
            mac TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE INDEX vault_items_active_idx
          ON vault_items (deleted_at, updated_at DESC, created_at DESC)
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
  }
}
