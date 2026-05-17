# 安全性和可用性升级实施计划

**日期：** 2026-05-17

> **面向智能体工作者：** 必需的子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 来逐步实现此计划。步骤使用复选框（`- [ ]`）语法进行跟踪。

**目标：** 通过添加本地密码健康检查、更严格敏感明文生命周期处理和基于策略的密码生成器，将当前安全的 MVP 转变为更实用的本地密码管理器。

**架构：** 保持所有分析为本地运行，且仅在保险库解锁后才运行。在 `lib/core/security/` 和 `lib/core/password_generator/` 下添加小型领域服务，通过 `AppServices` 暴露它们，并在现有 Flutter 功能页面中呈现，无需添加云同步、远程 API 或明文持久化索引。每个模块使用 TDD 并在每个任务后提交。

**技术栈：** Flutter 3.41、Dart 3.11、Material 3、通过现有 DAO 的 SQLite、`cryptography`、`hashlib`、现有 `AppServices` 外观、Flutter 小组件测试。

---

## 参考资料

- 评估报告：`docs/superpowers/specs/2026-05-17-project-evaluation-report.md`
- 现有生成器：`lib/core/password_generator/password_generator.dart`
- 现有主密码策略：`lib/core/security/master_password_policy.dart`
- 现有保险库服务：`lib/core/vault/vault_service.dart`
- 现有剪贴板/锁定测试：`test/core/security/clipboard_and_lock_test.dart`
- 现有生成器测试：`test/core/password_generator/password_generator_test.dart`

---

## 文件地图

- 创建 `lib/core/security/password_health_service.dart`：本地唯一的密码健康分析，用于检测弱密码、重复密码、过期密码以及与标题/网站相似的密码。
- 修改 `lib/core/vault/vault_service.dart`：为健康分析暴露已解锁的保险库条目，且不持久化明文索引。
- 修改 `lib/app/app_services.dart`：添加 `analyzePasswordHealth()` 和用于小组件测试的伪替代。
- 创建 `lib/features/security_health/security_health_page.dart`：面向用户的健康报告页面。
- 修改 `lib/features/vault_shell/vault_shell_page.dart`：为健康页添加底部导航目标。
- 修改 `lib/core/password_generator/password_generator.dart`：添加生成器策略和可读密码短语生成。
- 修改 `lib/features/password_generator/password_generator_page.dart`：添加预设、密码短语模式、复制操作和强度说明。
- 修改 `lib/features/vault_detail/vault_detail_page.dart`：当页面被覆盖、进入后台或销毁时清除可见的密码。
- 修改 `lib/features/vault_edit/vault_edit_page.dart`：在取消/保存/销毁时清除敏感控制器，并在生命周期变化时隐藏密码。
- 修改 `lib/core/clipboard/clipboard_service.dart`：为 UI 和测试暴露待处理密码清理状态。
- 测试 `test/core/security/password_health_service_test.dart`：健康分析器行为。
- 测试 `test/features/security_health_test.dart`：健康页面和导航行为。
- 测试 `test/core/password_generator/password_generator_test.dart`：策略和密码短语行为。
- 测试 `test/features/generator_settings_test.dart`：生成器页面预设/复制/保存行为。
- 测试 `test/features/vault_item_flow_test.dart`：详情/编辑敏感 UI 状态行为。
- 测试 `test/core/security/clipboard_and_lock_test.dart`：生命周期清理和待处理剪贴板状态。

---

### 任务 1：添加本地密码健康分析

**文件：**
- 创建：`lib/core/security/password_health_service.dart`
- 修改：`lib/core/vault/vault_service.dart`
- 修改：`lib/app/app_services.dart`
- 测试：`test/core/security/password_health_service_test.dart`
- 测试：`test/core/vault/vault_service_test.dart`

- [ ] **步骤 1：编写失败的健康服务测试**

