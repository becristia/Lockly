import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
          switch (methodCall.method) {
            case 'Clipboard.setData':
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': ''};
          }

          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'user can add an item and password stays hidden by default in detail',
    (tester) async {
      final services = AppServices.fake(hasVault: true, unlocked: true);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      await tester.pumpWidget(SecureBoxApp(services: services));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('新增密码'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, '标题'),
        'GitHub',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '网址'),
        'https://github.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '用户名'),
        'user@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '密码'),
        'super-secret-123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '备注'),
        '双重验证已开启',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '标签'),
        '开发, 常用',
      );

      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);

      await tester.tap(find.text('GitHub'));
      await tester.pumpAndSettle();

      expect(find.text('https://github.com'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);
      expect(find.text('super-secret-123'), findsNothing);
      expect(find.text('已隐藏'), findsOneWidget);

      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();

      expect(find.text('super-secret-123'), findsOneWidget);
    },
  );
}
