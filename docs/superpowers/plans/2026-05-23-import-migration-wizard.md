# Import Migration Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local import migration wizard for Lockly encrypted JSON and plaintext CSV imports.

**Architecture:** Add a pure Dart CSV importer, expose safe preview/import methods through `AppServices`, and replace the Settings backup import dialog with a dedicated wizard page. CSV plaintext never leaves the local unlocked app and is written only through existing encrypted vault item creation.

**Tech Stack:** Flutter, Dart, existing Lockly `AppServices`, `PasswordEntry`, `BackupImportMode`, `SecureVisual*` widgets, `flutter_test`.

---

## File Map

- Create: `Lockly/lib/core/migration/plaintext_csv_importer.dart`
  - Pure Dart CSV parser, header alias mapping, safe preview report, conversion to `PasswordEntry`.
- Create: `Lockly/test/core/migration/plaintext_csv_importer_test.dart`
  - Parser and safe-preview tests.
- Modify: `Lockly/lib/app/app_services.dart`
  - Add `previewPlaintextCsvImport()` and `importPlaintextCsv()`.
- Modify: `Lockly/test/core/backup/backup_service_test.dart`
  - Add AppServices facade tests for plaintext CSV import.
- Create: `Lockly/lib/features/migration/migration_wizard_page.dart`
  - Wizard UI for Lockly JSON and CSV.
- Modify: `Lockly/lib/features/settings/settings_page.dart`
  - Open the wizard from the backup import action and show result.
- Modify: `Lockly/test/features/generator_settings_test.dart`
  - Widget coverage for Settings -> migration wizard.
- Modify: `Lockly/test/ui/visual_system_test.dart`
  - Adjust any visual route assumptions if Settings import text changes.

---

## Task 1: Pure Dart CSV Importer

**Files:**
- Create: `Lockly/lib/core/migration/plaintext_csv_importer.dart`
- Test: `Lockly/test/core/migration/plaintext_csv_importer_test.dart`

- [x] **Step 1: Write failing parser tests**

Create `test/core/migration/plaintext_csv_importer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/migration/plaintext_csv_importer.dart';

void main() {
  test('CSV importer maps common password manager headers', () {
    final report = PlaintextCsvImporter.preview(
      'name,url,username,password,notes,tags,totp\n'
      'GitHub,https://github.com,user@example.com,secret-pass,private note,"dev, code",123456\n',
    );

    expect(report.totalRows, 1);
    expect(report.importableRows, 1);
    expect(report.skippedRows, 0);
    expect(report.previewRows.single.title, 'GitHub');
    expect(report.previewRows.single.website, 'https://github.com');
    expect(report.previewRows.single.username, 'user@example.com');
    expect(report.toEntries().single.password, 'secret-pass');
    expect(report.toEntries().single.notes, 'private note');
    expect(report.toEntries().single.tags, ['dev', 'code']);
    expect(report.toEntries().single.totpSecret, '123456');
  });

  test('CSV preview hides passwords notes and totp secrets', () {
    final report = PlaintextCsvImporter.preview(
      'title,website,username,password,notes,totp\n'
      'Bank,https://bank.example,alice,bank-secret,private banking note,OTPSECRET\n',
    );

    final preview = report.previewRows.single;
    expect(preview.title, 'Bank');
    expect(preview.website, 'https://bank.example');
    expect(preview.username, 'alice');
    expect(preview.toString(), isNot(contains('bank-secret')));
    expect(preview.toString(), isNot(contains('private banking note')));
    expect(preview.toString(), isNot(contains('OTPSECRET')));
  });

  test('CSV importer handles quoted commas and escaped quotes', () {
    final report = PlaintextCsvImporter.preview(
      'title,website,username,password\n'
      '"A, B ""Prod""",https://example.com,me,"p,ass"\n',
    );

    final entry = report.toEntries().single;
    expect(entry.title, 'A, B "Prod"');
    expect(entry.password, 'p,ass');
  });

  test('CSV importer skips incomplete rows', () {
    final report = PlaintextCsvImporter.preview(
      'title,website,username,password\n'
      'Missing password,https://example.com,me,\n'
      ',https://ok.example,ok-user,ok-pass\n',
    );

    expect(report.totalRows, 2);
    expect(report.importableRows, 1);
    expect(report.skippedRows, 1);
    expect(report.toEntries().single.title, 'https://ok.example');
  });

  test('CSV importer rejects oversized input', () {
    final text = 'title,website,username,password\n${'a' * 1048577}';
    expect(
      () => PlaintextCsvImporter.preview(text),
      throwsA(isA<FormatException>()),
    );
  });
}
```