创建 `test/core/security/password_health_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/data/models/password_entry.dart';

void main() {
  group('PasswordHealthService', () {
    test('detects weak reused stale and title-similar passwords', () {
      final service = PasswordHealthService(now: DateTime.utc(2026, 5, 17));
      final report = service.analyze([
        PasswordHealthInput(
          id: '1',
          entry: PasswordEntry(
            title: 'GitHub',
            website: 'https://github.com',
            username: 'a@example.com',
            password: 'password123456',
            notes: '',
            tags: const [],
          ),
          updatedAt: DateTime.utc(2023, 5, 1).millisecondsSinceEpoch,
        ),
        PasswordHealthInput(
          id: '2',
          entry: PasswordEntry(
            title: 'Mail',
            website: 'https://mail.example.com',
            username: 'a@example.com',
            password: 'password123456',
            notes: '',
            tags: const [],
          ),
          updatedAt: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
        ),
        PasswordHealthInput(
          id: '3',
          entry: PasswordEntry(
            title: 'Bank',
            website: 'https://bank.example.com',
            username: 'a@example.com',
            password: 'Bank2026!',
            notes: '',
            tags: const [],
          ),
          updatedAt: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
        ),
      ]);

      expect(report.totalItems, 3);
      expect(report.criticalCount, 2);
      expect(report.warningCount, 1);
      expect(report.findingFor('1').reasons, contains(PasswordHealthReason.weak));
      expect(report.findingFor('1').reasons, contains(PasswordHealthReason.reused));
      expect(report.findingFor('1').reasons, contains(PasswordHealthReason.stale));
      expect(report.findingFor('3').reasons, contains(PasswordHealthReason.similarToTitleOrSite));
    });

    test('does not persist or expose plaintext passwords in findings', () {
      final service = PasswordHealthService(now: DateTime.utc(2026, 5, 17));
      final report = service.analyze([
        PasswordHealthInput(
          id: 'secret-id',
          entry: PasswordEntry(
            title: 'Example',
            website: 'https://example.com',
            username: 'user',
            password: 'R9!vK2#pL8@qZ4',
            notes: '',
            tags: const [],
          ),
          updatedAt: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
        ),
      ]);

      expect(report.findings.single.toString(), isNot(contains('R9!vK2#pL8@qZ4')));
    });
  });
}
```

- [ ] **步骤 2：运行测试并验证失败**

运行：

```powershell
flutter test --reporter compact test\core\security\password_health_service_test.dart
```

预期：失败，因为 `password_health_service.dart` 不存在。

- [ ] **步骤 3：实现健康服务**

创建 `lib/core/security/password_health_service.dart`：

