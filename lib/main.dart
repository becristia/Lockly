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
import 'package:secure_box/data/db/vault_meta_dao.dart';

Future<void> main() async {
  final bindings = WidgetsFlutterBinding.ensureInitialized();
  final documentsDirectory = await getApplicationDocumentsDirectory();
  final databasePath = p.join(documentsDirectory.path, 'secure_box.db');
  final database = await AppDatabase.open(databasePath);

  final metaDao = VaultMetaDao(database);
  final repository = VaultRepository(
    database: database,
    metaDao: metaDao,
    itemsDao: VaultItemsDao(database),
    settingsDao: SettingsDao(database),
  );
  final random = SecureRandom();
  final hasVault = await metaDao.get() != null;
  final vaultService = VaultService(
    repository: repository,
    random: random,
    kdf: KdfService(),
    crypto: CryptoService(random: random),
  );
  final services = AppServices(
    hasVault: hasVault,
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
    clipboardService: ClipboardService(),
  );

  bindings.addObserver(services.appLifecycleGuard);
  runApp(SecureBoxApp(services: services));
}
