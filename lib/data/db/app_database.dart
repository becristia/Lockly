import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const int schemaVersion = 3;
  static const int vaultMetaSingletonKey = 1;
  static const int vaultManifestSingletonKey = 1;

  static Future<Database> open(String path) {
    return _openDatabase(path);
  }

  static Future<Database> openInMemory() {
    return _openDatabase(inMemoryDatabasePath, singleInstance: false);
  }

  static Future<Database> _openDatabase(
    String path, {
    bool singleInstance = true,
  }) {
    return openDatabase(
      path,
      singleInstance: singleInstance,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA secure_delete = ON');
      },
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
        await _createVaultManifestTable(db);
        await _createPasswordHistoryTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createVaultManifestTable(db);
        }
        if (oldVersion < 3) {
          await _createPasswordHistoryTable(db);
        }
      },
    );
  }

  static Future<void> _createPasswordHistoryTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE password_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id TEXT NOT NULL,
        encrypted_password TEXT NOT NULL,
        password_nonce TEXT NOT NULL,
        password_mac TEXT NOT NULL,
        recorded_at INTEGER NOT NULL,
        FOREIGN KEY (entry_id) REFERENCES vault_items(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _createVaultManifestTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE vault_manifest (
        singleton_key INTEGER NOT NULL DEFAULT 1
          CHECK (singleton_key = ${AppDatabase.vaultManifestSingletonKey})
          UNIQUE,
        version INTEGER NOT NULL,
        epoch INTEGER NOT NULL,
        counter INTEGER NOT NULL,
        nonce TEXT NOT NULL,
        ciphertext TEXT NOT NULL,
        mac TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }
}