```dart
import 'package:secure_box/core/security/master_password_policy.dart';
import 'package:secure_box/data/models/password_entry.dart';

enum PasswordHealthSeverity { ok, warning, critical }

enum PasswordHealthReason {
  weak,
  reused,
  stale,
  similarToTitleOrSite,
}

class PasswordHealthInput {
  const PasswordHealthInput({
    required this.id,
    required this.entry,
    required this.updatedAt,
  });

  final String id;
  final PasswordEntry entry;
  final int updatedAt;
}

class PasswordHealthFinding {
  const PasswordHealthFinding({
    required this.id,
    required this.title,
    required this.website,
    required this.username,
    required this.severity,
    required this.reasons,
  });

  final String id;
  final String title;
  final String website;
  final String username;
  final PasswordHealthSeverity severity;
  final List<PasswordHealthReason> reasons;

  @override
  String toString() {
    return 'PasswordHealthFinding(id: $id, title: $title, severity: $severity, reasons: $reasons)';
  }
}

class PasswordHealthReport {
  const PasswordHealthReport({
    required this.totalItems,
    required this.findings,
  });

  final int totalItems;
  final List<PasswordHealthFinding> findings;

  int get criticalCount => findings
      .where((finding) => finding.severity == PasswordHealthSeverity.critical)
      .length;

  int get warningCount => findings
      .where((finding) => finding.severity == PasswordHealthSeverity.warning)
      .length;

  PasswordHealthFinding findingFor(String id) {
    return findings.singleWhere((finding) => finding.id == id);
  }
}

class PasswordHealthService {
  PasswordHealthService({DateTime? now}) : _now = now ?? DateTime.now();

  static const _staleAfter = Duration(days: 365);

  final DateTime _now;

  PasswordHealthReport analyze(List<PasswordHealthInput> inputs) {
    final counts = <String, int>{};
    for (final input in inputs) {
      counts.update(input.entry.password, (value) => value + 1, ifAbsent: () => 1);
    }

    final findings = <PasswordHealthFinding>[];
    for (final input in inputs) {
      final reasons = <PasswordHealthReason>[];
      final policy = MasterPasswordPolicy.evaluate(input.entry.password);
      if (!policy.isAcceptable) {
        reasons.add(PasswordHealthReason.weak);
      }
      if ((counts[input.entry.password] ?? 0) > 1) {
        reasons.add(PasswordHealthReason.reused);
      }
      final updated = DateTime.fromMillisecondsSinceEpoch(input.updatedAt);
      if (_now.difference(updated) >= _staleAfter) {
        reasons.add(PasswordHealthReason.stale);
      }
      if (_isSimilarToTitleOrSite(input.entry)) {
        reasons.add(PasswordHealthReason.similarToTitleOrSite);
      }
      if (reasons.isEmpty) {
        continue;
      }

      final severity = reasons.contains(PasswordHealthReason.weak) ||
              reasons.contains(PasswordHealthReason.reused)
          ? PasswordHealthSeverity.critical
          : PasswordHealthSeverity.warning;

      findings.add(PasswordHealthFinding(
        id: input.id,
        title: input.entry.title,
        website: input.entry.website,
        username: input.entry.username,
        severity: severity,
        reasons: List.unmodifiable(reasons),
      ));
    }

    return PasswordHealthReport(
      totalItems: inputs.length,
      findings: List.unmodifiable(findings),
    );
  }

  bool _isSimilarToTitleOrSite(PasswordEntry entry) {
    final password = entry.password.toLowerCase();
    final tokens = <String>[
      ...entry.title.toLowerCase().split(RegExp(r'[^a-z0-9]+')),
      ...entry.website.toLowerCase().split(RegExp(r'[^a-z0-9]+')),
    ].where((token) => token.length >= 4).toList(growable: false);
    return tokens.any(password.contains);
  }
}
```

- [ ] **步骤 4：添加保险库/应用服务集成测试**

在现有项目 CRUD 测试之后，向 `test/core/vault/vault_service_test.dart` 追加测试：

```dart
  test('password health analysis decrypts active items only', () async {
    final harness = await _createUnlockedHarness();
    final staleUpdatedAt = DateTime.now()
        .subtract(const Duration(days: 400))
        .millisecondsSinceEpoch;

    final firstId = await harness.service.createItem(PasswordEntry(
      title: 'GitHub',
      website: 'https://github.com',
      username: 'a@example.com',
      password: 'password123456',
      notes: '',
      tags: const [],
    ));
    await harness.repository.itemsDao.updateActive(
      (await harness.repository.itemsDao.byId(firstId))!.copyWith(updatedAt: staleUpdatedAt),
    );
    await harness.service.createItem(PasswordEntry(
      title: 'Mail',
      website: 'https://mail.example.com',
      username: 'a@example.com',
      password: 'password123456',
      notes: '',
      tags: const [],
    ));

    final report = await harness.service.analyzePasswordHealth();

    expect(report.totalItems, 2);
    expect(report.criticalCount, 2);
  });
```

如果 `EncryptedVaultItem.copyWith` 不存在，请在 `lib/data/models/encrypted_vault_item.dart` 中为其添加所有现有构造函数属性的字段。

- [ ] **步骤 5：实现服务集成**

修改 `lib/core/vault/vault_service.dart`：

```dart
import 'package:secure_box/core/security/password_health_service.dart';
```

在 `listItems()` 附近添加此公共方法：

```dart
  Future<PasswordHealthReport> analyzePasswordHealth() async {
    _ensureUnlocked();
    await _verifyCurrentManifestWithActiveSession();
    final items = await repository.itemsDao.activeItems();
    final inputs = <PasswordHealthInput>[];
    for (final item in items) {
      final entry = await _decryptItem(item);
      inputs.add(PasswordHealthInput(
        id: item.id,
        entry: entry,
        updatedAt: item.updatedAt,
      ));
    }
    return PasswordHealthService().analyze(inputs);
  }
```

修改 `lib/app/app_services.dart`：

```dart
import 'package:secure_box/core/security/password_health_service.dart';
```

