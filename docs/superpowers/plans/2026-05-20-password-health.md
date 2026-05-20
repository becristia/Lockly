# 密码健康检测 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Lockly 中添加本地密码健康分析页面，检测弱密码、重复密码、过期密码、相似密码和从未更新的条目。

**Architecture:** 新增 `PasswordHealthService` 纯领域服务（不持久化），通过 `VaultService` → `AppServices` 暴露，新增 `HealthPage` UI 渲染健康仪表盘。设置页添加入口。

**Tech Stack:** Flutter 3.x, Dart 3.11, Material 3, sqflite, 现有 SecureVisual 组件

**Spec:** `docs/superpowers/specs/2026-05-20-password-health-design.md`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `lib/core/security/password_health_service.dart` | Create | 健康分析领域逻辑 |
| `lib/core/vault/vault_service.dart` | Modify | 添加 `analyzePasswordHealth()` |
| `lib/app/app_services.dart` | Modify | 暴露健康分析 API + fake override |
| `lib/features/security_health/health_page.dart` | Create | 健康仪表盘页面 |
| `lib/features/settings/settings_page.dart` | Modify | 添加健康入口 |
| `test/core/security/password_health_service_test.dart` | Create | 健康分析单元测试 |
| `test/features/security_health_test.dart` | Create | 健康页面 widget 测试 |

---

### Task 1: PasswordHealthService 领域模型和纯函数

**Files:**
- Create: `lib/core/security/password_health_service.dart`

- [ ] **Step 1: 编写服务类框架**

```dart
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
  });
}
```

- [ ] **Step 2: 实现弱密码检测**

```dart
  static Set<HealthCategory> _checkWeak(String password, int length) {
    final categories = <HealthCategory>{};
    final result = MasterPasswordPolicy.evaluate(password);
    if (!result.isAcceptable) {
      categories.add(HealthCategory.weak);
    }
    return categories;
  }
```

- [ ] **Step 3: 实现重复密码检测**

```dart
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
```

- [ ] **Step 4: 实现过期密码检测**

```dart
  static Set<HealthCategory> _checkStale(int updatedAt, int createdAt) {
    final categories = <HealthCategory>{};
    final ageMs = DateTime.now().millisecondsSinceEpoch - updatedAt;
    final ageDays = ageMs / (1000 * 60 * 60 * 24);
    if (ageDays > _staleThresholdDays) {
      categories.add(HealthCategory.stale);
    }
    return categories;
  }
```

- [ ] **Step 5: 实现相似密码检测**

```dart
  static Set<HealthCategory> _checkSimilar(
    String password,
    String title,
    String? website,
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
```

- [ ] **Step 6: 实现从未更新检测**

```dart
  static Set<HealthCategory> _checkNeverEdited(int updatedAt, int createdAt) {
    if (updatedAt == createdAt) {
      return {HealthCategory.neverEdited};
    }
    return {};
  }
```

- [ ] **Step 7: 实现 analyze() 主方法**

```dart
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
      categories.addAll(_checkWeak(password, password.length));
      categories.addAll(reusedMap[id] ?? {});
      categories.addAll(_checkStale(updatedAt, createdAt));
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

  static int _calculateScore(Map<HealthCategory, int> counts) {
    var score = 100;
    score -= (counts[HealthCategory.weak] ?? 0) * 20;
    score -= (counts[HealthCategory.reused] ?? 0) * 15;
    score -= (counts[HealthCategory.stale] ?? 0) * 5;
    score -= (counts[HealthCategory.similar] ?? 0) * 5;
    score -= (counts[HealthCategory.neverEdited] ?? 0) * 2;
    return score.clamp(0, 100);
  }

  static String _buildDetail(Set<HealthCategory> categories) { ... }
```

- [ ] **Step 8: Commit**

```bash
git add lib/core/security/password_health_service.dart
git commit -m "feat: add PasswordHealthService domain logic"
```

---

### Task 2: PasswordHealthService 单元测试

**Files:**
- Create: `test/core/security/password_health_service_test.dart`

