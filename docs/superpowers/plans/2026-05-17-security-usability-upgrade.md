# Security Usability Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current secure MVP into a more practical local password manager by adding local password health checks, tighter sensitive plaintext lifecycle handling, and a strategy-based password generator.

**Architecture:** Keep all analysis local and only run it after the vault is unlocked. Add small domain services under `lib/core/security/` and `lib/core/password_generator/`, expose them through `AppServices`, and surface them in existing Flutter feature pages without adding cloud sync, remote APIs, or plaintext persistent indexes. Use TDD for each module and commit after each task.

**Tech Stack:** Flutter 3.41, Dart 3.11, Material 3, SQLite via existing DAOs, `cryptography`, `hashlib`, existing `AppServices` facade, Flutter widget tests.

---

## References

- Evaluation report: `docs/superpowers/specs/2026-05-17-project-evaluation-report.md`
- Existing generator: `lib/core/password_generator/password_generator.dart`
- Existing master password policy: `lib/core/security/master_password_policy.dart`
- Existing vault service: `lib/core/vault/vault_service.dart`
- Existing clipboard/lock tests: `test/core/security/clipboard_and_lock_test.dart`
- Existing generator tests: `test/core/password_generator/password_generator_test.dart`

---

## File Map

- Create `lib/core/security/password_health_service.dart`: local-only password health analysis for weak, reused, stale, and title/website-similar passwords.
- Modify `lib/core/vault/vault_service.dart`: expose unlocked vault entries for health analysis without persisting plaintext indexes.
- Modify `lib/app/app_services.dart`: add `analyzePasswordHealth()` and fake overrides for widget tests.
- Create `lib/features/security_health/security_health_page.dart`: user-facing health report page.
- Modify `lib/features/vault_shell/vault_shell_page.dart`: add bottom navigation destination for health.
- Modify `lib/core/password_generator/password_generator.dart`: add generator strategies and readable passphrase generation.
- Modify `lib/features/password_generator/password_generator_page.dart`: add presets, passphrase mode, copy action, and strength explanation.
- Modify `lib/features/vault_detail/vault_detail_page.dart`: clear visible password when page is covered, backgrounded, or disposed.
- Modify `lib/features/vault_edit/vault_edit_page.dart`: clear sensitive controllers on cancel/save/dispose and hide password on lifecycle changes.
- Modify `lib/core/clipboard/clipboard_service.dart`: expose pending password cleanup status for UI and tests.
- Test `test/core/security/password_health_service_test.dart`: health analyzer behavior.
- Test `test/features/security_health_test.dart`: health page and navigation behavior.
- Test `test/core/password_generator/password_generator_test.dart`: strategy and passphrase behavior.
- Test `test/features/generator_settings_test.dart`: generator page presets/copy/save behavior.
- Test `test/features/vault_item_flow_test.dart`: detail/edit sensitive UI state behavior.
- Test `test/core/security/clipboard_and_lock_test.dart`: lifecycle cleanup and pending clipboard state.

---

### Task 1: Add Local Password Health Analysis

**Files:**
- Create: `lib/core/security/password_health_service.dart`
- Modify: `lib/core/vault/vault_service.dart`
- Modify: `lib/app/app_services.dart`
- Test: `test/core/security/password_health_service_test.dart`
- Test: `test/core/vault/vault_service_test.dart`

- [ ] **Step 1: Write the failing health service tests**

Create `test/core/security/password_health_service_test.dart`:

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

- [ ] **Step 2: Run the test and verify it fails**

Run:

```powershell
flutter test --reporter compact test\core\security\password_health_service_test.dart
```

Expected: fails because `password_health_service.dart` does not exist.

- [ ] **Step 3: Implement the health service**

Create `lib/core/security/password_health_service.dart`:

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

- [ ] **Step 4: Add vault/app service integration tests**

Append a test to `test/core/vault/vault_service_test.dart` after existing item CRUD tests:

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

If `EncryptedVaultItem.copyWith` does not exist, add it in `lib/data/models/encrypted_vault_item.dart` with fields for every existing constructor property.

