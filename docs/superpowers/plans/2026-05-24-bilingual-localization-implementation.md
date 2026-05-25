# Bilingual Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Simplified Chinese and English switching to every app-owned visible string in the Lockly Flutter app.

**Architecture:** Use a lightweight local Dart i18n layer with one abstract `AppStrings` contract and two concrete classes, `AppStringsZh` and `AppStringsEn`. `AppServices` owns a `ValueNotifier<AppLanguage>` like the existing theme notifier, and `SecureBoxApp` wraps the tree in an inherited strings scope so widgets read text through `AppStrings.of(context)`.

**Tech Stack:** Flutter, Dart, existing `flutter_test`, no external localization package.

---

## File Structure

- Create `lib/shared/i18n/app_language.dart`: enum, labels, parser.
- Create `lib/shared/i18n/app_strings.dart`: abstract contract, `of(context)`, dynamic string method signatures.
- Create `lib/shared/i18n/app_strings_zh.dart`: Simplified Chinese strings.
- Create `lib/shared/i18n/app_strings_en.dart`: English strings.
- Create `lib/shared/i18n/app_strings_scope.dart`: `InheritedWidget` provider.
- Modify `lib/app/app_services.dart`: add language notifier/getter/setter/dispose behavior.
- Modify `lib/app/app.dart`: listen for language changes and wrap `MaterialApp.builder` content with `AppStringsScope`.
- Modify feature files in `lib/features/**`: replace app-owned hardcoded visible text with strings.
- Modify shared widgets in `lib/shared/widgets/**`: replace shared visible text with strings where applicable.
- Add/modify tests in `test/ui/localization_test.dart` and `test/ui/visual_system_test.dart`.

## Task 1: Add Language Model and Failing App Tests

**Files:**
- Create: `test/ui/localization_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/shared/i18n/app_language.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';

void main() {
  test('app language parser falls back to Chinese', () {
    expect(AppLanguageX.parse('en'), AppLanguage.en);
    expect(AppLanguageX.parse('zh'), AppLanguage.zh);
    expect(AppLanguageX.parse('bad-value'), AppLanguage.zh);
  });

  testWidgets('settings switches between Chinese and English', (tester) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);
    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('vault-shell-settings-tab')));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(services.language, AppLanguage.en);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);

    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();
    expect(services.language, AppLanguage.zh);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('app strings scope exposes selected language', (tester) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);
    services.language = AppLanguage.en;

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(SecureBoxApp));
    expect(AppStrings.of(context).settingsTitle, 'Settings');
  });
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test --reporter compact test\ui\localization_test.dart`

Expected: FAIL because `shared/i18n` files and `AppServices.language` do not exist.

## Task 2: Implement Core Flutter I18n Layer

**Files:**
- Create: `lib/shared/i18n/app_language.dart`
- Create: `lib/shared/i18n/app_strings.dart`
- Create: `lib/shared/i18n/app_strings_zh.dart`
- Create: `lib/shared/i18n/app_strings_en.dart`
- Create: `lib/shared/i18n/app_strings_scope.dart`
- Modify: `lib/app/app_services.dart`
- Modify: `lib/app/app.dart`

- [ ] **Step 1: Add language enum**

```dart
enum AppLanguage { zh, en }

extension AppLanguageX on AppLanguage {
  static AppLanguage parse(String? value) {
    return switch (value) {
      'en' => AppLanguage.en,
      'zh' => AppLanguage.zh,
      _ => AppLanguage.zh,
    };
  }

  String get code => switch (this) {
    AppLanguage.zh => 'zh',
    AppLanguage.en => 'en',
  };

  String get displayName => switch (this) {
    AppLanguage.zh => '中文',
    AppLanguage.en => 'English',
  };
}
```

- [ ] **Step 2: Add string contract**

Create an abstract `AppStrings` with properties and methods used by all migrated UI. Start with the tested keys:

```dart
import 'package:flutter/widgets.dart';
import 'package:secure_box/shared/i18n/app_strings_scope.dart';

abstract class AppStrings {
  const AppStrings();

  static AppStrings of(BuildContext context) => AppStringsScope.of(context);

  String get appName;
  String get settingsTitle;
  String get languageTitle;
  String get themeTitle;
  String get vaultTab;
  String get securityTab;
  String get totpTab;
  String get generatorTab;
  String get settingsTab;
  String get vaultTitle;
  String get passwordGeneratorTitle;
  String get searchLabel;
  String get searchHint;
  String vaultItemCount(int count);
}
```

Expand this contract as feature files are migrated. Do not use ad hoc string maps.

- [ ] **Step 3: Add Chinese and English classes**

Implement `AppStringsZh extends AppStrings` and `AppStringsEn extends AppStrings`. Every contract member must exist in both files.

- [ ] **Step 4: Add scope**

