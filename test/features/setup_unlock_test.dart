import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/features/setup/setup_page.dart';
import 'package:secure_box/features/unlock/unlock_page.dart';
import 'package:secure_box/shared/theme/app_theme.dart';

void main() {
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
      await tester.tap(find.text('创建密码库'));
      await tester.pump();

      expect(find.text('两次输入的主密码不一致'), findsOneWidget);
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
      await tester.tap(find.text('创建密码库'));
      await tester.pump();

      expect(services.fakeCreateVaultCalls, 1);
      expect(services.fakeLastCreateVaultPassword, 'very-secure-password');
      expect(services.fakeLastCreateVaultBiometricEnabled, isTrue);
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