- [x] **Step 2: Run parser tests and verify RED**

Run:

```powershell
flutter test test/core/migration/plaintext_csv_importer_test.dart
```

Expected: fails because `PlaintextCsvImporter` does not exist.

- [x] **Step 3: Implement importer**

Create `lib/core/migration/plaintext_csv_importer.dart` with:

```dart
import 'package:secure_box/data/models/password_entry.dart';

const int maxPlaintextCsvImportBytes = 1024 * 1024;

class PlaintextCsvImportReport {
  const PlaintextCsvImportReport({
    required this.totalRows,
    required this.importableRows,
    required this.skippedRows,
    required this.previewRows,
    required List<PasswordEntry> entries,
  }) : _entries = entries;

  final int totalRows;
  final int importableRows;
  final int skippedRows;
  final List<PlaintextCsvPreviewRow> previewRows;
  final List<PasswordEntry> _entries;

  List<PasswordEntry> toEntries() => List.unmodifiable(_entries);
}

class PlaintextCsvPreviewRow {
  const PlaintextCsvPreviewRow({
    required this.title,
    required this.website,
    required this.username,
  });

  final String title;
  final String website;
  final String username;

  @override
  String toString() {
    return 'PlaintextCsvPreviewRow(title: $title, website: $website, username: $username)';
  }
}

class PlaintextCsvImporter {
  static PlaintextCsvImportReport preview(String csvText) {
    if (csvText.length > maxPlaintextCsvImportBytes) {
      throw const FormatException('CSV import is too large');
    }
    final rows = _parseCsv(csvText);
    if (rows.isEmpty) {
      throw const FormatException('CSV import is empty');
    }
    final headers = rows.first.map(_normalizeHeader).toList(growable: false);
    if (headers.every((header) => header.isEmpty)) {
      throw const FormatException('CSV headers are missing');
    }

    final entries = <PasswordEntry>[];
    final previews = <PlaintextCsvPreviewRow>[];
    var skipped = 0;
    for (final row in rows.skip(1)) {
      if (row.every((value) => value.trim().isEmpty)) {
        continue;
      }
      final entry = _entryFromRow(headers, row);
      if (entry == null) {
        skipped += 1;
        continue;
      }
      entries.add(entry);
      if (previews.length < 5) {
        previews.add(
          PlaintextCsvPreviewRow(
            title: entry.title,
            website: entry.website,
            username: entry.username,
          ),
        );
      }
    }
    return PlaintextCsvImportReport(
      totalRows: rows.length - 1,
      importableRows: entries.length,
      skippedRows: skipped,
      previewRows: List.unmodifiable(previews),
      entries: List.unmodifiable(entries),
    );
  }
}

PasswordEntry? _entryFromRow(List<String> headers, List<String> row) {
  String read(Set<String> aliases) {
    for (var i = 0; i < headers.length; i += 1) {
      if (!aliases.contains(headers[i])) {
        continue;
      }
      if (i >= row.length) {
        return '';
      }
      return row[i].trim();
    }
    return '';
  }

  final website = read(_websiteHeaders);
  final username = read(_usernameHeaders);
  final password = read(_passwordHeaders);
  if (password.isEmpty || (website.isEmpty && username.isEmpty && read(_titleHeaders).isEmpty)) {
    return null;
  }
  final title = _firstNonEmpty([read(_titleHeaders), website, username, 'Imported item']);
  return PasswordEntry(
    title: title,
    website: website,
    username: username,
    password: password,
    notes: read(_notesHeaders),
    tags: _splitTags(read(_tagsHeaders)),
    totpSecret: _emptyToNull(read(_totpHeaders)),
  );
}

List<String> _splitTags(String value) {
  if (value.trim().isEmpty) {
    return const [];
  }
  return value
      .split(RegExp(r'[,;]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

String _firstNonEmpty(List<String> values) {
  return values.firstWhere((value) => value.trim().isNotEmpty).trim();
}

String? _emptyToNull(String value) => value.isEmpty ? null : value;

String _normalizeHeader(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
}

const _titleHeaders = {'title', 'name', 'login_title'};
const _websiteHeaders = {'website', 'url', 'uri', 'login_uri'};
const _usernameHeaders = {'username', 'login_username', 'email'};
const _passwordHeaders = {'password', 'login_password'};
const _notesHeaders = {'notes', 'note'};
const _tagsHeaders = {'tags', 'folder'};
const _totpHeaders = {'totp', 'totp_secret', 'otp'};

List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < input.length; i += 1) {
    final char = input[i];
    if (inQuotes) {
      if (char == '"') {
        final nextIsQuote = i + 1 < input.length && input[i + 1] == '"';
        if (nextIsQuote) {
          field.write('"');
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(char);
      }
      continue;
    }
    if (char == '"') {
      inQuotes = true;
    } else if (char == ',') {
      row.add(field.toString());
      field.clear();
    } else if (char == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else if (char != '\r') {
      field.write(char);
    }
  }
  if (inQuotes) {
    throw const FormatException('CSV quote is not closed');
  }
  row.add(field.toString());
  if (row.any((value) => value.isNotEmpty) || rows.isEmpty) {
    rows.add(row);
  }
  return rows;
}
```