- [ ] **Step 5: Implement service integration**

Modify `lib/core/vault/vault_service.dart`:

```dart
import 'package:secure_box/core/security/password_health_service.dart';
```

Add this public method near `listItems()`:

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

Modify `lib/app/app_services.dart`:

```dart
import 'package:secure_box/core/security/password_health_service.dart';
```

Add a constructor override:

```dart
    Future<PasswordHealthReport> Function()? passwordHealthOverride,
```

Store it:

```dart
  final Future<PasswordHealthReport> Function()? _passwordHealthOverride;
```

Add the method:

```dart
  Future<PasswordHealthReport> analyzePasswordHealth() {
    final override = _passwordHealthOverride;
    if (override != null) {
      return override();
    }
    return vaultService.analyzePasswordHealth();
  }
```

- [ ] **Step 6: Run focused tests and commit**

Run:

```powershell
dart format lib\core\security\password_health_service.dart lib\core\vault\vault_service.dart lib\app\app_services.dart test\core\security\password_health_service_test.dart test\core\vault\vault_service_test.dart
flutter test --reporter compact test\core\security\password_health_service_test.dart test\core\vault\vault_service_test.dart
```

Expected: all focused tests pass.

Commit:

```powershell
git add lib\core\security\password_health_service.dart lib\core\vault\vault_service.dart lib\app\app_services.dart test\core\security\password_health_service_test.dart test\core\vault\vault_service_test.dart
git commit -m "feat: add local password health analysis"
```

---

### Task 2: Add Password Health Page And Navigation

**Files:**
- Create: `lib/features/security_health/security_health_page.dart`
- Modify: `lib/features/vault_shell/vault_shell_page.dart`
- Modify: `test/features/security_health_test.dart`
- Modify: `test/app/app_routing_test.dart`

- [ ] **Step 1: Write failing widget tests**

Create `test/features/security_health_test.dart`:

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

- [ ] **Step 2: Run and verify failure**

Run:

```powershell
flutter test --reporter compact test\features\security_health_test.dart
```

Expected: fails because health tab/page does not exist.

- [ ] **Step 3: Implement the page**

Create `lib/features/security_health/security_health_page.dart`:

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

- [ ] **Step 4: Add the bottom navigation tab**

Modify `lib/features/vault_shell/vault_shell_page.dart`:

```dart
import 'package:secure_box/features/security_health/security_health_page.dart';
```

Update the body switch:

```dart
      body: switch (_selectedIndex) {
        0 => VaultListPage(services: widget.services),
        1 => PasswordGeneratorPage(services: widget.services),
        2 => SecurityHealthPage(services: widget.services),
        _ => SettingsPage(services: widget.services),
      },
```

Add a destination before settings:

```dart
          NavigationDestination(
            key: ValueKey('vault-shell-health-tab'),
            icon: Icon(Icons.health_and_safety_outlined),
            selectedIcon: Icon(Icons.health_and_safety_rounded),
            label: '安全',
          ),
```

- [ ] **Step 5: Run focused tests and commit**

Run:

```powershell
dart format lib\features\security_health\security_health_page.dart lib\features\vault_shell\vault_shell_page.dart test\features\security_health_test.dart
flutter test --reporter compact test\features\security_health_test.dart test\app\app_routing_test.dart
```

Expected: all focused tests pass.

Commit:

```powershell
git add lib\features\security_health\security_health_page.dart lib\features\vault_shell\vault_shell_page.dart test\features\security_health_test.dart test\app\app_routing_test.dart
git commit -m "feat: surface local password health report"
```

---

### Task 3: Productize Password Generator Strategies

**Files:**
- Modify: `lib/core/password_generator/password_generator.dart`
- Modify: `lib/features/password_generator/password_generator_page.dart`
- Modify: `lib/app/app_services.dart`
- Test: `test/core/password_generator/password_generator_test.dart`
- Test: `test/features/generator_settings_test.dart`

- [ ] **Step 1: Add failing generator strategy tests**