添加构造函数替代：

```dart
    Future<PasswordHealthReport> Function()? passwordHealthOverride,
```

存储它：

```dart
  final Future<PasswordHealthReport> Function()? _passwordHealthOverride;
```

添加方法：

```dart
  Future<PasswordHealthReport> analyzePasswordHealth() {
    final override = _passwordHealthOverride;
    if (override != null) {
      return override();
    }
    return vaultService.analyzePasswordHealth();
  }
```

- [ ] **步骤 6：运行聚焦测试并提交**

运行：

```powershell
dart format lib\core\security\password_health_service.dart lib\core\vault\vault_service.dart lib\app\app_services.dart test\core\security\password_health_service_test.dart test\core\vault\vault_service_test.dart
flutter test --reporter compact test\core\security\password_health_service_test.dart test\core\vault\vault_service_test.dart
```

预期：所有聚焦测试通过。

提交：

```powershell
git add lib\core\security\password_health_service.dart lib\core\vault\vault_service.dart lib\app\app_services.dart test\core\security\password_health_service_test.dart test\core\vault\vault_service_test.dart
git commit -m "feat: add local password health analysis"
```

---

### 任务 2：添加密码健康页面和导航

**文件：**
- 创建：`lib/features/security_health/security_health_page.dart`
- 修改：`lib/features/vault_shell/vault_shell_page.dart`
- 修改：`test/features/security_health_test.dart`
- 修改：`test/app/app_routing_test.dart`

- [ ] **步骤 1：编写失败的小组件件测试**

创建 `test/features/security_health_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/data/models/password_entry.dart';

void main() {
  testWidgets('health tab shows critical and warning findings', (tester) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'a@example.com',
          password: 'password123456',
          notes: '',
          tags: const [],
        ),
      ],
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.tap(find.byKey(const ValueKey('vault-shell-health-tab')));
    await tester.pumpAndSettle();

    expect(find.text('安全检查'), findsOneWidget);
    expect(find.textContaining('高风险'), findsWidgets);
    expect(find.textContaining('GitHub'), findsOneWidget);
  });
}
```

- [ ] **步骤 2：运行并验证失败**

运行：

```powershell
flutter test --reporter compact test\features\security_health_test.dart
```

预期：失败，因为健康标签/页面不存在。

- [ ] **步骤 3：实现页面**

创建 `lib/features/security_health/security_health_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/password_health_service.dart';

class SecurityHealthPage extends StatefulWidget {
  const SecurityHealthPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SecurityHealthPage> createState() => _SecurityHealthPageState();
}

class _SecurityHealthPageState extends State<SecurityHealthPage> {
  PasswordHealthReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.services.analyzePasswordHealth();
      if (!mounted) {
        return;
      }
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '无法完成本地安全检查，请重新解锁后再试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('安全检查')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 64),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _HealthMessage(title: '检查失败', message: _error!)
              else if (report != null) ...[
                _SummaryCard(report: report),
                const SizedBox(height: 16),
                if (report.findings.isEmpty)
                  const _HealthMessage(
                    title: '没有发现明显风险',
                    message: '当前密码没有重复、常见弱密码或长期未更新风险。',
                  )
                else
                  ...report.findings.map((finding) => _FindingTile(finding: finding)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});

  final PasswordHealthReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '共 ${report.totalItems} 条记录，${report.criticalCount} 个高风险，${report.warningCount} 个提醒',
          style: theme.textTheme.titleMedium,
        ),
      ),
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding});

  final PasswordHealthFinding finding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highRisk = finding.severity == PasswordHealthSeverity.critical;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        tileColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(
          highRisk ? Icons.error_outline_rounded : Icons.info_outline_rounded,
          color: highRisk ? theme.colorScheme.error : theme.colorScheme.tertiary,
        ),
        title: Text(finding.title),
        subtitle: Text(_reasonText(finding.reasons)),
      ),
    );
  }

  String _reasonText(List<PasswordHealthReason> reasons) {
    return reasons.map((reason) {
      return switch (reason) {
        PasswordHealthReason.weak => '常见弱密码',
        PasswordHealthReason.reused => '重复使用',
        PasswordHealthReason.stale => '长期未更新',
        PasswordHealthReason.similarToTitleOrSite => '与标题或网站相似',
      };
    }).join(' · ');
  }
}

class _HealthMessage extends StatelessWidget {
  const _HealthMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
        children: [
          Icon(Icons.health_and_safety_outlined, size: 36, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
```

