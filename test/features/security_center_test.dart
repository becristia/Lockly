import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/features/security_center/security_center_page.dart';

void main() {
  testWidgets('security center exposes local safety cards', (tester) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(
      MaterialApp(home: SecurityCenterPage(services: services)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('security-center-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('security-center-health-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('security-center-migration'),
        skipOffstage: false,
      ),
      findsWidgets,
    );
    expect(
      find.byKey(
        const ValueKey('security-center-attachments'),
        skipOffstage: false,
      ),
      findsWidgets,
    );
    expect(
      find.byKey(
        const ValueKey('security-center-passkeys'),
        skipOffstage: false,
      ),
      findsWidgets,
    );
  });

  testWidgets('security center summarizes local safety areas', (tester) async {
    var healthCalls = 0;
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      analyzePasswordHealthOverride: () async {
        healthCalls += 1;
        return const HealthReport(
          totalItems: 4,
          findings: <HealthFinding>[],
          score: 96,
          categoryCounts: <HealthCategory, int>{},
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(home: SecurityCenterPage(services: services)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('security-center-page')), findsOneWidget);
    expect(find.text('安全中心'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('security-center-health-card')),
      findsOneWidget,
    );
    expect(healthCalls, 0);

    await tester.tap(find.text('运行本地检查'));
    await tester.pumpAndSettle();

    expect(healthCalls, 1);
    expect(find.text('96/100 健康分'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('security-center-migration'),
        skipOffstage: false,
      ),
      findsWidgets,
    );
    expect(
      find.byKey(
        const ValueKey('security-center-attachments'),
        skipOffstage: false,
      ),
      findsWidgets,
    );
    expect(
      find.byKey(
        const ValueKey('security-center-passkeys'),
        skipOffstage: false,
      ),
      findsWidgets,
    );
  });

  testWidgets('security center opens LAN exchange recovery actions', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(
      MaterialApp(
        home: SecurityCenterPage(services: services),
        routes: {
          AppServices.routeLanSend: (_) =>
              const _RouteMarker(key: ValueKey('lan-send-route')),
          AppServices.routeLanReceive: (_) =>
              const _RouteMarker(key: ValueKey('lan-receive-route')),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('security-center-local-exchange-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('security-center-local-exchange-send')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('security-center-local-exchange-receive')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('security-center-local-exchange-send')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lan-send-route')), findsOneWidget);

    Navigator.of(
      tester.element(find.byKey(const ValueKey('lan-send-route'))),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('security-center-local-exchange-receive')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lan-receive-route')), findsOneWidget);
  });

  testWidgets('vault shell does not expose security center as a tab', (
    tester,
  ) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      analyzePasswordHealthOverride: () async => const HealthReport(
        totalItems: 0,
        findings: <HealthFinding>[],
        score: 100,
        categoryCounts: <HealthCategory, int>{},
      ),
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('vault-shell-security-tab')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('security-center-page')), findsNothing);
  });
}

class _RouteMarker extends StatelessWidget {
  const _RouteMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.shrink());
  }
}