- [x] **Step 4: Run parser tests and verify GREEN**

Run:

```powershell
flutter test test/core/migration/plaintext_csv_importer_test.dart
```

Expected: all tests pass.

---

## Task 2: AppServices CSV Facade

**Files:**
- Modify: `Lockly/lib/app/app_services.dart`
- Test: `Lockly/test/core/backup/backup_service_test.dart`

- [x] **Step 1: Write failing AppServices tests**

Add imports to `test/core/backup/backup_service_test.dart` if missing:

```dart
import 'package:secure_box/core/migration/plaintext_csv_importer.dart';
```

Add tests:

```dart
test('AppServices previews plaintext CSV without exposing secrets', () {
  final services = AppServices.fake(hasVault: true, unlocked: true);

  final report = services.previewPlaintextCsvImport(
    'title,website,username,password,notes,totp\n'
    'GitHub,https://github.com,user@example.com,secret,private,OTPSECRET\n',
  );

  expect(report.importableRows, 1);
  expect(report.previewRows.single.title, 'GitHub');
  expect(report.previewRows.single.toString(), isNot(contains('secret')));
  expect(report.previewRows.single.toString(), isNot(contains('private')));
  expect(report.previewRows.single.toString(), isNot(contains('OTPSECRET')));
});

test('AppServices imports plaintext CSV through encrypted vault item creation', () async {
  final services = AppServices.fake(hasVault: true, unlocked: true);

  final count = await services.importPlaintextCsv(
    'title,website,username,password\n'
    'GitHub,https://github.com,user@example.com,secret\n',
  );

  expect(count, 1);
  final items = await services.listVaultItems();
  expect(items.single.title, 'GitHub');
  final entry = await services.getVaultItem(items.single.id);
  expect(entry.password, 'secret');
});
```

- [x] **Step 2: Run tests and verify RED**

Run:

```powershell
flutter test test/core/backup/backup_service_test.dart --plain-name "AppServices"
```