- [ ] **步骤 4：添加底部导航标签**

修改 `lib/features/vault_shell/vault_shell_page.dart`：

```dart
import 'package:secure_box/features/security_health/security_health_page.dart';
```

更新 body switch：

```dart
      body: switch (_selectedIndex) {
        0 => VaultListPage(services: widget.services),
        1 => PasswordGeneratorPage(services: widget.services),
        2 => SecurityHealthPage(services: widget.services),
        _ => SettingsPage(services: widget.services),
      },
```

在设置之前添加目标：

```dart
          NavigationDestination(
            key: ValueKey('vault-shell-health-tab'),
            icon: Icon(Icons.health_and_safety_outlined),
            selectedIcon: Icon(Icons.health_and_safety_rounded),
            label: '安全',
          ),
```

- [ ] **步骤 5：运行聚焦测试并提交**

运行：

```powershell
dart format lib\features\security_health\security_health_page.dart lib\features\vault_shell\vault_shell_page.dart test\features\security_health_test.dart
flutter test --reporter compact test\features\security_health_test.dart test\app\app_routing_test.dart
```

预期：所有聚焦测试通过。

提交：

```powershell
git add lib\features\security_health\security_health_page.dart lib\features\vault_shell\vault_shell_page.dart test\features\security_health_test.dart test\app\app_routing_test.dart
git commit -m "feat: surface local password health report"
```

---

### 任务 3：产品化密码生成器策略

**文件：**
- 修改：`lib/core/password_generator/password_generator.dart`
- 修改：`lib/features/password_generator/password_generator_page.dart`
- 修改：`lib/app/app_services.dart`
- 测试：`test/core/password_generator/password_generator_test.dart`
- 测试：`test/features/generator_settings_test.dart`

- [ ] **步骤 1：添加失败的生成器策略测试**

追加到 `test/core/password_generator/password_generator_test.dart`：

```dart
  test('strong preset generates 24 characters with every class', () {
    final options = PasswordGeneratorOptions.strongPreset();
    final password = PasswordGenerator.forTesting(random: Random(1)).generate(options);

    expect(password, hasLength(24));
    expect(password, matches(RegExp(r'[a-z]')));
    expect(password, matches(RegExp(r'[A-Z]')));
    expect(password, matches(RegExp(r'\d')));
    expect(password, matches(RegExp(r'[^A-Za-z0-9]')));
  });

  test('readable passphrase preset generates four separated words and a number', () {
    final generator = PasswordGenerator.forTesting(random: Random(2));
    final password = generator.generate(PasswordGeneratorOptions.passphrasePreset());

    expect(password.split('-'), hasLength(5));
    expect(password, matches(RegExp(r'\d$')));
  });

  test('site compatible preset excludes symbols', () {
    final password = PasswordGenerator.forTesting(random: Random(3))
        .generate(PasswordGeneratorOptions.siteCompatiblePreset());

    expect(password, hasLength(20));
    expect(password, isNot(matches(RegExp(r'[^A-Za-z0-9]'))));
  });
```

- [ ] **步骤 2：运行并验证失败**

运行：

```powershell
flutter test --reporter compact test\core\password_generator\password_generator_test.dart
```

预期：失败，因为预设构造函数和密码短语生成不存在。

- [ ] **步骤 3：添加策略字段和预设构造函数**

修改 `lib/core/password_generator/password_generator.dart` 中的 `PasswordGeneratorOptions`：

```dart
enum PasswordGeneratorMode { randomCharacters, passphrase }
```

添加字段：

```dart
    this.mode = PasswordGeneratorMode.randomCharacters,
    this.wordCount = 4,
    this.separator = '-',
    this.appendNumber = false,
```

添加构造函数：

