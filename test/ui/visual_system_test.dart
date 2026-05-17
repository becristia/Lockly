import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/shared/theme/app_theme.dart';

void main() {
  testWidgets('app theme provides a dark security console surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            return Scaffold(
              body: Text(
                '${theme.brightness.name}:${theme.colorScheme.surface}',
              ),
            );
          },
        ),
      ),
    );

    expect(find.textContaining('dark:'), findsOneWidget);
    expect(
      find.textContaining('Color(alpha: 1.0000, red: 1.0000'),
      findsNothing,
    );
  });

  testWidgets('vault list shows a security summary above records', (
    tester,
  ) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-1',
          notes: '',
          tags: const [],
        ),
        PasswordEntry(
          title: 'Mail',
          website: 'https://mail.example.com',
          username: 'mail@example.com',
          password: 'secret-2',
          notes: '',
          tags: const [],
        ),
      ],
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('vault-list-security-summary')),
      findsOneWidget,
    );
    expect(find.text('本地密码库'), findsOneWidget);
    expect(find.text('2 条记录仅保存在本机'), findsOneWidget);
  });

  testWidgets('settings page uses grouped security sections', (tester) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vault-shell-settings-tab')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-section-unlock')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-section-privacy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-section-backup')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-section-danger')),
      160,
    );
    expect(
      find.byKey(const ValueKey('settings-section-danger')),
      findsOneWidget,
    );
  });

  testWidgets('generator presents generated password in a result panel', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vault-shell-generator-tab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('generator-generate-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('generator-result-panel')),
      findsOneWidget,
    );
    expect(find.text('生成结果'), findsOneWidget);
  });
}
