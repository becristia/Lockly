import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';
import 'package:secure_box/core/clipboard/clipboard_service.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/password_history_dao.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_manifest_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:secure_box/features/migration/migration_wizard_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets(
    'generator saves a generated 24 character password into edit page',
    (tester) async {
      final services = AppServices.fake(hasVault: true, unlocked: true);

      await tester.pumpWidget(SecureBoxApp(services: services));
      await tester.pumpAndSettle();

      services.navigatorKey.currentState!.pushNamed(AppServices.routeGenerator);
      await tester.pumpAndSettle();

      await tester.tap(find.text('24'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '生成密码'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '保存此密码'));
      await tester.pumpAndSettle();

      expect(find.text('新增密码'), findsOneWidget);

      final passwordField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, '密码'),
      );
      expect(passwordField.controller?.text, hasLength(24));
    },
  );

  testWidgets('generator copy button copies generated password', (
    tester,
  ) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final data = Map<Object?, Object?>.from(call.arguments as Map);
            clipboardText = data['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    services.navigatorKey.currentState!.pushNamed(AppServices.routeGenerator);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('generator-generate-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();

    expect(clipboardText, isNotNull);
    expect(clipboardText, isNotEmpty);
  });

  testWidgets('settings exposes required local vault controls', (tester) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    services.navigatorKey.currentState!.pushNamed(AppServices.routeSettings);
    await tester.pumpAndSettle();

    expect(find.text('修改主密码'), findsOneWidget);
    expect(find.text('生物识别'), findsOneWidget);
    expect(find.text('自动锁定'), findsOneWidget);
    expect(find.text('剪贴板清理'), findsOneWidget);
    expect(find.text('导出加密备份'), findsOneWidget);
    expect(find.text('迁移导入'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('清除本地密码库'),
      120,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('清除本地密码库'));
    await tester.pumpAndSettle();

    expect(find.text('此操作会删除本机密码库和设置，无法找回。请确认已经导出可用备份。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '清除'), findsOneWidget);
  });

  testWidgets('settings exposes LAN exchange local transfer actions', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    services.navigatorKey.currentState!.pushNamed(AppServices.routeSettings);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-section-lan-sync')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings-lan-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-lan-receive')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-section-backup')),
      findsOneWidget,
    );
  });

  testWidgets('settings opens migration wizard from backup import', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    services.navigatorKey.currentState!.pushNamed(AppServices.routeSettings);
    await tester.pumpAndSettle();

    final importTile = find.widgetWithText(ListTile, '迁移导入');
    await tester.scrollUntilVisible(
      importTile,
      120,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(importTile);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('migration-wizard-page')), findsOneWidget);
    expect(find.text('迁移导入'), findsOneWidget);
  });

  testWidgets(
    'migration wizard previews CSV without rendering secrets and imports rows',
    (tester) async {
      final services = AppServices.fake(hasVault: true, unlocked: true);

      await tester.pumpWidget(
        MaterialApp(home: MigrationWizardPage(services: services)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('migration-csv-input')),
        'title,website,username,password,notes,totp\n'
        'Bank,https://bank.example,alice,bank-secret,private note,OTPSECRET\n',
      );
      await tester.tap(find.text('预览'));
      await tester.pumpAndSettle();

      expect(find.text('1 可导入行'), findsOneWidget);
      expect(find.text('Bank'), findsOneWidget);
      expect(find.text('https://bank.example'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.textContaining('bank-secret'), findsNothing);
      expect(find.textContaining('private note'), findsNothing);
      expect(find.textContaining('OTPSECRET'), findsNothing);

      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();

      final items = await services.listVaultItems();
      expect(items.single.title, 'Bank');
    },
  );

  testWidgets('migration wizard clears visible CSV when preview fails', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(
      MaterialApp(home: MigrationWizardPage(services: services)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('migration-csv-input')),
      'title,website,username,password\n"Broken,https://bank.example,alice,bank-secret',
    );
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();

    expect(find.text('无法在本地解析 CSV 导入内容。'), findsOneWidget);
    expect(find.textContaining('bank-secret'), findsNothing);
  });

  testWidgets('migration wizard clears pasted CSV when switching source', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(
      MaterialApp(home: MigrationWizardPage(services: services)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('migration-csv-input')),
      'title,website,username,password\nBank,https://bank.example,alice,bank-secret\n',
    );
    await tester.tap(find.text('Lockly JSON'));
    await tester.pumpAndSettle();

    expect(find.textContaining('bank-secret'), findsNothing);
  });

  testWidgets('migration wizard requires a new preview after CSV changes', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(
      MaterialApp(home: MigrationWizardPage(services: services)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('migration-csv-input')),
      'title,website,username,password\n'
      'Bank,https://bank.example,alice,bank-secret\n',
    );
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();

    expect(find.text('1 可导入行'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('migration-csv-input')),
      'title,website,username,password\n'
      'Mail,https://mail.example,bob,mail-secret\n',
    );
    await tester.pumpAndSettle();

    expect(find.text('1 可导入行'), findsNothing);
    expect(find.widgetWithText(FilledButton, '导入'), findsOneWidget);

    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    final items = await services.listVaultItems();
    expect(items.single.title, 'Mail');
  });

  testWidgets('migration wizard keeps Lockly encrypted JSON import path', (
    tester,
  ) async {
    String? importedJson;
    String? importedPassword;
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      clipboardService: ClipboardService(),
      biometricEnabledOverride: () async => false,
      autoLockTimeoutOverride: () async => const Duration(minutes: 2),
      clipboardCleanupTimeoutOverride: () async => const Duration(seconds: 30),
      importBackupOverride: (backupJson, masterPassword) async {
        importedJson = backupJson;
        importedPassword = masterPassword;
        return 3;
      },
      trackActivity: false,
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      MaterialApp(home: MigrationWizardPage(services: services)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('migration-json-input')),
      '{"version":2,"items":[]}',
    );
    await tester.enterText(
      find.byKey(const ValueKey('migration-backup-password-input')),
      'backup-master',
    );
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(importedJson, '{"version":2,"items":[]}');
    expect(importedPassword, 'backup-master');
    expect(find.textContaining('backup-master'), findsNothing);
  });

  testWidgets('backup export dialog can copy encrypted backup json', (
    tester,
  ) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final data = Map<Object?, Object?>.from(call.arguments as Map);
            clipboardText = data['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    services.navigatorKey.currentState!.pushNamed(AppServices.routeSettings);
    await tester.pumpAndSettle();

    final exportIcon = find.byIcon(Icons.file_upload_outlined).first;
    await tester.scrollUntilVisible(exportIcon, 120);
    await tester.tap(exportIcon);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();

    expect(clipboardText, contains('"version"'));
  });

  testWidgets('successful master password change closes dialog cleanly', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    services.navigatorKey.currentState!.pushNamed(AppServices.routeSettings);
    await tester.pumpAndSettle();

    await tester.tap(find.text('修改主密码'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '当前主密码'),
      'old-master-password',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '新主密码'),
      'correct horse battery staple',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '确认新主密码'),
      'correct horse battery staple',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('主密码已修改，生物识别需要重新开启。'), findsOneWidget);
  });

  testWidgets('successful biometric enable closes password prompt cleanly', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    services.navigatorKey.currentState!.pushNamed(AppServices.routeSettings);
    await tester.pumpAndSettle();

    await tester.tap(find.text('生物识别'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '主密码'),
      'old-master-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, '开启'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isTrue);
  });

  test('failed master password change does not delete biometric DEK', () async {
    final harness = await _buildBiometricHarness();
    await harness.vaultService.enableBiometricUnlock(
      masterPassword: 'old-master-password',
      biometricService: harness.biometricService,
    );

    await expectLater(
      harness.services.changeMasterPassword(
        oldPassword: 'wrong-master-password',
        newPassword: 'new-master-password',
      ),
      throwsA(isA<VaultUnlockException>()),
    );

    expect(harness.store.deleteCount, 0);
    expect(
      (await harness.vaultService.repository.metaDao.get())?.biometricEnabled,
      isTrue,
    );
  });

  test(
    'biometric delete failure prevents master password metadata change',
    () async {
      final harness = await _buildBiometricHarness();
      await harness.vaultService.enableBiometricUnlock(
        masterPassword: 'old-master-password',
        biometricService: harness.biometricService,
      );
      harness.store.throwOnDelete = true;

      await expectLater(
        harness.services.changeMasterPassword(
          oldPassword: 'old-master-password',
          newPassword: 'new-master-password',
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        (await harness.vaultService.repository.metaDao.get())?.biometricEnabled,
        isTrue,
      );
    },
  );

  test(
    'biometric disable delete failure leaves biometric metadata enabled',
    () async {
      final harness = await _buildBiometricHarness();
      await harness.vaultService.enableBiometricUnlock(
        masterPassword: 'old-master-password',
        biometricService: harness.biometricService,
      );
      harness.store.throwOnDelete = true;

      await expectLater(
        harness.services.disableBiometricUnlock(),
        throwsA(isA<StateError>()),
      );

      expect(harness.store.deleteCount, 1);
      expect(
        (await harness.vaultService.repository.metaDao.get())?.biometricEnabled,
        isTrue,
      );
    },
  );

  test('clear local vault deletes persisted vault manifest', () async {
    final harness = await _buildBiometricHarness();
    await harness.vaultService.repository.manifestDao.save(
      VaultManifest(
        version: 1,
        epoch: 1,
        counter: 1,
        nonce: 'manifest-nonce',
        ciphertext: 'manifest-ciphertext',
        mac: 'manifest-mac',
        updatedAt: 1747000000000,
      ),
    );

    await harness.services.clearLocalVault();

    expect(await harness.vaultService.repository.manifestDao.get(), isNull);
  });

  test('password history integrity failure locks the app shell', () async {
    final harness = await _buildBiometricHarness();
    harness.services.markVaultUnlocked();
    final id = await harness.vaultService.createItem(
      PasswordEntry(
        title: 'History',
        website: 'https://history.example',
        username: 'history@example.com',
        password: 'old-password',
        notes: 'history test',
        tags: const ['history'],
      ),
    );
    await harness.vaultService.updateItem(
      id,
      PasswordEntry(
        title: 'History',
        website: 'https://history.example',
        username: 'history@example.com',
        password: 'new-password',
        notes: 'history test',
        tags: const ['history'],
      ),
    );
    expect(harness.services.shellState.value, AppShellState.unlocked);
    await harness.vaultService.repository.historyDao!.deleteAll();

    await expectLater(
      harness.services.listPasswordHistory(id),
      throwsA(isA<VaultIntegrityException>()),
    );

    expect(harness.services.shellState.value, AppShellState.locked);
    expect(harness.vaultService.isUnlocked, isFalse);
  });

  test('restore password integrity failure locks the app shell', () async {
    final harness = await _buildBiometricHarness();
    harness.services.markVaultUnlocked();
    final firstId = await harness.vaultService.createItem(
      PasswordEntry(
        title: 'First',
        website: 'https://first.example',
        username: 'first@example.com',
        password: 'first-old',
        notes: 'first item',
        tags: const ['history'],
      ),
    );
    final secondId = await harness.vaultService.createItem(
      PasswordEntry(
        title: 'Second',
        website: 'https://second.example',
        username: 'second@example.com',
        password: 'second-old',
        notes: 'second item',
        tags: const ['history'],
      ),
    );
    await harness.vaultService.updateItem(
      firstId,
      PasswordEntry(
        title: 'First',
        website: 'https://first.example',
        username: 'first@example.com',
        password: 'first-new',
        notes: 'first item',
        tags: const ['history'],
      ),
    );
    final history = await harness.vaultService.listPasswordHistory(firstId);

    await expectLater(
      harness.services.restorePassword(secondId, history.single['id'] as int),
      throwsA(isA<VaultIntegrityException>()),
    );

    expect(harness.services.shellState.value, AppShellState.locked);
    expect(harness.vaultService.isUnlocked, isFalse);
  });

  test('vault item integrity failure locks the app shell', () async {
    final harness = await _buildBiometricHarness();
    harness.services.markVaultUnlocked();
    final id = await harness.vaultService.createItem(
      PasswordEntry(
        title: 'Tampered',
        website: 'https://tampered.example',
        username: 'tampered@example.com',
        password: 'secret-password',
        notes: 'tamper test',
        tags: const ['integrity'],
      ),
    );
    final manifest = await harness.vaultService.repository.manifestDao.get();
    await harness.vaultService.repository.manifestDao.save(
      manifest!.copyWith(mac: '${manifest.mac}tampered'),
    );

    await expectLater(
      harness.services.getVaultItem(id),
      throwsA(isA<VaultIntegrityException>()),
    );

    expect(harness.services.shellState.value, AppShellState.locked);
    expect(harness.vaultService.isUnlocked, isFalse);
  });

  test('trash integrity failure locks the app shell', () async {
    final harness = await _buildBiometricHarness();
    harness.services.markVaultUnlocked();
    final id = await harness.vaultService.createItem(
      PasswordEntry(
        title: 'Deleted',
        website: 'https://deleted.example',
        username: 'deleted@example.com',
        password: 'secret-password',
        notes: 'trash test',
        tags: const ['trash'],
      ),
    );
    await harness.services.deleteVaultItem(id);
    final manifest = await harness.vaultService.repository.manifestDao.get();
    await harness.vaultService.repository.manifestDao.save(
      manifest!.copyWith(mac: '${manifest.mac}tampered'),
    );

    await expectLater(
      harness.services.listDeletedItems(),
      throwsA(isA<VaultIntegrityException>()),
    );

    expect(harness.services.shellState.value, AppShellState.locked);
    expect(harness.vaultService.isUnlocked, isFalse);
  });

  test('trash count integrity failure locks the app shell', () async {
    final harness = await _buildBiometricHarness();
    harness.services.markVaultUnlocked();
    final id = await harness.vaultService.createItem(
      PasswordEntry(
        title: 'Deleted Count',
        website: 'https://deleted-count.example',
        username: 'deleted-count@example.com',
        password: 'secret-password',
        notes: 'trash count test',
        tags: const ['trash'],
      ),
    );
    await harness.services.deleteVaultItem(id);
    final manifest = await harness.vaultService.repository.manifestDao.get();
    await harness.vaultService.repository.manifestDao.save(
      manifest!.copyWith(mac: '${manifest.mac}tampered'),
    );

    await expectLater(
      harness.services.deletedItemCount(),
      throwsA(isA<VaultIntegrityException>()),
    );

    expect(harness.services.shellState.value, AppShellState.locked);
    expect(harness.vaultService.isUnlocked, isFalse);
  });
}