Append to `test/core/password_generator/password_generator_test.dart`:

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

- [ ] **Step 2: Run and verify failure**

Run:

```powershell
flutter test --reporter compact test\core\password_generator\password_generator_test.dart
```

Expected: fails because preset constructors and passphrase generation do not exist.

- [ ] **Step 3: Add strategy fields and preset constructors**

Modify `PasswordGeneratorOptions` in `lib/core/password_generator/password_generator.dart`:

```dart
enum PasswordGeneratorMode { randomCharacters, passphrase }
```

Add fields:

```dart
    this.mode = PasswordGeneratorMode.randomCharacters,
    this.wordCount = 4,
    this.separator = '-',
    this.appendNumber = false,
```

Add constructors:

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

Add a small internal word list:

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

Branch in `generate()`:

```dart
    if (options.mode == PasswordGeneratorMode.passphrase) {
      return _generatePassphrase(options);
    }
```

Add:

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

- [ ] **Step 4: Add UI preset and copy tests**

Append to `test/features/generator_settings_test.dart`:

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

- [ ] **Step 5: Implement generator UI**

In `PasswordGeneratorPage`, add:

```dart
enum _GeneratorPreset { strong, passphrase, compatible }
```

Add `_selectedPreset` state and an `_applyPreset()` method:

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

Add preset `SegmentedButton` above length controls with labels `强密码`, `密码短语`, `兼容网站`.

Add copy method:

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

Add a `FilledButton.tonalIcon` with label `复制` when `_generatedPassword.isNotEmpty`.

- [ ] **Step 6: Run focused tests and commit**

Run:

```powershell
dart format lib\core\password_generator\password_generator.dart lib\features\password_generator\password_generator_page.dart lib\app\app_services.dart test\core\password_generator\password_generator_test.dart test\features\generator_settings_test.dart
flutter test --reporter compact test\core\password_generator\password_generator_test.dart test\features\generator_settings_test.dart
```

Expected: all focused tests pass.

Commit:

```powershell
git add lib\core\password_generator\password_generator.dart lib\features\password_generator\password_generator_page.dart lib\app\app_services.dart test\core\password_generator\password_generator_test.dart test\features\generator_settings_test.dart
git commit -m "feat: add password generator presets"
```

---

### Task 4: Tighten Sensitive Plaintext Lifecycle

**Files:**
- Modify: `lib/features/vault_detail/vault_detail_page.dart`
- Modify: `lib/features/vault_edit/vault_edit_page.dart`
- Modify: `lib/features/password_generator/password_generator_page.dart`
- Modify: `lib/app/app_services.dart`
- Test: `test/features/vault_item_flow_test.dart`
- Test: `test/core/security/clipboard_and_lock_test.dart`

- [ ] **Step 1: Add failing lifecycle widget tests**

Append to `test/features/vault_item_flow_test.dart`:

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

- [ ] **Step 2: Run and verify failure**

Run:

```powershell
flutter test --reporter compact test\features\vault_item_flow_test.dart
```

Expected: fails because detail page does not observe lifecycle state.

- [ ] **Step 3: Implement lifecycle hiding in detail page**

Modify `_VaultDetailPageState`:

```dart
class _VaultDetailPageState extends State<VaultDetailPage> with WidgetsBindingObserver {
```

In `initState()`:

```dart
    WidgetsBinding.instance.addObserver(this);
```

In `dispose()`:

```dart
    WidgetsBinding.instance.removeObserver(this);
```

Add:

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

- [ ] **Step 4: Clear generated password on lock/background**

In `PasswordGeneratorPage`, add `WidgetsBindingObserver`, clear `_generatedPassword` on `paused`, `hidden`, and `detached`, and call `WidgetsBinding.instance.removeObserver(this)` in `dispose()`.

Use this exact lifecycle handler:

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

- [ ] **Step 5: Clear edit controllers on cancel and save**

In `VaultEditPage`, add:

```dart
  void _clearSensitiveControllers() {
    _passwordController.clear();
    _notesController.clear();
    _isPasswordVisible = false;
  }
```

