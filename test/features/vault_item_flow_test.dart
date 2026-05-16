import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/features/vault_list/vault_list_page.dart';
import 'package:secure_box/shared/theme/app_theme.dart';

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

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(find.text('Secure Box'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
  );

  testWidgets('stale search results cannot replace the latest query', (
    tester,
  ) async {
    final broadQuery = Completer<List<VaultListItem>>();
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      trackActivity: false,
      listItemsOverride: (query) {
        if (query == 'g') {
          return broadQuery.future;
        }
        if (query == 'gi') {
          return Future.value([
            VaultListItem(
              id: 'github',
              title: 'GitHub',
              website: 'https://github.com',
              username: 'user@example.com',
              tags: const [],
              createdAt: 1,
              updatedAt: 2,
            ),
          ]);
        }
        return Future.value(const <VaultListItem>[]);
      },
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: VaultListPage(services: services),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '搜索'), 'g');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '搜索'), 'gi');
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);

    broadQuery.complete([
      VaultListItem(
        id: 'google',
        title: 'Google',
        website: 'https://google.com',
        username: 'google@example.com',
        tags: const [],
        createdAt: 1,
        updatedAt: 1,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Google'), findsNothing);
  });
}