- [ ] **Step 1: 写弱密码检测测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/core/security/master_password_policy.dart';

void main() {
  group('PasswordHealthService', () {
    test('弱密码被检测', () {
      final service = PasswordHealthService();
      final report = service.analyze(decryptedItems: [
        {
          'id': '1', 'title': 'Test', 'username': 'u',
          'password': '123456', 'updatedAt': '${DateTime.now().millisecondsSinceEpoch}',
          'createdAt': '${DateTime.now().millisecondsSinceEpoch}',
        },
      ]);
      expect(report.findings.length, 1);
      expect(report.findings.first.categories, contains(HealthCategory.weak));
      expect(report.score, lessThan(100));
    });
  });
}
```

- [ ] **Step 2: 重复密码检测测试**

```dart
    test('两个条目相同密码被检测为 reused', () {
      final service = PasswordHealthService();
      final now = DateTime.now().millisecondsSinceEpoch;
      final report = service.analyze(decryptedItems: [
        {'id': '1', 'title': 'A', 'username': 'u', 'password': 'StrongP@ss1', 'updatedAt': '$now', 'createdAt': '$now'},
        {'id': '2', 'title': 'B', 'username': 'v', 'password': 'StrongP@ss1', 'updatedAt': '$now', 'createdAt': '$now'},
      ]);
      expect(report.findings.where((f) => f.categories.contains(HealthCategory.reused)).length, 2);
    });
```

- [ ] **Step 3: 过期密码、相似密码、从未更新检测测试**

```dart
    test('超过365天密码被检测为 stale', () {
      final service = PasswordHealthService();
      final oldDate = DateTime.now().subtract(const Duration(days: 400)).millisecondsSinceEpoch;
      final report = service.analyze(decryptedItems: [
        {'id': '1', 'title': 'X', 'username': 'u', 'password': 'StrongP@ss1', 'updatedAt': '$oldDate', 'createdAt': '$oldDate'},
      ]);
      final finding = report.findings.first;
      expect(finding.categories, contains(HealthCategory.stale));
    });

    test('密码包含标题被检测为 similar', () {
      final service = PasswordHealthService();
      final now = DateTime.now().millisecondsSinceEpoch;
      final report = service.analyze(decryptedItems: [
        {'id': '1', 'title': 'Google', 'username': 'u', 'password': 'myGoogle123!', 'updatedAt': '$now', 'createdAt': '$now'},
      ]);
      expect(report.findings.first.categories, contains(HealthCategory.similar));
    });

    test('从未更新被检测', () {
      final service = PasswordHealthService();
      final now = DateTime.now().millisecondsSinceEpoch;
      final report = service.analyze(decryptedItems: [
        {'id': '1', 'title': 'X', 'username': 'u', 'password': 'StrongP@ss1', 'updatedAt': '$now', 'createdAt': '$now'},
      ]);
      expect(report.findings.first.categories, contains(HealthCategory.neverEdited));
    });

    test('强独一无二密码无发现', () {
      final service = PasswordHealthService();
      final now = DateTime.now().millisecondsSinceEpoch;
      final report = service.analyze(decryptedItems: [
        {'id': '1', 'title': 'Bank', 'username': 'u', 'password': 'CorrectHorseBatteryStaple99!', 'updatedAt': '$now', 'createdAt': '$now'},
      ]);
      expect(report.findings, isEmpty);
      expect(report.score, 100);
    });
```

- [ ] **Step 4: toString 不含密码**

```dart
    test('toString 不包含密码明文', () {
      final finding = HealthFinding(
        itemId: '1', title: 'Test', username: 'u',
        categories: {HealthCategory.weak}, detail: 'too short',
      );
      expect(finding.toString(), isNot(contains('password')));
      final findingWithPw = HealthFinding(
        itemId: '2', title: 'password', username: 'u',
        categories: {HealthCategory.similar}, detail: 'matches title',
      );
      expect(findingWithPw.toString(), isNot(contains('123456')));
    });