```dart
  factory PasswordGeneratorOptions.strongPreset() {
    return const PasswordGeneratorOptions(
      length: 24,
      lowercase: true,
      uppercase: true,
      numbers: true,
      symbols: true,
      excludeConfusing: true,
      requireEverySelectedClass: true,
    );
  }

  factory PasswordGeneratorOptions.siteCompatiblePreset() {
    return const PasswordGeneratorOptions(
      length: 20,
      lowercase: true,
      uppercase: true,
      numbers: true,
      symbols: false,
      excludeConfusing: true,
      requireEverySelectedClass: true,
    );
  }

  factory PasswordGeneratorOptions.passphrasePreset() {
    return const PasswordGeneratorOptions(
      mode: PasswordGeneratorMode.passphrase,
      length: 0,
      lowercase: true,
      uppercase: false,
      numbers: true,
      symbols: false,
      excludeConfusing: true,
      requireEverySelectedClass: false,
      wordCount: 4,
      separator: '-',
      appendNumber: true,
    );
  }
```

添加小型内部词表：

```dart
  static const List<String> _words = [
    'anchor',
    'forest',
    'silver',
    'river',
    'signal',
    'planet',
    'harbor',
    'window',
    'canvas',
    'rocket',
    'garden',
    'pencil',
  ];
```

在 `generate()` 中分支：

```dart
    if (options.mode == PasswordGeneratorMode.passphrase) {
      return _generatePassphrase(options);
    }
```

添加：

```dart
  String _generatePassphrase(PasswordGeneratorOptions options) {
    if (options.wordCount < 3) {
      throw const PasswordGeneratorException('Passphrase must contain at least three words');
    }
    final words = <String>[];
    while (words.length < options.wordCount) {
      words.add(_words[_random.nextInt(_words.length)]);
    }
    var phrase = words.join(options.separator);
    if (options.appendNumber) {
      phrase = '$phrase${_random.nextInt(10)}';
    }
    return phrase;
  }
```

- [ ] **步骤 4：添加 UI 预设和复制测试**

追加到 `test/features/generator_settings_test.dart`：

```dart
  testWidgets('generator exposes presets and copy action', (tester) async {
    final harness = await _createUnlockedAppHarness();
    await tester.pumpWidget(harness.app);
    await tester.tap(find.byKey(const ValueKey('vault-shell-generator-tab')));
    await tester.pumpAndSettle();

    expect(find.text('强密码'), findsOneWidget);
    expect(find.text('密码短语'), findsOneWidget);
    expect(find.text('兼容网站'), findsOneWidget);

    await tester.tap(find.text('密码短语'));
    await tester.pump();
    await tester.tap(find.text('生成密码'));
    await tester.pump();

    expect(find.text('复制'), findsOneWidget);
    expect(find.textContaining('密码短语'), findsWidgets);
  });
```

- [ ] **步骤 5：实现生成器 UI**

在 `PasswordGeneratorPage` 中添加：

```dart
enum _GeneratorPreset { strong, passphrase, compatible }
```

添加 `_selectedPreset` 状态和 `_applyPreset()` 方法：

```dart
  _GeneratorPreset _selectedPreset = _GeneratorPreset.strong;

  void _applyPreset(_GeneratorPreset preset) {
    widget.services.recordActivity();
    setState(() {
      _selectedPreset = preset;
      final options = switch (preset) {
        _GeneratorPreset.strong => PasswordGeneratorOptions.strongPreset(),
        _GeneratorPreset.passphrase => PasswordGeneratorOptions.passphrasePreset(),
        _GeneratorPreset.compatible => PasswordGeneratorOptions.siteCompatiblePreset(),
      };
      _length = options.length == 0 ? 24 : options.length;
      _lowercase = options.lowercase;
      _uppercase = options.uppercase;
      _numbers = options.numbers;
      _symbols = options.symbols;
      _excludeConfusing = options.excludeConfusing;
      _requireEverySelectedClass = options.requireEverySelectedClass;
      _generatedPassword = '';
      _errorText = null;
    });
  }
```

在长度控件上方添加预设 `SegmentedButton`，标签为 `强密码`、`密码短语`、`兼容网站`。

添加复制方法：

