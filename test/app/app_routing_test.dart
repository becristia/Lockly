import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/shared/widgets/activity_text_form_field.dart';

void main() {
  testWidgets('fresh app shows setup page with recovery warning', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: false);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    expect(find.text('创建主密码'), findsOneWidget);
    expect(find.textContaining('无法找回'), findsOneWidget);
  });

  testWidgets('existing locked vault shows unlock page with master password', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    expect(find.text('解锁密码库'), findsOneWidget);
    expect(find.text('主密码'), findsOneWidget);
  });

  testWidgets('locked shell blocks vault routes', (tester) async {
    final services = AppServices.fake(hasVault: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    services.navigatorKey.currentState!.pushNamed(AppServices.routeVault);
    await tester.pumpAndSettle();

    expect(find.text('解锁密码库'), findsOneWidget);
    expect(find.text('密码库'), findsNothing);
  });

  testWidgets('locking clears pushed routes back to unlock shell', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    services.navigatorKey.currentState!.pushNamed(AppServices.routeGenerator);
    await tester.pumpAndSettle();
    expect(find.text('密码生成器'), findsOneWidget);

    services.lockVault();
    await tester.pumpAndSettle();

    expect(find.text('解锁密码库'), findsOneWidget);
    expect(find.text('密码生成器'), findsNothing);
  });

  testWidgets('bottom tab switch clears generated password state', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('vault-shell-generator-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.refresh_rounded).last);
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('vault-shell-vault-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vault-shell-generator-tab')));
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('text entry activity resets the auto-lock timer', (tester) async {
    final services = AppServices(
      hasVault: true,
      autoLockTimeout: const Duration(milliseconds: 300),
      initialShellState: AppShellState.unlocked,
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityTextFormField(
            onActivity: services.recordActivity,
            decoration: const InputDecoration(labelText: '主密码'),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ActivityTextFormField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(ActivityTextFormField), 'a');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(services.shellState.value, AppShellState.unlocked);

    await tester.pump(const Duration(milliseconds: 150));

    expect(services.shellState.value, AppShellState.locked);
  });
}
