# UI TOTP Settings Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh Lockly UI, remove the redundant Security tab, add encrypted standalone TOTP entry support, align Settings layout, extend LAN-send auto-lock timing, and improve dialogs.

**Architecture:** Standalone MFA secrets are represented as encrypted `PasswordEntry` payloads with an `isStandaloneTotp` marker. UI-only work stays in shared theme/widgets and feature pages; security-sensitive persistence continues through existing vault encryption APIs.

**Tech Stack:** Flutter, Material 3, existing Lockly `AppServices`, `VaultService`, `PasswordEntry`, `TotpService`, and Flutter widget tests.

---

### Task 1: TOTP Core and Encrypted Standalone Entries

**Files:**
- Modify: `lib/data/models/password_entry.dart`
- Modify: `lib/core/password_generator/totp_service.dart`
- Modify: `lib/core/vault/vault_service.dart`
- Modify: `lib/app/app_services.dart`
- Test: `test/core/password_generator/totp_service_test.dart`
- Test: `test/data/models/password_entry_test.dart`
- Test: `test/core/vault/vault_service_test.dart`

- [x] Add tests for Base32 normalization, otpauth parsing with standalone defaults, `PasswordEntry.isStandaloneTotp`, vault list filtering, health filtering, and TOTP list inclusion.
- [x] Implement `PasswordEntry.isStandaloneTotp` with backward-compatible JSON parsing.
- [x] Implement TOTP secret normalization/validation helpers.
- [x] Skip standalone TOTP entries from password list and health analysis.
- [x] Include standalone TOTP entries in TOTP listing.
- [x] Add fake `AppServices.listTotpItems` support for widget tests.
- [x] Add focused test coverage for TOTP service, password entry model, and vault service. Focused Flutter tests pass after local Windows native assets were supplied.

### Task 2: TOTP Page UI and Save Flow

**Files:**
- Modify: `lib/features/totp/totp_page.dart`
- Modify: `lib/shared/i18n/app_strings_en.dart`
- Modify: `lib/shared/i18n/app_strings_zh.dart`
- Test: create or modify `test/features/totp_page_test.dart`

- [x] Add widget tests for action buttons, manual standalone save, TOTP card display, standalone edit/delete, and invalid secret handling.
- [x] Add a brighter header with decorative status chips.
- [x] Add scan and manual action buttons styled consistently with existing add actions.
- [x] Implement manual save dialog that stores a standalone encrypted TOTP entry through `AppServices.createVaultItem`.
- [x] Implement scanner dialog with camera gate and paste fallback, reusing the same parser/save path.
- [x] Add localized labels and error messages.
- [x] Add focused TOTP page widget coverage. Focused Flutter tests pass after local Windows native assets were supplied.

### Task 3: Navigation, Theme, Settings, and Dialog Polish

**Files:**
- Modify: `lib/features/vault_shell/vault_shell_page.dart`
- Modify: `lib/shared/theme/app_theme.dart`
- Modify: `lib/shared/widgets/secure_visuals.dart`
- Modify: `lib/features/settings/settings_page.dart`
- Modify: `lib/features/lan_sync/lan_send_page.dart`
- Modify: existing UI/routing tests under `test/`

- [x] Add tests proving the Security tab is gone, Settings sections stretch to a common width, LAN section spacing is present, LAN send extends auto-lock to at least 5 minutes, and theme tokens are brighter.
- [x] Remove Security tab/page from shell navigation.
- [x] Lighten theme and shared visual colors without reducing contrast.
- [x] Add global dialog theme styling.
- [x] Stretch Settings column/cards and segmented controls.
- [x] Add missing spacing before LAN exchange.
- [x] Extend auto-lock during LAN send session creation, preserving values above 5 minutes and restoring stricter values after cleanup.
- [x] Add focused visual/routing/settings/LAN coverage. Focused Flutter tests pass after local Windows native assets were supplied.

### Task 4: Verification and Review

**Files:**
- No planned production edits; fix only issues found by verification/review.

- [x] Run `dart analyze`.
- [x] Run relevant focused Flutter-test workflow after the missing native assets were supplied locally.
- [x] Dispatch a code-review subagent with implementation requirements and changed files.
- [x] Fix all Critical/Important/warning-or-higher findings.
- [x] Fix final review findings: saving dialogs now block barrier/route dismissal while busy, secure dialog cancel/close can be disabled, long message content scrolls, and standalone TOTP edit no longer previews the saved secret.
- [x] Re-run analyzer, platform builds, and code-review subagents; final review reported no warning-or-higher issues.

### Final Verification Notes

- `flutter analyze` reports no issues.
- Focused Flutter tests for secure dialogs, biometric localization, TOTP UI, LAN sync, visual system, Windows configuration, backup conflict handling, and LAN transfer conflict handling pass.
- `flutter build windows --release` passes when the supplied local `build/windows/x64/_deps/nuget-src/nuget.exe` is prepended to `PATH` for that build process.
- Windows smoke launch of `build/windows/x64/runner/Release/Lockly.exe` starts successfully and is terminated after startup verification.
- `flutter test test/android_integration_test.dart -r compact` passes and verifies Android local-only hardening, including release APK checks.
- `flutter build apk --debug` passes.
- `git status --short -- android` and `git diff --name-only -- android` have no output; Android project files were not changed.
- `rg -n "AlertDialog\(" lib` has no output; production dialogs use the shared secure dialog path.
- `powershell -ExecutionPolicy Bypass -File windows\installer\install_smoke.ps1 -IsccPath 'C:\Users\office\AppData\Local\Programs\Inno Setup 6\ISCC.exe'` passes with Inno Setup 6.7.3: it builds the Windows release, compiles `LocklyInstallerSetup.exe`, installs into `build/windows/install-smoke/Lockly` with `/CURRENTUSER /NOICONS`, launches briefly, then uninstalls and removes the disposable install directory.
- Installer configuration and smoke-script safety are covered by `test/windows_configuration_test.dart`.
