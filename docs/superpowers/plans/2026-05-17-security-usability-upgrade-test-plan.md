# Security Usability Upgrade Test Plan

**Date:** 2026-05-17

## Scope

This test plan covers the execution plan in `docs/superpowers/plans/2026-05-17-security-usability-upgrade.md`.

It verifies:

- Local password health checks.
- Password health UI and bottom navigation.
- Password generator presets and passphrase mode.
- Sensitive plaintext lifecycle cleanup.
- Unlock cooldown and clearer security error states.
- Regression coverage for crypto, vault integrity, backup, clipboard, biometric fallback, and routing.

## Test Strategy

Use three layers:

1. Unit tests for pure services:
   - `PasswordHealthService`
   - `PasswordGenerator`
   - `ClipboardService`
   - `MasterPasswordPolicy`

2. Service/integration tests for vault behavior:
   - `VaultService`
   - `BackupService`
   - manifest and rollback anchor interactions

3. Widget tests for user-facing flows:
   - setup/unlock
   - vault list/detail/edit
   - generator
   - settings
   - health page
   - shell navigation

## Required Commands

Run focused tests after each task:

```powershell
flutter test --reporter compact test\core\security\password_health_service_test.dart
flutter test --reporter compact test\features\security_health_test.dart
flutter test --reporter compact test\core\password_generator\password_generator_test.dart
flutter test --reporter compact test\features\generator_settings_test.dart
flutter test --reporter compact test\features\vault_item_flow_test.dart
flutter test --reporter compact test\features\setup_unlock_test.dart
```

Run final verification:

```powershell
flutter test --reporter compact
flutter analyze
```

## Password Health Test Matrix

| Case | Test File | Expected |
| --- | --- | --- |
| Common weak password | `test/core/security/password_health_service_test.dart` | Finding includes `weak`, severity `critical` |
| Reused password across two entries | `test/core/security/password_health_service_test.dart` | Both entries include `reused`, severity `critical` |
| Password older than 365 days | `test/core/security/password_health_service_test.dart` | Finding includes `stale`, severity `warning` unless also weak/reused |
| Password contains title/site token | `test/core/security/password_health_service_test.dart` | Finding includes `similarToTitleOrSite` |
| Strong unique recent password | `test/core/security/password_health_service_test.dart` | No finding |
| Finding string does not contain plaintext password | `test/core/security/password_health_service_test.dart` | `finding.toString()` excludes password |
| Vault health analysis requires unlocked vault | `test/core/vault/vault_service_test.dart` | Locked vault throws `VaultLockedException` |
| Deleted item is excluded | `test/core/vault/vault_service_test.dart` | Report total excludes soft-deleted rows |

## Health Page Test Matrix

| Case | Test File | Expected |
| --- | --- | --- |
| Health tab visible in bottom navigation | `test/features/security_health_test.dart` | Finds `vault-shell-health-tab` |
| Report summary visible | `test/features/security_health_test.dart` | Shows total, high-risk count, warning count |
| Finding list visible | `test/features/security_health_test.dart` | Shows title and localized reason labels |
| Empty healthy vault | `test/features/security_health_test.dart` | Shows no-risk empty state |
| Health analysis failure | `test/features/security_health_test.dart` | Shows check failure message |
| Pull to refresh | `test/features/security_health_test.dart` | Calls analysis again |

## Generator Test Matrix

| Case | Test File | Expected |
| --- | --- | --- |
| Strong preset | `test/core/password_generator/password_generator_test.dart` | 24 chars, lower/upper/digit/symbol |
| Compatible preset | `test/core/password_generator/password_generator_test.dart` | 20 chars, no symbols |
| Passphrase preset | `test/core/password_generator/password_generator_test.dart` | Four words plus number |
| Passphrase rejects fewer than three words | `test/core/password_generator/password_generator_test.dart` | Throws `PasswordGeneratorException` |
| UI exposes presets | `test/features/generator_settings_test.dart` | Shows `强密码`, `密码短语`, `兼容网站` |
| UI can copy generated password | `test/features/generator_settings_test.dart` | Shows copy success snackbar |
| UI can save generated password | `test/features/generator_settings_test.dart` | Navigates to edit page with password prefilled |
| Background clears generated password | `test/features/generator_settings_test.dart` | Generated secret disappears after paused state |

