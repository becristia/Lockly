# Lockly Import Migration Wizard Design

## Goal

Replace the single backup-import paste dialog with a local migration wizard that helps users import Lockly encrypted backups or plaintext CSV exports without weakening the zero-knowledge vault boundary.

## Security Boundary

- Lockly encrypted JSON import continues to use `BackupService.importBackup()` through `AppServices.importEncryptedBackupJson()`.
- CSV import is local-only. CSV text is pasted into the app, parsed in memory, converted to `PasswordEntry`, and written through `AppServices.createVaultItem()` so every imported item is encrypted before persistence.
- CSV plaintext must never be sent to `backend-pass`, copied to logs, included in sync DTOs, or displayed in preview rows.
- The wizard may show source type, row count, skipped row count, and non-sensitive fields such as title/website/username. It must not show imported passwords, notes, TOTP secrets, or raw CSV after parsing.
- Existing size limits remain: imported backup JSON is capped by `AppServices.maxImportedBackupJsonBytes`; CSV gets its own smaller in-memory text cap.

## Product Shape

The Settings backup section opens a `MigrationWizardPage` instead of the old `_BackupImportDialog`.

Step 1: Choose source

- Lockly encrypted backup JSON.
- CSV from another password manager.

Step 2: Paste source

- Lockly JSON requires backup JSON and backup master password.
- CSV requires pasted CSV text. No master password is required for CSV because it is already plaintext; the vault is already unlocked and local encryption happens during item creation.

Step 3: Preview

- Lockly JSON: show mode, format, and that encrypted import will verify the backup password and manifest.
- CSV: show total parsed rows, importable rows, skipped rows, and sanitized preview rows with title, website, and username only.

Step 4: Import

- Lockly JSON calls `AppServices.importEncryptedBackupJson()` with `BackupImportMode.merge`.
- CSV calls a new `AppServices.importPlaintextCsv()` facade that parses and creates items locally.

## CSV Contract

The first implementation supports a dependency-free CSV parser with quoted field support. The first row must be headers. Recognized columns:

- title aliases: `title`, `name`, `login_title`
- website aliases: `website`, `url`, `uri`, `login_uri`
- username aliases: `username`, `login_username`, `email`
- password aliases: `password`, `login_password`
- notes aliases: `notes`, `note`
- tags aliases: `tags`, `folder`
- totp aliases: `totp`, `totp_secret`, `otp`

Importable rows require at least one non-empty title/website/username and a non-empty password. Missing title falls back to website, then username, then `Imported item`.

## Architecture

- Add `lib/core/migration/plaintext_csv_importer.dart`.
  - Owns CSV parsing, column mapping, row validation, count reporting, and conversion to `PasswordEntry`.
  - No Flutter imports.
- Extend `AppServices`.
  - `previewPlaintextCsvImport(String csvText)` returns a safe report.
  - `importPlaintextCsv(String csvText)` parses again and creates importable entries through `createVaultItem()`.
- Add `lib/features/migration/migration_wizard_page.dart`.
  - Stateful wizard UI using existing `SecureVisualBackground`, `SecureReplicaHeader`, `SecureGlassCard`, and Material controls.
  - Does not render passwords, notes, TOTP secrets, or raw CSV after preview.
- Update `SettingsPage`.
  - The backup section keeps export.
  - Import opens the migration wizard page and shows a result snackbar after it returns.

## Error Handling

- Invalid CSV format returns a generic local parse error.
- Oversized CSV is rejected before parsing.
- CSV rows missing required data are skipped and counted.
- Lockly JSON import failures continue to show the existing generic failure messaging.
- No raw exception string is rendered in the UI.

## Testing

- Unit tests for CSV parser:
  - maps common headers to `PasswordEntry`;
  - supports quoted commas and escaped quotes;
  - skips incomplete rows;
  - rejects oversized input;
  - never includes password/notes/totp in preview data.
- AppServices tests:
  - CSV import creates encrypted local vault entries through `createVaultItem()`;
  - preview report is safe.
- Widget tests:
  - Settings opens migration wizard from the backup section;
  - CSV paste preview hides plaintext secrets and imports rows;
  - Lockly JSON path still asks for backup master password and calls encrypted backup import.

## Non-Goals

- No OS file picker in this slice.
- No cloud upload or sync trigger after migration.
- No brand-specific import templates beyond flexible CSV header aliases.
- No plaintext export.
