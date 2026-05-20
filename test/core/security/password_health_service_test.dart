import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/security/password_health_service.dart';

void main() {
  group('PasswordHealthService', () {
    test('弱密码被检测', () {
      final service = PasswordHealthService();
      final report = service.analyze(decryptedItems: [
        {
          'id': '1',
          'title': 'Test',
          'username': 'u',
          'password': '123456',
          'updatedAt': '${DateTime.now().millisecondsSinceEpoch}',
          'createdAt': '${DateTime.now().millisecondsSinceEpoch}',
        },
      ]);
      expect(report.findings.length, 1);
      expect(report.findings.first.categories, contains(HealthCategory.weak));
      expect(report.score, lessThan(100));
    });

    test('两个条目相同密码被检测为 reused', () {
      final service = PasswordHealthService();
      final now = DateTime.now().millisecondsSinceEpoch;
      final report = service.analyze(decryptedItems: [
        {
          'id': '1',
          'title': 'A',
          'username': 'u',
          'password': 'StrongP@ss1',
          'updatedAt': '$now',
          'createdAt': '$now',
        },
        {
          'id': '2',
          'title': 'B',
          'username': 'v',
          'password': 'StrongP@ss1',
          'updatedAt': '$now',
          'createdAt': '$now',
        },
      ]);
      expect(
        report.findings
            .where((f) => f.categories.contains(HealthCategory.reused))
            .length,
        2,
      );
    });

    test('超过365天密码被检测为 stale', () {
      final service = PasswordHealthService();
      final oldDate =
          DateTime.now().subtract(const Duration(days: 400)).millisecondsSinceEpoch;
      final report = service.analyze(decryptedItems: [
        {
          'id': '1',
          'title': 'X',
          'username': 'u',
          'password': 'StrongP@ss1',
          'updatedAt': '$oldDate',
          'createdAt': '$oldDate',
        },
      ]);
      expect(report.findings.first.categories, contains(HealthCategory.stale));
    });

    test('密码包含标题被检测为 similar', () {
      final service = PasswordHealthService();
      final now = DateTime.now().millisecondsSinceEpoch;
      final report = service.analyze(decryptedItems: [
        {
          'id': '1',
          'title': 'Google',
          'username': 'u',
          'password': 'myGoogle123!',
          'updatedAt': '$now',
          'createdAt': '$now',
        },
      ]);
      expect(report.findings.first.categories, contains(HealthCategory.similar));
    });

    test('从未更新被检测', () {
      final service = PasswordHealthService();
      final now = DateTime.now().millisecondsSinceEpoch;
      final report = service.analyze(decryptedItems: [
        {
          'id': '1',
          'title': 'X',
          'username': 'u',
          'password': 'StrongP@ss1',
          'updatedAt': '$now',
          'createdAt': '$now',
        },
      ]);
      expect(
        report.findings.first.categories,
        contains(HealthCategory.neverEdited),
      );
    });

    test('强唯一密码无发现', () {
      final service = PasswordHealthService();
      final now = DateTime.now().millisecondsSinceEpoch;
      final report = service.analyze(decryptedItems: [
        {
          'id': '1',
          'title': 'Bank',
          'username': 'u',
          'password': 'CorrectHorseBatteryStaple99!',
          'updatedAt': '$now',
          'createdAt': '${now - 1000}',
        },
      ]);
      expect(report.findings, isEmpty);
      expect(report.score, 100);
    });

    test('toString 不包含密码明文', () {
      final finding = HealthFinding(
        itemId: '1',
        title: 'Test',
        username: 'u',
        categories: {HealthCategory.weak},
        detail: 'too short',
      );
      expect(finding.toString(), isNot(contains('password')));
      expect(finding.toString(), isNot(contains('123456')));
    });

    test('空条目返回score=100', () {
      final service = PasswordHealthService();
      final report = service.analyze(decryptedItems: []);
      expect(report.score, 100);
      expect(report.totalItems, 0);
      expect(report.findings, isEmpty);
    });

    test('一个条目可以有多个分类', () {
      final service = PasswordHealthService();
      final now = DateTime.now().millisecondsSinceEpoch;
      final report = service.analyze(decryptedItems: [
        {
          'id': '1',
          'title': 'MySite',
          'username': 'u',
          'password': 'MySite',
          'updatedAt': '$now',
          'createdAt': '$now',
        },
      ]);
      final finding = report.findings.first;
      expect(finding.categories.length, greaterThanOrEqualTo(2));
    });

    test('sortOrder: weak (0) < reused (1) < neverEdited (4)', () {
      final weak = HealthFinding(
        itemId: '1',
        title: 'A',
        username: 'u',
        categories: {HealthCategory.weak},
        detail: 'w',
      );
      final reused = HealthFinding(
        itemId: '2',
        title: 'B',
        username: 'u',
        categories: {HealthCategory.reused},
        detail: 'r',
      );
      final neverEdit = HealthFinding(
        itemId: '3',
        title: 'C',
        username: 'u',
        categories: {HealthCategory.neverEdited},
        detail: 'n',
      );
      expect(weak.sortOrder, lessThan(reused.sortOrder));
      expect(reused.sortOrder, lessThan(neverEdit.sortOrder));
    });
  });
}