Expected: fails because AppServices methods do not exist.

- [x] **Step 3: Add AppServices methods**

Modify `lib/app/app_services.dart`:

```dart
import 'package:secure_box/core/migration/plaintext_csv_importer.dart';
```

Add methods near backup import/export:

```dart
PlaintextCsvImportReport previewPlaintextCsvImport(String csvText) {
  return PlaintextCsvImporter.preview(csvText);
}

Future<int> importPlaintextCsv(String csvText) async {
  final report = PlaintextCsvImporter.preview(csvText);
  for (final entry in report.toEntries()) {
    await createVaultItem(entry);
  }
  return report.importableRows;
}
```

- [x] **Step 4: Run AppServices tests**

Run:

```powershell
flutter test test/core/backup/backup_service_test.dart --plain-name "AppServices"
```

Expected: tests pass.

---

## Task 3: Migration Wizard UI

**Files:**
- Create: `Lockly/lib/features/migration/migration_wizard_page.dart`
- Modify: `Lockly/lib/features/settings/settings_page.dart`
- Test: `Lockly/test/features/generator_settings_test.dart`

- [x] **Step 1: Write failing widget tests**

In `test/features/generator_settings_test.dart`, add tests:

```dart
testWidgets('settings opens migration wizard from backup import', (tester) async {
  final services = AppServices.fake(hasVault: true, unlocked: true);

  await tester.pumpWidget(SecureBoxApp(services: services));
  await tester.pumpAndSettle();
  services.navigatorKey.currentState!.pushNamed(AppServices.routeSettings);
  await tester.pumpAndSettle();

  await tester.scrollUntilVisible(find.text('瀵煎叆杩佺Щ鍚戝'), 120);
  await tester.tap(find.text('瀵煎叆杩佺Щ鍚戝'));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('migration-wizard-page')), findsOneWidget);
  expect(find.text('Migration import'), findsOneWidget);
});

testWidgets('migration wizard previews CSV without rendering secrets and imports rows', (tester) async {
  final services = AppServices.fake(hasVault: true, unlocked: true);

  await tester.pumpWidget(MaterialApp(home: MigrationWizardPage(services: services)));
  await tester.pumpAndSettle();

  await tester.tap(find.text('CSV'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('migration-csv-input')),
    'title,website,username,password,notes,totp\n'
    'Bank,https://bank.example,alice,bank-secret,private note,OTPSECRET\n',
  );
  await tester.tap(find.text('Preview'));
  await tester.pumpAndSettle();

  expect(find.text('1 importable row'), findsOneWidget);
  expect(find.text('Bank'), findsOneWidget);
  expect(find.text('https://bank.example'), findsOneWidget);
  expect(find.text('alice'), findsOneWidget);
  expect(find.textContaining('bank-secret'), findsNothing);
  expect(find.textContaining('private note'), findsNothing);
  expect(find.textContaining('OTPSECRET'), findsNothing);

  await tester.tap(find.text('Import'));
  await tester.pumpAndSettle();

  final items = await services.listVaultItems();
  expect(items.single.title, 'Bank');
});
```

Also add imports:

```dart
import 'package:secure_box/features/migration/migration_wizard_page.dart';
```

- [x] **Step 2: Run widget tests and verify RED**

Run:

```powershell
flutter test test/features/generator_settings_test.dart --plain-name "migration"
```

Expected: fails because wizard/page/text do not exist.

- [x] **Step 3: Implement wizard page**