Before `Navigator.of(context).pop(true);` in `_save()`, call:

```dart
      _clearSensitiveControllers();
```

Add a leading close/back action or `PopScope` that calls `_clearSensitiveControllers()` before leaving the page.

- [ ] **Step 6: Run focused tests and commit**

Run:

```powershell
dart format lib\features\vault_detail\vault_detail_page.dart lib\features\vault_edit\vault_edit_page.dart lib\features\password_generator\password_generator_page.dart test\features\vault_item_flow_test.dart
flutter test --reporter compact test\features\vault_item_flow_test.dart test\core\security\clipboard_and_lock_test.dart
```

Expected: all focused tests pass.

Commit:

```powershell
git add lib\features\vault_detail\vault_detail_page.dart lib\features\vault_edit\vault_edit_page.dart lib\features\password_generator\password_generator_page.dart test\features\vault_item_flow_test.dart test\core\security\clipboard_and_lock_test.dart
git commit -m "fix: reduce sensitive plaintext lifetime"
```

---

### Task 5: Improve Security Error States

**Files:**
- Modify: `lib/app/app_services.dart`
- Modify: `lib/features/unlock/unlock_page.dart`
- Modify: `lib/features/vault_list/vault_list_page.dart`
- Modify: `lib/features/settings/settings_page.dart`
- Test: `test/features/setup_unlock_test.dart`
- Test: `test/features/generator_settings_test.dart`

- [ ] **Step 1: Add failing tests for clear cooldown and integrity messages**

Append to `test/features/setup_unlock_test.dart`:

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

- [ ] **Step 2: Run and verify failure**

Run:

```powershell
flutter test --reporter compact test\features\setup_unlock_test.dart
```

Expected: fails because unlock cooldown is not clearly displayed.

- [ ] **Step 3: Expose unlock cooldown state**

In `AppServices`, add:

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

Update `_recordMasterUnlockFailure()`:

```dart
    _masterUnlockRetryUntil = DateTime.now().add(delay);
```

Update `_resetMasterUnlockThrottle()`:

```dart
    _masterUnlockRetryUntil = null;
```

- [ ] **Step 4: Display cooldown in unlock UI**

In `UnlockPage`, after a failed unlock, check:

```dart
final remaining = widget.services.masterUnlockRetryRemaining;
```

If `remaining > Duration.zero`, show:

```dart
'多次失败，请稍后 ${remaining.inSeconds} 秒后再试。'
```

Otherwise keep the generic wrong-password message.

- [ ] **Step 5: Run focused tests and commit**

Run:

```powershell
dart format lib\app\app_services.dart lib\features\unlock\unlock_page.dart test\features\setup_unlock_test.dart
flutter test --reporter compact test\features\setup_unlock_test.dart
```

Expected: all focused tests pass.

Commit:

```powershell
git add lib\app\app_services.dart lib\features\unlock\unlock_page.dart test\features\setup_unlock_test.dart
git commit -m "fix: clarify unlock retry cooldown"
```

---

## Final Verification

- [ ] Run full test suite:

```powershell
flutter test --reporter compact
```

Expected: all tests pass.

- [ ] Run static analysis:

```powershell
flutter analyze
```

Expected: `No issues found`.

- [ ] Confirm status:

```powershell
git status --short --branch
```

Expected: clean feature branch except intentionally ignored local files.

---

## Self-Review

Spec coverage:

- Local password health checks: Task 1 and Task 2.
- Sensitive plaintext lifecycle: Task 4.
- Strategy-based password generator: Task 3.
- Better user-facing security states: Task 5.
- Detailed verification: final verification and separate test plan.

Placeholder scan:

- No implementation task uses forbidden placeholder terms.
- Each code task has concrete paths, commands, and expected results.

Type consistency:

- `PasswordHealthReport`, `PasswordHealthFinding`, `PasswordHealthInput`, and `PasswordHealthReason` are introduced in Task 1 and reused consistently.
- Generator preset constructors are introduced in Task 3 and used by UI in the same task.
