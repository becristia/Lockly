# Security Center And Backup Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Security Center as a primary unlocked tab and guide encrypted backup export through a safer wizard.

**Architecture:** Keep `AppServices` as the UI facade. Add one focused backup export wizard page under `features/migration/`, wire it from Settings and Security Center, and keep import logic in the existing migration wizard.

**Tech Stack:** Flutter Material, existing Lockly `SecureVisual*` widgets, existing backup and clipboard services.

---

### Task 1: Security Center Shell Entry

**Files:**
- Modify: `lib/features/vault_shell/vault_shell_page.dart`
- Modify: `test/app/app_routing_test.dart`

- [ ] Write a widget test expecting `vault-shell-security-tab` to be present and open `security-center-page`.
- [ ] Run the test and confirm it fails because the tab is absent.
- [ ] Add `SecurityCenterPage` to the vault shell page switch and mobile/desktop destinations.
- [ ] Run the route test and confirm it passes.

### Task 2: Backup Export Wizard

**Files:**
- Create: `lib/features/migration/backup_export_wizard_page.dart`
- Modify: `lib/features/settings/settings_page.dart`
- Modify: `lib/features/security_center/security_center_page.dart`
- Modify: `lib/shared/i18n/app_strings_en.dart`
- Modify: `lib/shared/i18n/app_strings_zh.dart`
- Modify: `test/features/generator_settings_test.dart`

- [ ] Write a widget test that opens backup export, enters master password, sees backup metadata, and confirms the full JSON is not rendered.
- [ ] Run the test and confirm it fails because no export wizard page exists.
- [ ] Implement `BackupExportWizardPage` with prepare and ready states.
- [ ] Wire Settings export and Security Center export to the wizard.
- [ ] Add localized labels for export status and metadata.
- [ ] Run the feature test and confirm it passes.

### Task 3: Verification

**Files:**
- Modify: `docs/audit-hardening-progress-2026-05-30.md`

- [ ] Run `flutter analyze --no-pub`.
- [ ] Run targeted widget tests for routing, settings, migration, and security center.
- [ ] Run Windows build/test command available in the local environment.
- [ ] Run Android build/test command available in the local environment.
- [ ] Document completed verification and any platform limitations.