Create `lib/features/migration/migration_wizard_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/backup/backup_service.dart';
import 'package:secure_box/core/migration/plaintext_csv_importer.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

enum _MigrationSource { locklyJson, csv }

class MigrationWizardPage extends StatefulWidget {
  const MigrationWizardPage({super.key, required this.services});

  final AppServices services;

  @override
  State<MigrationWizardPage> createState() => _MigrationWizardPageState();
}

class _MigrationWizardPageState extends State<MigrationWizardPage> {
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  _MigrationSource _source = _MigrationSource.locklyJson;
  PlaintextCsvImportReport? _csvReport;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _sourceController.clear();
    _passwordController.clear();
    _sourceController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _previewCsv() {
    widget.services.recordActivity();
    try {
      setState(() {
        _csvReport = widget.services.previewPlaintextCsvImport(_sourceController.text);
        _error = null;
      });
    } catch (_) {
      setState(() {
        _csvReport = null;
        _error = 'CSV import could not be parsed locally.';
      });
    }
  }

  Future<void> _import() async {
    widget.services.recordActivity();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final count = switch (_source) {
        _MigrationSource.locklyJson => await widget.services.importEncryptedBackupJson(
            backupJson: _sourceController.text,
            masterPassword: _passwordController.text,
            mode: BackupImportMode.merge,
          ),
        _MigrationSource.csv => await widget.services.importPlaintextCsv(_sourceController.text),
      };
      if (!mounted) return;
      Navigator.of(context).pop(count);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Import failed. Check the source data and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _csvReport;
    return SecureVisualBackground(
      key: const ValueKey('migration-wizard-page'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: ListView(
        children: [
          SecureReplicaHeader(
            title: 'Migration import',
            subtitle: 'Local import wizard',
            leading: IconButton(
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          const SizedBox(height: 12),
          SecureGlassCard(
            borderRadius: 20,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_MigrationSource>(
                  segments: const [
                    ButtonSegment(
                      value: _MigrationSource.locklyJson,
                      icon: Icon(Icons.lock_outline_rounded),
                      label: Text('Lockly JSON'),
                    ),
                    ButtonSegment(
                      value: _MigrationSource.csv,
                      icon: Icon(Icons.table_chart_outlined),
                      label: Text('CSV'),
                    ),
                  ],
                  selected: {_source},
                  onSelectionChanged: _busy
                      ? null
                      : (selection) {
                          setState(() {
                            _source = selection.single;
                            _csvReport = null;
                            _error = null;
                          });
                        },
                ),
                const SizedBox(height: 14),
                TextField(
                  key: ValueKey(
                    _source == _MigrationSource.csv
                        ? 'migration-csv-input'
                        : 'migration-json-input',
                  ),
                  controller: _sourceController,
                  minLines: 6,
                  maxLines: 9,
                  decoration: InputDecoration(
                    labelText: _source == _MigrationSource.csv
                        ? 'CSV export'
                        : 'Encrypted backup JSON',
                    prefixIcon: const Icon(Icons.data_object_rounded),
                  ),
                ),
                if (_source == _MigrationSource.locklyJson) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('migration-backup-password-input'),
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Backup master password',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (_source == _MigrationSource.csv)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _previewCsv,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Preview'),
                  ),
                if (report != null) ...[
                  const SizedBox(height: 12),
                  _CsvPreview(report: report),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.file_download_outlined),
                  label: Text(_busy ? 'Importing' : 'Import'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CsvPreview extends StatelessWidget {
  const _CsvPreview({required this.report});

  final PlaintextCsvImportReport report;

  @override
  Widget build(BuildContext context) {
    final countLabel = report.importableRows == 1 ? '1 importable row' : '${report.importableRows} importable rows';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(countLabel, style: Theme.of(context).textTheme.titleSmall),
        Text('${report.skippedRows} skipped rows'),
        const SizedBox(height: 8),
        for (final row in report.previewRows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key_rounded),
            title: Text(row.title),
            subtitle: Text([row.website, row.username].where((value) => value.isNotEmpty).join(' | ')),
          ),
      ],
    );
  }
}
```

- [x] **Step 4: Wire Settings import action**

Modify `lib/features/settings/settings_page.dart`:

```dart
import 'package:secure_box/features/migration/migration_wizard_page.dart';
```

Replace `_importBackup()` body with navigation:

```dart
Future<void> _importBackup() async {
  widget.services.recordActivity();
  final imported = await Navigator.of(context).push<int>(
    MaterialPageRoute(
      builder: (context) => MigrationWizardPage(services: widget.services),
    ),
  );
  if (imported == null || !mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Imported $imported record(s).')));
}
```

Update the import tile display text to stable English:

```dart
_ActionTile(
  icon: Icons.move_up_rounded,
  title: '瀵煎叆杩佺Щ鍚戝',
  subtitle: 'Import Lockly JSON or local CSV exports.',
  onTap: _importBackup,
),
```

- [x] **Step 5: Run widget tests**

Run:

```powershell
flutter test test/features/generator_settings_test.dart --plain-name "migration"
```

Expected: tests pass.

---

## Task 4: Lockly JSON Wizard Coverage

**Files:**
- Modify: `Lockly/test/features/generator_settings_test.dart`
- Modify: `Lockly/lib/features/migration/migration_wizard_page.dart` if needed

- [x] **Step 1: Add failing JSON-path test**

Add:

```dart
testWidgets('migration wizard keeps Lockly encrypted JSON import path', (tester) async {
  String? importedJson;
  String? importedPassword;
  final services = AppServices(
    hasVault: true,
    initialShellState: AppShellState.unlocked,
    clipboardService: ClipboardService(),
    biometricEnabledOverride: () async => false,
    autoLockTimeoutOverride: () async => const Duration(minutes: 2),
    clipboardCleanupTimeoutOverride: () async => const Duration(seconds: 30),
    importBackupOverride: (backupJson, masterPassword) async {
      importedJson = backupJson;
      importedPassword = masterPassword;
      return 3;
    },
    trackActivity: false,
  );
  addTearDown(services.dispose);

  await tester.pumpWidget(MaterialApp(home: MigrationWizardPage(services: services)));
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const ValueKey('migration-json-input')),
    '{"version":2,"items":[]}',
  );
  await tester.enterText(
    find.byKey(const ValueKey('migration-backup-password-input')),
    'backup-master',
  );
  await tester.tap(find.text('Import'));
  await tester.pumpAndSettle();

  expect(importedJson, '{"version":2,"items":[]}');
  expect(importedPassword, 'backup-master');
  expect(find.textContaining('backup-master'), findsNothing);
});
```

Add any missing imports:

```dart
import 'package:secure_box/core/clipboard/clipboard_service.dart';
```

- [x] **Step 2: Run JSON-path test**

Run:

```powershell
flutter test test/features/generator_settings_test.dart --plain-name "migration wizard keeps Lockly encrypted JSON import path"
```

Expected: passes after Task 3 implementation.

---

## Task 5: Verification And Docs

**Files:**
- Modify: `Lockly/docs/security-check.md`
- Modify: `Lockly/docs/superpowers/plans/2026-05-23-import-migration-wizard.md`

- [x] **Step 1: Update security docs**

Append a bullet to `docs/security-check.md`:

```markdown
- Import migration supports local plaintext CSV parsing only inside the unlocked client. CSV passwords, notes, and TOTP secrets are not sent to the backend or rendered in previews; imported rows are immediately written through encrypted vault item creation.
```

- [x] **Step 2: Run targeted verification**

Run:

```powershell
flutter test test/core/migration/plaintext_csv_importer_test.dart test/core/backup/backup_service_test.dart test/features/generator_settings_test.dart
flutter analyze
```

Expected: targeted tests pass and analyzer reports no issues.

- [x] **Step 3: Mark plan checkboxes**

After implementation and verification, update this plan file by changing completed task checkboxes from `[ ]` to `[x]`.

---

## Review Requirements

After implementation:

- Dispatch a frontend review subagent for UI, parser safety, no secret rendering, tests, and analyzer issues.
- Dispatch a backend/protocol review subagent to confirm no CSV plaintext or master-password data touches `backend-pass` or sync DTOs.
- Fix all Warning-or-higher findings before starting the next slice.
