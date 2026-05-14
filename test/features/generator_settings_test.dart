import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';

void main() {
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
    expect(find.text('清除本地密码库'), findsOneWidget);

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
}