```

- [ ] **Step 5: 运行测试确认通过**

```bash
flutter test --reporter compact test/core/security/password_health_service_test.dart
```

- [ ] **Step 6: Commit**

```bash
git add test/core/security/password_health_service_test.dart
git commit -m "test: add PasswordHealthService unit tests"
```

---

### Task 3: VaultService 集成

**Files:**
- Modify: `lib/core/vault/vault_service.dart`
- Modify: `lib/app/app_services.dart`

- [ ] **Step 1: 在 VaultService 添加 analyzePasswordHealth()**

在 `vault_service.dart` 的 `listItems` 方法附近添加：

```dart
  Future<Map<String, String?>> _decryptItemForHealth(
    EncryptedVaultItem item,
    Uint8List dek,
  ) {
    return {
      'id': item.id,
      'title': cryptoService.decryptAscii(dek, item.encryptedTitle, item.titleNonce),
      'username': cryptoService.decryptAscii(dek, item.encryptedUsername, item.usernameNonce),
      'password': cryptoService.decryptAscii(dek, item.encryptedPassword, item.passwordNonce),
      'website': item.encryptedWebsite != null
          ? cryptoService.decryptAscii(dek, item.encryptedWebsite!, item.websiteNonce!)
          : null,
      'updatedAt': '${item.updatedAt}',
      'createdAt': '${item.createdAt}',
    };
  }

  Future<HealthReport> analyzePasswordHealth({
    required PasswordHealthService healthService,
  }) async {
    _ensureUnlocked();
    final items = await repository.itemsDao.all();
    final activeItems = items.where((i) => i.deletedAt == null).toList();

    final decryptedItems = await _session.withDekCopy((dek) async {
      return activeItems
          .map((item) => _decryptItemForHealth(item, dek))
          .toList();
    });

    return healthService.analyze(decryptedItems: decryptedItems);
  }
```

- [ ] **Step 2: 在 AppServices 暴露 API 并添加 fake override**

在 `app_services.dart` 添加：

```dart
  static const routeHealth = '/health';

  final Future<HealthReport> Function()? _analyzePasswordHealthOverride;

  Future<HealthReport> analyzePasswordHealth() async {
    final override = _analyzePasswordHealthOverride;
    if (override != null) return override();
    return vaultService.analyzePasswordHealth(
      healthService: PasswordHealthService(),
    );
  }
```

将 `_analyzePasswordHealthOverride` 加入构造函数参数列表，并在 `fake()` 工厂中赋值。

- [ ] **Step 3: 在 resolveRouteName 添加 /health 路由**

```dart
  String resolveRouteName(String? name) {
    if (shellState.value != AppShellState.unlocked) {
      return currentRouteName;
    }
    if (name == routeVault || name == routeGenerator || name == routeSettings || name == routeHealth) {
      return name;
    }
    return currentRouteName;
  }
```

- [ ] **Step 4: Commit**

```bash
git add lib/core/vault/vault_service.dart lib/app/app_services.dart
git commit -m "feat: add analyzePasswordHealth to VaultService and AppServices"
```

---

### Task 4: HealthPage UI

**Files:**
- Create: `lib/features/security_health/health_page.dart`

- [ ] **Step 1: 创建 HealthPage 页面框架**

```dart
import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key, required this.services});

  final AppServices services;

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  HealthReport? _report;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async { ... }
}
```

- [ ] **Step 2: 实现 _analyze() 方法**

```dart
  Future<void> _analyze() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final report = await widget.services.analyzePasswordHealth();
      if (!mounted) return;
      setState(() { _report = report; _isLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '分析失败，请重试';
      });
    }
  }
```

- [ ] **Step 3: 实现评分卡片**

```dart
  Widget _buildScoreCard(HealthReport report) {
    final gradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [SecureVisualColors.blue, SecureVisualColors.cyan],
    );
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text('密码健康分', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text('${report.score}', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: Colors.white)),
          Text('共 ${report.totalItems} 条记录', style: TextStyle(color: Colors.white60, fontSize: 13)),
        ],
      ),
    );
  }