## Sensitive Plaintext Lifecycle Test Matrix

| Case | Test File | Expected |
| --- | --- | --- |
| Detail password hidden by default | `test/features/vault_item_flow_test.dart` | Password text absent until reveal |
| Detail password hides on app background | `test/features/vault_item_flow_test.dart` | Password text absent after `paused` |
| Detail password hides on page dispose | `test/features/vault_item_flow_test.dart` | Returning to list does not keep visible secret |
| Edit clears password controller on save | `test/features/vault_item_flow_test.dart` | Password controller no longer exposes old value after save |
| Edit clears sensitive fields on cancel/back | `test/features/vault_item_flow_test.dart` | Password/notes clear before pop |
| Clipboard clears password on background | `test/core/security/clipboard_and_lock_test.dart` | Pending password clear executes immediately |
| Username copy does not schedule password clear | `test/core/security/clipboard_and_lock_test.dart` | No pending password cleanup |

## Unlock And Error-State Test Matrix

| Case | Test File | Expected |
| --- | --- | --- |
| Wrong master password shows generic failure | `test/features/setup_unlock_test.dart` | No sensitive technical detail |
| Repeated failures show cooldown | `test/features/setup_unlock_test.dart` | Message includes `稍后` and seconds |
| Successful unlock resets cooldown | `test/features/setup_unlock_test.dart` | Retry state cleared |
| Biometric failure falls back to master password | `test/features/setup_unlock_test.dart` | Master unlock form remains usable |
| Integrity failure locks vault | `test/core/vault/vault_service_test.dart` | Session locked after failure |

## Regression Test Matrix

| Area | Test Files |
| --- | --- |
| Crypto and KDF | `test/core/crypto/crypto_service_test.dart` |
| Vault CRUD and plaintext absence | `test/core/vault/vault_service_test.dart` |
| Manifest integrity | `test/core/vault/vault_service_test.dart`, `test/core/vault/vault_service_anchor_test.dart` |
| Backup import/export | `test/core/backup/backup_service_test.dart` |
| Clipboard and auto-lock | `test/core/security/clipboard_and_lock_test.dart` |
| Setup/unlock routing | `test/app/app_routing_test.dart`, `test/features/setup_unlock_test.dart` |
| Generator/settings | `test/features/generator_settings_test.dart` |
| Vault item flow | `test/features/vault_item_flow_test.dart` |
| Android hardening | `test/android_integration_test.dart` |

## Manual QA Checklist

Run these manually on Android after automated tests:

- Create a new vault with a strong master password.
- Try `password123456` as master password and confirm it is rejected.
- Add three entries: one strong, two reused weak passwords.
- Open the health tab and confirm reused/weak entries are marked high risk.
- Reveal a password, background the app, return, and confirm the vault is locked or the password is hidden.
- Generate a strong password, copy it, wait for configured cleanup, and confirm clipboard no longer contains it.
- Generate a passphrase and save it to a new entry.
- Export a backup, import it into a clean local vault, and confirm entries decrypt.
- Enable biometric unlock, lock, unlock with biometric, then disable biometric.
- Change master password and confirm old password no longer unlocks.

## Acceptance Criteria

- Full automated suite passes with `flutter test --reporter compact`.
- Static analysis passes with `flutter analyze`.
- No new plaintext fields are added to SQLite schema.
- No network permission, cloud sync, remote password lookup, or plaintext search index is introduced.
- Password health analysis only runs on unlocked, decrypted in-memory data.
- Generated passwords and revealed passwords are cleared or hidden on background/lock/dispose.
- User-facing security messages are actionable without exposing sensitive internals.

