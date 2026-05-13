import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';

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
}