Future<_BiometricHarness> _buildBiometricHarness() async {
  final db = await AppDatabase.openInMemory();
  addTearDown(db.close);
  final repository = VaultRepository(
    metaDao: VaultMetaDao(db),
    itemsDao: VaultItemsDao(db),
    manifestDao: VaultManifestDao(db),
    settingsDao: SettingsDao(db),
    historyDao: PasswordHistoryDao(db),
  );
  final random = SecureRandom();
  final vaultService = VaultService(
    repository: repository,
    random: random,
    kdf: KdfService(),
    crypto: CryptoService(random: random),
  );
  await vaultService.createVault(masterPassword: 'old-master-password');
  await vaultService.unlock(masterPassword: 'old-master-password');

  final store = _ThrowingDeleteStore();
  final biometricService = BiometricService(
    authenticator: FakeBiometricAuthenticator(
      canAuthenticate: true,
      succeeds: true,
    ),
    store: store,
  );
  final services = AppServices(
    hasVault: true,
    vaultService: vaultService,
    biometricService: biometricService,
    trackActivity: false,
  );
  addTearDown(services.dispose);

  return _BiometricHarness(
    services: services,
    vaultService: vaultService,
    biometricService: biometricService,
    store: store,
  );
}

class _BiometricHarness {
  const _BiometricHarness({
    required this.services,
    required this.vaultService,
    required this.biometricService,
    required this.store,
  });

  final AppServices services;
  final VaultService vaultService;
  final BiometricService biometricService;
  final _ThrowingDeleteStore store;
}

class _ThrowingDeleteStore implements SecureDekStore {
  Uint8List? _dek;
  var deleteCount = 0;
  var throwOnDelete = false;

  @override
  SecureDekReadRequirement get readRequirement =>
      SecureDekReadRequirement.explicitBiometricAuthentication;

  @override
  Future<bool> canUseBiometricProtection() async => true;

  @override
  Future<void> writeDek(Uint8List dek) async {
    _dek = Uint8List.fromList(dek);
  }

  @override
  Future<Uint8List?> readDek() async {
    final dek = _dek;
    return dek == null ? null : Uint8List.fromList(dek);
  }

  @override
  Future<void> deleteDek() async {
    deleteCount += 1;
    if (throwOnDelete) {
      throw StateError('delete failed');
    }
    _dek = null;
  }
}