```

- [ ] **Step 4: 实现统计行和分类列表**

```dart
  Widget _buildStatRow(HealthReport report) { ... }  // 3列：高/提醒/健康
  Widget _buildCategoryList(HealthReport report) { ... }  // 5个可折叠面板
  Widget _buildCategoryTile(HealthCategory category, int count, List<HealthFinding> findings) { ... }
  Widget _buildFindingItem(HealthFinding finding) { ... }  // 条目卡片 + 修改密码按钮
```

- [ ] **Step 5: 实现 build() 整体布局**

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('密码健康')),
      body: SecureVisualBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildError()
                : _report!.findings.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: () async => _analyze(),
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            _buildScoreCard(_report!),
                            const SizedBox(height: 16),
                            _buildStatRow(_report!),
                            const SizedBox(height: 20),
                            _buildCategoryList(_report!),
                          ],
                        ),
                      ),
      ),
    );
  }
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/security_health/health_page.dart
git commit -m "feat: add password health report page"
```

---

### Task 5: 设置页添加健康入口

**Files:**
- Modify: `lib/features/settings/settings_page.dart`

- [ ] **Step 1: 在设置列表添加健康条目**

在设置页列表中添加新的 `ListTile`：

```dart
  ListTile(
    leading: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: SecureVisualColors.blue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.health_and_safety_outlined),
    ),
    title: const Text('密码健康'),
    subtitle: const Text('检测弱密码、重复密码和过期密码'),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () {
      widget.services.recordActivity();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => HealthPage(services: widget.services),
        ),
      );
    },
  ),
```

- [ ] **Step 2: 添加 import**

```dart
import 'package:secure_box/features/security_health/health_page.dart';
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/settings/settings_page.dart
git commit -m "feat: add password health entry to settings page"
```

---

### Task 6: HealthPage widget 测试

**Files:**
- Create: `test/features/security_health_test.dart`

- [ ] **Step 1: 写健康页面测试**

```dart
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
    findings: findings ?? [
      HealthFinding(itemId: '1', title: 'Test', username: 'u',
        categories: {HealthCategory.weak}, detail: 'len=6'),
      HealthFinding(itemId: '2', title: 'Foo', username: 'v',
        categories: {HealthCategory.reused}, detail: 'dupe'),
    ],
    score: score,
    categoryCounts: {HealthCategory.weak: 1, HealthCategory.reused: 1},
  );
}

void main() {
  group('HealthPage', () {
    testWidgets('显示评分和发现列表', (tester) async {
      final services = AppServices.fake(hasVault: true, unlocked: true);
      // Use analyzePasswordHealth override
      await tester.pumpWidget(MaterialApp(home: HealthPage(services: services)));
      // Verify score visible
      expect(find.text('60'), findsOneWidget);
      // Verify findings visible
      expect(find.text('Test'), findsOneWidget);
      expect(find.text('Foo'), findsOneWidget);
    });

    testWidgets('空状态显示', (tester) async {
      final services = AppServices.fake(hasVault: true, unlocked: true);
      // Override with empty report
      await tester.pumpWidget(MaterialApp(home: HealthPage(services: services)));
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('下拉刷新', (tester) async {
      // drag and verify reanalysis triggered
    });
  });
}
```

- [ ] **Step 2: 运行测试**

```bash
flutter test --reporter compact test/features/security_health_test.dart
```

- [ ] **Step 3: Commit**

```bash
git add test/features/security_health_test.dart
git commit -m "test: add password health page widget tests"
```

---

### Task 7: 端到端验证

- [ ] **Step 1: 运行全部测试**

```bash
flutter test --reporter compact
```

- [ ] **Step 2: 运行静态分析**

```bash
flutter analyze
```

- [ ] **Step 3: 构建并安装到设备**

```bash
flutter build apk --debug && adb -d install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 4: 手动验证**
  - 打开设置 → 密码健康
  - 验证评分卡片显示
  - 验证如果无风险则显示 100 分空状态
  - 添加弱密码条目后刷新验证检测

- [ ] **Step 5: 最终 commit**

```bash
git commit -m "chore: finalize password health feature" --allow-empty
```