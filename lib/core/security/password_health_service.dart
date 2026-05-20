import 'master_password_policy.dart';

enum HealthCategory { weak, reused, stale, similar, neverEdited }

class HealthFinding {
  const HealthFinding({
    required this.itemId,
    required this.title,
    required this.username,
    required this.categories,
    required this.detail,
  });

  final String itemId;
  final String title;
  final String username;
  final Set<HealthCategory> categories;
  final String detail;

  int get severity {
    if (categories.contains(HealthCategory.weak)) return 0;
    if (categories.contains(HealthCategory.reused)) return 1;
    if (categories.contains(HealthCategory.stale)) return 2;
    if (categories.contains(HealthCategory.similar)) return 3;
    return 4;
  }

  @override
  String toString() => 'HealthFinding($itemId: $detail, categories: $categories)';
}

class HealthReport {
  const HealthReport({
    required this.totalItems,
    required this.findings,
    required this.score,
    required this.categoryCounts,
  });

  final int totalItems;
  final List<HealthFinding> findings;
  final int score;
  final Map<HealthCategory, int> categoryCounts;
}

class PasswordHealthService {
  static const _staleThresholdDays = 365;

  HealthReport analyze({
    required List<Map<String, String?>> decryptedItems,
  }) {
    final reusedMap = _checkReused(decryptedItems);
    final findings = <HealthFinding>[];

    for (final item in decryptedItems) {
      final id = item['id']!;
      final password = item['password'] ?? '';
      final title = item['title'] ?? '';
      final website = item['website'];
      final updatedAt = int.parse(item['updatedAt'] ?? '0');
      final createdAt = int.parse(item['createdAt'] ?? '0');
      final username = item['username'] ?? '';

      final categories = <HealthCategory>{};
      categories.addAll(_checkWeak(password));
      categories.addAll(reusedMap[id] ?? {});
      categories.addAll(_checkStale(updatedAt));
      categories.addAll(_checkSimilar(password, title, website));
      categories.addAll(_checkNeverEdited(updatedAt, createdAt));

      if (categories.isNotEmpty) {
        findings.add(HealthFinding(
          itemId: id,
          title: title,
          username: username,
          categories: categories,
          detail: _buildDetail(categories),
        ));
      }
    }

    findings.sort((a, b) => a.severity.compareTo(b.severity));

    final categoryCounts = <HealthCategory, int>{};
    for (final f in findings) {
      for (final c in f.categories) {
        categoryCounts[c] = (categoryCounts[c] ?? 0) + 1;
      }
    }

    final score = _calculateScore(categoryCounts);

    return HealthReport(
      totalItems: decryptedItems.length,
      findings: findings,
      score: score,
      categoryCounts: categoryCounts,
    );
  }

  static Set<HealthCategory> _checkWeak(String password) {
    final categories = <HealthCategory>{};
    final result = MasterPasswordPolicy.evaluate(password);
    if (!result.isAcceptable) {
      categories.add(HealthCategory.weak);
    }
    return categories;
  }

  static Map<String, Set<HealthCategory>> _checkReused(
    List<Map<String, String?>> items,
  ) {
    final passwordMap = <String, List<String>>{};
    for (final item in items) {
      final pw = item['password'];
      if (pw == null || pw.isEmpty) continue;
      passwordMap.putIfAbsent(pw, () => []).add(item['id']!);
    }
    final affected = <String, Set<HealthCategory>>{};
    for (final entry in passwordMap.entries) {
      if (entry.value.length > 1) {
        for (final id in entry.value) {
          affected.putIfAbsent(id, () => {}).add(HealthCategory.reused);
        }
      }
    }
    return affected;
  }

  static Set<HealthCategory> _checkStale(int updatedAt) {
    final categories = <HealthCategory>{};
    final ageMs = DateTime.now().millisecondsSinceEpoch - updatedAt;
    final ageDays = ageMs / (1000 * 60 * 60 * 24);
    if (ageDays > _staleThresholdDays) {
      categories.add(HealthCategory.stale);
    }
    return categories;
  }

  static Set<HealthCategory> _checkSimilar(
    String password, String title, String? website,
  ) {
    final categories = <HealthCategory>{};
    final lower = password.toLowerCase();
    for (final token in [title.toLowerCase(), (website ?? '').toLowerCase()]) {
      if (token.length < 3) continue;
      if (lower.contains(token)) {
        categories.add(HealthCategory.similar);
        break;
      }
    }
    return categories;
  }

  static Set<HealthCategory> _checkNeverEdited(int updatedAt, int createdAt) {
    if (updatedAt == createdAt) {
      return {HealthCategory.neverEdited};
    }
    return {};
  }

  static int _calculateScore(Map<HealthCategory, int> counts) {
    var score = 100;
    score -= (counts[HealthCategory.weak] ?? 0) * 20;
    score -= (counts[HealthCategory.reused] ?? 0) * 15;
    score -= (counts[HealthCategory.stale] ?? 0) * 5;
    score -= (counts[HealthCategory.similar] ?? 0) * 5;
    score -= (counts[HealthCategory.neverEdited] ?? 0) * 2;
    return score.clamp(0, 100);
  }

  static String _buildDetail(Set<HealthCategory> categories) {
    final parts = <String>[];
    if (categories.contains(HealthCategory.weak)) parts.add('密码强度不足');
    if (categories.contains(HealthCategory.reused)) parts.add('与其他条目重复');
    if (categories.contains(HealthCategory.stale)) parts.add('超过365天未更新');
    if (categories.contains(HealthCategory.similar)) parts.add('包含标题或网站名');
    if (categories.contains(HealthCategory.neverEdited)) parts.add('从未修改');
    return parts.join('；');
  }
}
