# Lockly Bilingual Localization Design - 2026-05-24

## Goal

Lockly must stop mixing Chinese and English in the UI. The app will support a user-facing language switch between Simplified Chinese and English, and every app-owned visible string will live in one of two language classes.

This is a presentation-layer change. It must not change vault encryption, master password handling, sync payloads, account authentication, device management, backend protocols, or stored password data.

## Scope

In scope:

- All user-visible text in `Lockly/lib`, including navigation, setup, unlock, vault list, vault detail, vault edit, password generator, settings, security center, password health, TOTP, trash, migration, tag management, emergency access, privacy policy, dialogs, snack bars, empty states, buttons, input labels, helper text, and validation messages.
- Language switch in settings.
- App rebuild after language changes.
- Tests proving language switching works and common screens no longer mix languages.
- Coordination with `backend-pass` admin localization, documented separately in that repository.

Out of scope:

- Translating user data such as entry titles, usernames, URLs, notes, tags, device names, attachment names, audit action codes, API error codes, ciphertext metadata, or imported backup content.
- Persisting language to cloud sync.
- Introducing `intl`, ARB generation, network translation, or remote language packs.
- Changing backend API contracts or cryptographic behavior.

## Architecture

Add a lightweight local i18n layer:

- `lib/shared/i18n/app_language.dart`
  Defines `AppLanguage.zh` and `AppLanguage.en`, labels for UI display, and parsing helpers.
- `lib/shared/i18n/app_strings.dart`
  Defines the abstract string contract and `AppStrings.of(context)`.
- `lib/shared/i18n/app_strings_zh.dart`
  Implements all Simplified Chinese strings.
- `lib/shared/i18n/app_strings_en.dart`
  Implements all English strings.
- `lib/shared/i18n/app_strings_scope.dart`
  Provides the current `AppStrings` through an `InheritedWidget`.

`AppServices` will own `languageNotifier`, matching the existing theme pattern:

- Default language: Simplified Chinese.
- Getter/setter: `language`.
- Language changes notify `SecureBoxApp`.
- `SecureBoxApp` rebuilds and wraps the app content with `AppStringsScope`.

This avoids adding external dependencies and keeps the implementation directly aligned with the requirement for Chinese and English classes.

## UI Behavior

Settings gets a language section near the theme section:

- Title in current language: `语言` / `Language`.
- Segmented control choices: `中文` / `English`.
- Changing language immediately updates the visible UI.

Text access pattern:

```dart
final strings = AppStrings.of(context);
Text(strings.settingsTitle);
```

Functions are used for dynamic text:

```dart
String vaultItemCount(int count);
String confirmDeleteEntry(String title);
String importedRecords(int count);
```

Tests may continue to assert existing keys. Text assertions must use the localized value for the active language.

## Backend Coordination

The backend admin console will use its own Python-side string classes and language state. The Flutter app does not consume backend admin strings. The two implementations share language names and intent, but remain independent.

## Error Handling

- If an unknown language value is requested, fall back to Simplified Chinese.
- Dynamic formatting must be deterministic and local only.
- Error messages generated from exceptions may remain technical if they are not app-owned display copy; app-owned wrappers should be localized.
- User content is rendered as-is and never translated.

## Testing

Follow TDD:

1. Add failing Flutter tests showing:
   - Settings has a language switch.
   - Switching to English updates navigation and settings labels.
   - Switching back to Chinese restores Chinese labels.
   - Main user-visible screens use localized strings from `AppStrings`.
2. Implement the i18n layer and setting switch.
3. Migrate visible strings file by file.
4. Run:
   - `flutter analyze`
   - targeted localization/UI tests
   - full `flutter test --reporter compact`
5. Dispatch a frontend review subagent to check for missed hardcoded app-owned visible strings and any security-boundary regressions.

## Migration Order

1. Add i18n classes, scope, and `AppServices.languageNotifier`.
2. Wire `SecureBoxApp` and settings language control.
3. Migrate shared widgets and shell navigation.
4. Migrate setup/unlock/core vault flows.
5. Migrate settings, generator, security center, health, TOTP, trash, migration, tags, emergency access, and privacy policy.
6. Update tests and docs.

## Safety Rules

- Do not edit crypto, vault serialization, sync payloads, backend API clients, or auth behavior except for app-owned UI messages.
- Do not translate or transform user secrets or user-entered vault content.
- Do not introduce network-based translation.
- Do not remove existing test keys.

## Spec Self-Review

- No placeholder requirements remain.
- Scope covers both languages and all app-owned visible text.
- Backend admin localization is acknowledged but kept independent.
- The implementation path is test-first and avoids security-sensitive logic.
