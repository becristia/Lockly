import 'package:secure_box/data/db/password_history_dao.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_blobs_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_manifest_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:sqflite/sqflite.dart';

class VaultRepository {
  VaultRepository({
    required this.metaDao,
    required this.itemsDao,
    required this.manifestDao,
    required this.settingsDao,
    VaultBlobsDao? blobsDao,
    this.historyDao,
    Database? database,
  }) : blobsDao = blobsDao ?? VaultBlobsDao(itemsDao.executor),
       _database =
           database ??
           _inferDatabase(
             metaDao,
             blobsDao,
             itemsDao,
             manifestDao,
             settingsDao,
           );

  final VaultMetaDao metaDao;
  final VaultBlobsDao blobsDao;
  final VaultItemsDao itemsDao;
  final VaultManifestDao manifestDao;
  final SettingsDao settingsDao;
  final PasswordHistoryDao? historyDao;
  final Database? _database;

  Future<T> transaction<T>(
    Future<T> Function(VaultRepository repository) action,
  ) async {
    final database = _database;
    if (database == null) {
      return action(this);
    }

    return database.transaction((txn) async {
      return action(
        VaultRepository(
          metaDao: VaultMetaDao(txn),
          blobsDao: VaultBlobsDao(txn),
          itemsDao: VaultItemsDao(txn),
          manifestDao: VaultManifestDao(txn),
          settingsDao: SettingsDao(txn),
          historyDao: historyDao != null ? PasswordHistoryDao(txn) : null,
        ),
      );
    });
  }

  static Database? _inferDatabase(
    VaultMetaDao metaDao,
    VaultBlobsDao? blobsDao,
    VaultItemsDao itemsDao,
    VaultManifestDao manifestDao,
    SettingsDao settingsDao,
  ) {
    final executors = [
      metaDao.executor,
      blobsDao?.executor,
      itemsDao.executor,
      manifestDao.executor,
      settingsDao.executor,
    ];

    for (final executor in executors) {
      if (executor is Database) {
        return executor;
      }
    }

    return null;
  }
}