```dart
  Future<void> _copyGeneratedPassword() async {
    widget.services.recordActivity();
    if (_generatedPassword.isEmpty) {
      return;
    }
    final copied = await widget.services.copyPassword(_generatedPassword);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(copied ? '已复制，稍后会自动清理剪贴板。' : '复制失败，请重试。')),
    );
  }
```

当 `_generatedPassword.isNotEmpty` 时添加带有标签 `复制` 的 `FilledButton.tonalIcon`。

- [ ] **步骤 6：运行聚焦测试并提交**

运行：

```powershell
dart format lib\core\password_generator\password_generator.dart lib\features\password_generator\password_generator_page.dart lib\app\app_services.dart test\core\password_generator\password_generator_test.dart test\features\generator_settings_test.dart
flutter test --reporter compact test\core\password_generator\password_generator_test.dart test\features\generator_settings_test.dart
```

预期：所有聚焦测试通过。

提交：

```powershell
git add lib\core\password_generator\password_generator.dart lib\features\password_generator\password_generator_page.dart lib\app\app_services.dart test\core\password_generator\password_generator_test.dart test\features\generator_settings_test.dart
git commit -m "feat: add password generator presets"
```

---

### 任务 4：收紧敏感明文生命周期

**文件：**
- 修改：`lib/features/vault_detail/vault_detail_page.dart`
- 修改：`lib/features/vault_edit/vault_edit_page.dart`
- 修改：`lib/features/password_generator/password_generator_page.dart`
- 修改：`lib/app/app_services.dart`
- 测试：`test/features/vault_item_flow_test.dart`
- 测试：`test/core/security/clipboard_and_lock_test.dart`

- [ ] **步骤 1：添加失败的生命周期小组件测试**

追加到 `test/features/vault_item_flow_test.dart`：

```dart
  testWidgets('detail hides visible password when app backgrounds', (tester) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user',
          password: 'secret-password',
          notes: '',
          tags: const [],
        ),
      ],
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.text('secret-password'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(find.text('secret-password'), findsNothing);
  });
```

- [ ] **步骤 2：运行并验证失败**

运行：

```powershell
flutter test --reporter compact test\features\vault_item_flow_test.dart
```

预期：失败，因为详情页面不观察生命周期状态。

- [ ] **步骤 3：在详情页面中实现生命周期隐藏**

修改 `_VaultDetailPageState`：

```dart
class _VaultDetailPageState extends State<VaultDetailPage> with WidgetsBindingObserver {
```

在 `initState()` 中：

```dart
    WidgetsBinding.instance.addObserver(this);
```

在 `dispose()` 中：

```dart
    WidgetsBinding.instance.removeObserver(this);
```

添加：

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (mounted && _isPasswordVisible) {
        setState(() => _isPasswordVisible = false);
      }
    }
  }
```

- [ ] **步骤 4：在锁定/后台时清除生成的密码**

在 `PasswordGeneratorPage` 中添加 `WidgetsBindingObserver`，并在 `paused`、`hidden` 和 `detached` 时清除 `_generatedPassword`，并在 `dispose()` 中调用 `WidgetsBinding.instance.removeObserver(this)`。

使用此精确的生命周期处理器：

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (mounted && _generatedPassword.isNotEmpty) {
        setState(() => _generatedPassword = '');
      }
    }
  }
```

- [ ] **步骤 5：在取消和保存时清除编辑控制器**

在 `VaultEditPage` 中添加：

```dart
  void _clearSensitiveControllers() {
    _passwordController.clear();
    _notesController.clear();
    _isPasswordVisible = false;
  }
```

在 `_save()` 中的 `Navigator.of(context).pop(true);` 之前调用：

```dart
      _clearSensitiveControllers();
```

添加在离开页面之前调用 `_clearSensitiveControllers()` 的前导关闭/返回操作或 `PopScope`。

- [ ] **步骤 6：运行聚焦测试并提交**

运行：

```powershell
dart format lib\features\vault_detail\vault_detail_page.dart lib\features\vault_edit\vault_edit_page.dart lib\features\password_generator\password_generator_page.dart test\features\vault_item_flow_test.dart
flutter test --reporter compact test\features\vault_item_flow_test.dart test\core\security\clipboard_and_lock_test.dart
```

预期：所有聚焦测试通过。

提交：

