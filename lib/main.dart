import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/backup/backup_service.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';
import 'package:secure_box/core/clipboard/clipboard_service.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_manifest_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';

Future<void> main() async {
  final bindings = WidgetsFlutterBinding.ensureInitialized();
  final documentsDirectory = await getApplicationDocumentsDirectory();
  final databasePath = p.join(documentsDirectory.path, 'secure_box.db');
  final database = await AppDatabase.open(databasePath);

  final metaDao = VaultMetaDao(database);
  final settingsDao = SettingsDao(database);
  final repository = VaultRepository(
    database: database,
    metaDao: metaDao,
    itemsDao: VaultItemsDao(database),
    manifestDao: VaultManifestDao(database),
    settingsDao: settingsDao,
  );
  final random = SecureRandom();
  final hasVault = await metaDao.get() != null;
  final autoLockTimeout = await _readDurationSetting(
    settingsDao,
    key: 'auto_lock_seconds',
    fallback: const Duration(minutes: 2),
  );
  final clipboardCleanupTimeout = await _readDurationSetting(
    settingsDao,
    key: 'clipboard_clear_seconds',
    fallback: const Duration(seconds: 30),
  );
  final vaultService = VaultService(
    repository: repository,
    random: random,
    kdf: KdfService(),
    crypto: CryptoService(random: random),
  );
  final services = AppServices(
    hasVault: hasVault,
    autoLockTimeout: autoLockTimeout,
    vaultService: vaultService,
    backupService: BackupService(
      repository: repository,
      vaultService: vaultService,
    ),
    biometricService: BiometricService(
      authenticator: LocalAuthBiometricAuthenticator(
        localizedReason: '验证身份以解锁 Secure Box',
      ),
      store: SecureStorageDekStore(),
    ),
    clipboardService: ClipboardService(
      clearPasswordAfter: clipboardCleanupTimeout,
    ),
  );

  bindings.addObserver(services.appLifecycleGuard);
  runApp(SecureBoxApp(services: services));
}

Future<Duration> _readDurationSetting(
  SettingsDao settingsDao, {
  required String key,
  required Duration fallback,
}) async {
  final rawValue = await settingsDao.getValue(key);
  final seconds = rawValue == null ? null : int.tryParse(rawValue);
  if (seconds == null || seconds <= 0) {
    return fallback;
  }

  return Duration(seconds: seconds);
}
