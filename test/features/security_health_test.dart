import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/features/security_health/health_page.dart';

HealthReport _fakeReport({
  int totalItems = 3,
  List<HealthFinding>? findings,
  int score = 60,
}) {
  return HealthReport(
    totalItems: totalItems,
    findings:
        findings ??
        [
          HealthFinding(
            itemId: '1',
            title: 'Test',
            username: 'u',
            categories: {HealthCategory.weak},
            detail: '密码强度不足',
          ),
          HealthFinding(
            itemId: '2',
            title: 'Foo',
            username: 'v',
            categories: {HealthCategory.reused},
            detail: '与其他条目重复',
          ),
        ],
    score: score,
    categoryCounts: {HealthCategory.weak: 1, HealthCategory.reused: 1},
  );
}

void main() {
  group('HealthPage', () {
    testWidgets('显示评分和发现列表', (tester) async {
      final services = AppServices.fake(
        hasVault: true,
        unlocked: true,
        analyzePasswordHealthOverride: () async => _fakeReport(),
      );

      await tester.pumpWidget(
        MaterialApp(home: HealthPage(services: services)),
      );
      await tester.pumpAndSettle();

      expect(find.text('60'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);
      expect(find.text('Foo'), findsOneWidget);
      expect(find.text('共 3 条记录'), findsOneWidget);
    });

    testWidgets('空状态显示健康提示', (tester) async {
      final services = AppServices.fake(
        hasVault: true,
        unlocked: true,
        analyzePasswordHealthOverride: () async =>
            _fakeReport(findings: [], score: 100),
      );

      await tester.pumpWidget(
        MaterialApp(home: HealthPage(services: services)),
      );
      await tester.pumpAndSettle();

      expect(find.text('密码库很健康'), findsOneWidget);
      expect(find.text('没有发现安全风险'), findsOneWidget);
    });

    testWidgets('错误状态显示重试按钮', (tester) async {
      final services = AppServices.fake(
        hasVault: true,
        unlocked: true,
        analyzePasswordHealthOverride: () async => throw Exception('fail'),
      );

      await tester.pumpWidget(
        MaterialApp(home: HealthPage(services: services)),
      );
      await tester.pumpAndSettle();

      expect(find.text('分析失败，请重试'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });
}