```powershell
git add lib\features\vault_detail\vault_detail_page.dart lib\features\vault_edit\vault_edit_page.dart lib\features\password_generator\password_generator_page.dart test\features\vault_item_flow_test.dart test\core\security\clipboard_and_lock_test.dart
git commit -m "fix: reduce sensitive plaintext lifetime"
```

---

### 任务 5：改进安全错误状态

**文件：**
- 修改：`lib/app/app_services.dart`
- 修改：`lib/features/unlock/unlock_page.dart`
- 修改：`lib/features/vault_list/vault_list_page.dart`
- 修改：`lib/features/settings/settings_page.dart`
- 测试：`test/features/setup_unlock_test.dart`
- 测试：`test/features/generator_settings_test.dart`

- [ ] **步骤 1：添加清晰的冷却时间和完整性消息的失败测试**

追加到 `test/features/setup_unlock_test.dart`：

```dart
  testWidgets('unlock shows cooldown after repeated master password failures', (tester) async {
    final services = AppServices.fake(hasVault: true, unlockSucceeds: false);
    await _pumpPage(tester, services: services, home: UnlockPage(services: services));

    await tester.enterText(find.widgetWithText(TextFormField, '主密码'), 'wrong-password');
    await tester.tap(find.text('解锁'));
    await tester.pump();
    await tester.tap(find.text('解锁'));
    await tester.pump();

    expect(find.textContaining('稍后'), findsOneWidget);
  });
```

- [ ] **步骤 2：运行并验证失败**

运行：

```powershell
flutter test --reporter compact test\features\setup_unlock_test.dart
```

预期：失败，因为解锁冷却未清晰显示。

- [ ] **步骤 3：暴露解锁冷却状态**

在 `AppServices` 中添加：

```dart
  DateTime? _masterUnlockRetryUntil;

  Duration get masterUnlockRetryRemaining {
    final until = _masterUnlockRetryUntil;
    if (until == null) {
      return Duration.zero;
    }
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
```

更新 `_recordMasterUnlockFailure()`：

```dart
    _masterUnlockRetryUntil = DateTime.now().add(delay);
```

更新 `_resetMasterUnlockThrottle()`：

```dart
    _masterUnlockRetryUntil = null;
```

- [ ] **步骤 4：在解锁 UI 中显示冷却**

在 `UnlockPage` 中，在解锁失败后检查：

```dart
final remaining = widget.services.masterUnlockRetryRemaining;
```

如果 `remaining > Duration.zero`，显示：

```dart
'多次失败，请稍后 ${remaining.inSeconds} 秒后再试。'
```

否则保持通用的密码错误消息。

- [ ] **步骤 5：运行聚焦测试并提交**

运行：

```powershell
dart format lib\app\app_services.dart lib\features\unlock\unlock_page.dart test\features\setup_unlock_test.dart
flutter test --reporter compact test\features\setup_unlock_test.dart
```

预期：所有聚焦测试通过。

提交：

```powershell
git add lib\app\app_services.dart lib\features\unlock\unlock_page.dart test\features\setup_unlock_test.dart
git commit -m "fix: clarify unlock retry cooldown"
```

---

## 最终验证

- [ ] 运行完整测试套件：

```powershell
flutter test --reporter compact
```

预期：所有测试通过。

- [ ] 运行静态分析：

```powershell
flutter analyze
```

预期：`No issues found`。

- [ ] 确认状态：

```powershell
git status --short --branch
```

预期：除了有意忽略的本地文件外，功能分支保持干净。

---

## 自我审查

规格覆盖：

- 本地密码健康检查：任务 1 和任务 2。
- 敏感明文生命周期：任务 4。
- 基于策略的密码生成器：任务 3。
- 更好的面向用户的安全状态：任务 5。
- 详细验证：最终验证和单独测试计划。

占位符扫描：

- 没有实现任务使用禁止的占位符术语。
- 每个代码任务都有具体的路径、命令和预期结果。

类型一致性：

- `PasswordHealthReport`、`PasswordHealthFinding`、`PasswordHealthInput` 和 `PasswordHealthReason` 在任务 1 中引入并被一致重用。
- 生成器预设构造函数在任务 3 中引入，并在同一任务中被 UI 使用。