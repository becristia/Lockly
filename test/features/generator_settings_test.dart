import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';
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
import 'package:secure_box/data/models/vault_manifest.dart';
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
    expect(find.text('导入加密备份'), findsOneWidget);
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

      harness.vaultService.lock();
      await harness.vaultService.unlock(masterPassword: 'old-master-password');
      await expectLater(
        harness.vaultService.unlock(masterPassword: 'new-master-password'),
        throwsA(isA<VaultUnlockException>()),
      );
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
}

Future<_BiometricHarness> _buildBiometricHarness() async {
  final db = await AppDatabase.openInMemory();
  addTearDown(db.close);
  final repository = VaultRepository(
    metaDao: VaultMetaDao(db),
    itemsDao: VaultItemsDao(db),
    manifestDao: VaultManifestDao(db),
    settingsDao: SettingsDao(db),
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
