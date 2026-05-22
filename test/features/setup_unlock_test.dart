import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/features/setup/setup_page.dart';
import 'package:secure_box/features/unlock/unlock_page.dart';
import 'package:secure_box/shared/theme/app_theme.dart';

void main() {
  group('AppServices', () {
    test('createVault override still transitions shell state', () async {
      final services = AppServices(
        hasVault: false,
        trackActivity: false,
        createVaultOverride: (masterPassword, enableBiometric) async {
          return BiometricSetupResult.notRequested;
        },
      );
      addTearDown(services.dispose);

      final result = await services.createVault(
        masterPassword: 'very-secure-password',
        enableBiometric: false,
      );

      expect(result, BiometricSetupResult.notRequested);
      expect(services.shellState.value, AppShellState.locked);
    });

    test('unlock override still transitions shell state', () async {
      final services = AppServices(
        hasVault: true,
        trackActivity: false,
        unlockOverride: (masterPassword) async => true,
      );
      addTearDown(services.dispose);

      final unlocked = await services.unlockWithMasterPassword(
        'very-secure-password',
      );

      expect(unlocked, isTrue);
      expect(services.shellState.value, AppShellState.unlocked);
    });

    test(
      'master unlock throttling blocks immediate repeated attempts',
      () async {
        var unlockCalls = 0;
        final services = AppServices(
          hasVault: true,
          trackActivity: false,
          unlockOverride: (masterPassword) async {
            unlockCalls += 1;
            return false;
          },
        );
        addTearDown(services.dispose);

        expect(
          await services.unlockWithMasterPassword('wrong-password'),
          isFalse,
        );
        expect(
          await services.unlockWithMasterPassword('wrong-password'),
          isFalse,
        );
        expect(unlockCalls, 2);

        expect(
          await services.unlockWithMasterPassword('wrong-password'),
          isFalse,
        );
        expect(unlockCalls, 2);
      },
    );

    test('master unlock throttle allows retry after the UI backoff window', () {
      fakeAsync((async) {
        var unlockCalls = 0;
        final services = AppServices(
          hasVault: true,
          trackActivity: false,
          unlockOverride: (masterPassword) async {
            unlockCalls += 1;
            return masterPassword == 'correct-password';
          },
        );

        for (var i = 0; i < 5; i += 1) {
          var unlocked = true;
          services.unlockWithMasterPassword('wrong-password').then((value) {
            unlocked = value;
          });
          async.flushMicrotasks();
          expect(unlocked, isFalse);
          if (i >= 1) {
            async.elapse(Duration(seconds: 1 << (i - 1)));
          }
        }
        expect(unlockCalls, 5);

        async.elapse(const Duration(seconds: 8));
        var unlocked = false;
        services.unlockWithMasterPassword('correct-password').then((value) {
          unlocked = value;
        });
        async.flushMicrotasks();

        expect(unlocked, isTrue);
        expect(unlockCalls, 6);
        services.dispose();
      });
    });
  });

  group('SetupPage', () {
    testWidgets('validates mismatched passwords and keeps biometric optional', (
      tester,
    ) async {
      final services = AppServices.fake(hasVault: false);

      await _pumpPage(
        tester,
        services: services,
        home: SetupPage(services: services),
      );

      expect(find.text('主密码不会上传，也无法找回。请务必牢记。'), findsOneWidget);
      expect(find.text('启用生物识别快速解锁'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, '主密码'),
        'very-secure-password',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '确认主密码'),
        'different-password',
      );
      await _tapVisible(tester, find.text('创建密码库'));
      await tester.pump();

      expect(find.text('两次输入的主密码不一致'), findsOneWidget);
    });

    testWidgets('rejects common weak master passwords before creating vault', (
      tester,
    ) async {
      final services = AppServices.fake(hasVault: false);

      await _pumpPage(
        tester,
        services: services,
        home: SetupPage(services: services),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, '主密码'),
        'password123456',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '确认主密码'),
        'password123456',
      );
      await _tapVisible(tester, find.text('创建密码库'));
      await tester.pump();

      expect(find.textContaining('常见弱密码'), findsOneWidget);
      expect(services.fakeCreateVaultCalls, 0);
    });

    testWidgets('shows master password strength feedback while typing', (
      tester,
    ) async {
      final services = AppServices.fake(hasVault: false);

      await _pumpPage(
        tester,
        services: services,
        home: SetupPage(services: services),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, '主密码'),
        'correct horse battery staple',
      );
      await tester.pump();

      expect(find.textContaining('强'), findsWidgets);
      expect(find.textContaining('密码短语'), findsOneWidget);
    });

    testWidgets('submits with biometric enabled when toggle is on', (
      tester,
    ) async {
      final services = AppServices.fake(hasVault: false);

      await _pumpPage(
        tester,
        services: services,
        home: SetupPage(services: services),
      );

      await tester.tap(find.text('启用生物识别快速解锁'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextFormField, '主密码'),
        'very-secure-password',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '确认主密码'),
        'very-secure-password',
      );
      await _tapVisible(tester, find.text('创建密码库'));
      await tester.pump();

      expect(services.fakeCreateVaultCalls, 1);
      expect(services.fakeLastCreateVaultPassword, 'very-secure-password');
      expect(services.fakeLastCreateVaultBiometricEnabled, isTrue);
      expect(services.shellState.value, AppShellState.locked);
    });

    testWidgets('shows notice when biometric enablement fails', (tester) async {
      final services = AppServices(
        hasVault: false,
        trackActivity: false,
        createVaultOverride: (masterPassword, enableBiometric) async {
          return BiometricSetupResult.failed;
        },
      );

      await _pumpPage(
        tester,
        services: services,
        home: SetupPage(services: services),
      );

      await tester.tap(find.text('启用生物识别快速解锁'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextFormField, '主密码'),
        'very-secure-password',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '确认主密码'),
        'very-secure-password',
      );
      await _tapVisible(tester, find.text('创建密码库'));
      await tester.pump();

      expect(find.text('密码库已创建，但未能启用生物识别。'), findsOneWidget);
      expect(services.shellState.value, AppShellState.locked);
    });
  });

  group('UnlockPage', () {
    testWidgets('shows generic error for wrong master password', (
      tester,
    ) async {
      final services = AppServices.fake(hasVault: true, unlockSucceeds: false);

      await _pumpPage(
        tester,
        services: services,
        home: UnlockPage(services: services),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, '主密码'),
        'wrong-password',
      );
      await tester.tap(find.text('解锁'));
      await tester.pump();

      expect(find.text('主密码不正确'), findsOneWidget);
      expect(services.fakeUnlockCalls, 1);
    });

    testWidgets('recovers from unexpected unlock errors', (tester) async {
      final services = AppServices(
        hasVault: true,
        trackActivity: false,
        unlockOverride: (masterPassword) async {
          throw StateError('boom');
        },
      );

      await _pumpPage(
        tester,
        services: services,
        home: UnlockPage(services: services),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, '主密码'),
        'wrong-password',
      );
      await tester.tap(find.text('解锁'));
      await tester.pump();

      expect(find.text('暂时无法解锁，请重试'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '解锁'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets(
      'shows biometric action and backs off after repeated failures',
      (tester) async {
        final services = AppServices.fake(
          hasVault: true,
          unlockSucceeds: false,
          biometricEnabled: true,
        );

        await _pumpPage(
          tester,
          services: services,
          home: UnlockPage(services: services),
        );
        await tester.pump();

        expect(find.text('使用生物识别'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextFormField, '主密码'),
          'wrong-password',
        );
        await tester.tap(find.text('解锁'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('解锁'));
        await tester.pumpAndSettle();

        expect(find.textContaining('请等待'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '解锁'))
              .onPressed,
          isNull,
        );

        await tester.pump(const Duration(seconds: 1));
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '解锁'))
              .onPressed,
          isNotNull,
        );
      },
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: AppTheme.light(), home: home);
  }
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required AppServices services,
  required Widget home,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    services.dispose();
    await tester.pump();
  });

  await tester.pumpWidget(_TestApp(home: home));
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}