```dart
import 'package:flutter/widgets.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';

class AppStringsScope extends InheritedWidget {
  const AppStringsScope({
    super.key,
    required this.strings,
    required super.child,
  });

  final AppStrings strings;

  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    if (scope == null) {
      throw StateError('AppStringsScope is missing above this context.');
    }
    return scope.strings;
  }

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) {
    return strings.runtimeType != oldWidget.strings.runtimeType;
  }
}
```

- [ ] **Step 5: Wire services and app**

`AppServices` gets:

```dart
final ValueNotifier<AppLanguage> languageNotifier =
    ValueNotifier(AppLanguage.zh);

AppLanguage get language => languageNotifier.value;
set language(AppLanguage value) {
  languageNotifier.value = value;
}
```

Dispose `languageNotifier`.

`SecureBoxApp` listens to `languageNotifier`, removes the listener in `dispose`, and wraps the existing app content with the current strings object.

- [ ] **Step 6: Run tests to verify GREEN**

Run: `flutter test --reporter compact test\ui\localization_test.dart`

Expected: tests pass after settings and shell strings are migrated in Task 3.

## Task 3: Migrate Shell, Settings, Vault List, and Generator

**Files:**
- Modify: `lib/features/vault_shell/vault_shell_page.dart`
- Modify: `lib/features/settings/settings_page.dart`
- Modify: `lib/features/vault_list/vault_list_page.dart`
- Modify: `lib/features/password_generator/password_generator_page.dart`
- Modify: i18n classes.

- [ ] **Step 1: Replace shell labels**

Read `final strings = AppStrings.of(context);` in `VaultShellPage.build`. Remove `const` from destinations that need localized labels.

- [ ] **Step 2: Add settings language section**

Near the theme section, add a `SecureSection` with a `SegmentedButton<AppLanguage>`. Use `widget.services.language` and set it in `onSelectionChanged`.

- [ ] **Step 3: Replace settings titles, labels, snack bars, dialogs, and cloud sync text**

Every app-owned visible setting string moves into `AppStrings`.

- [ ] **Step 4: Replace vault list text**

Migrate page header, search fields, filter chip labels, empty/error states, security summary, recycle bin label, and status pills.

- [ ] **Step 5: Replace generator text**

Migrate page header, generated result labels, snackbar messages, generator rules, length, switches, action buttons, and strength label.

- [ ] **Step 6: Run focused tests**

Run:

```powershell
flutter test --reporter compact test\ui\localization_test.dart test\ui\visual_system_test.dart test\features\generator_settings_test.dart
```

Expected: pass.

## Task 4: Migrate Remaining App Screens

**Files:**
- Modify all remaining `lib/features/**` files with app-owned visible text.
- Modify `lib/app/app.dart` privacy cover text.
- Modify shared widgets if they contain visible text.
- Modify tests whose text assertions should use localized values.

- [ ] **Step 1: Use search to find hardcoded visible text**

Run:

```powershell
rg "Text\(|labelText:|hintText:|SnackBar\(|AlertDialog|NavigationDestination|NavigationRailDestination|SecureReplicaHeader|SecureSection\(" lib -n
```

- [ ] **Step 2: Migrate setup and unlock**

Move setup, privacy policy, unlock, biometric, validation, and failure messages into `AppStrings`.

- [ ] **Step 3: Migrate vault detail and edit**

Move field labels, dialog labels, attachment labels, TOTP labels, passkey labels, export labels, snackbars, and empty/error messages into `AppStrings`.

- [ ] **Step 4: Migrate security center, health, emergency access, migration, TOTP, trash, and tags**

Move all app-owned visible copy into `AppStrings`. Keep IDs, fingerprints, timestamps, usernames, item titles, and user content unchanged.

- [ ] **Step 5: Run full app checks**

Run:

```powershell
flutter analyze
flutter test --reporter compact
```

Expected: no analyzer issues and all tests pass.

## Task 5: Review and Documentation

**Files:**
- Modify: `docs/superpowers/specs/2026-05-24-bilingual-localization-design.md` if implementation decisions differ.
- Create or modify: `docs/bilingual-localization-2026-05-24.md`

- [ ] **Step 1: Add implementation note**

Document language architecture, excluded dynamic data, and verification commands.

- [ ] **Step 2: Dispatch frontend review**

Ask a fresh review subagent to check for missed app-owned hardcoded visible strings, mixed-language UI, test gaps, and security-boundary regressions.

- [ ] **Step 3: Fix review findings**

Fix warning-level or higher findings in `Lockly` only.

- [ ] **Step 4: Final verification**

Run:

```powershell
flutter analyze
flutter test --reporter compact
git diff --check
```

Expected: no analyzer issues, all tests pass, and no whitespace errors beyond Windows LF/CRLF warnings.
