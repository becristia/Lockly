# Sync Conflict UI Plan

> For agentic workers: implement with TDD. Keep changes scoped to `Lockly` unless this plan is explicitly revised. Do not revert edits made by other workers.

## Goal

Turn the existing Security Center conflict count into a usable conflict-management surface while preserving Lockly's zero-knowledge sync boundary.

## Scope

- Show unresolved local sync conflict records from `SyncStateDao`.
- Render only safe metadata: item id, local/client revision, cloud/server revision, and local conflict timestamp.
- Provide an explicit "download latest encrypted vault" path that asks for the local master password and imports through the existing encrypted backup/manifest verification flow.
- Clear conflict records only after a cloud download has been imported and committed successfully.

## Non-Goals

- Do not show remote payload JSON, ciphertext, decrypted titles, usernames, passwords, notes, TOTP data, passkeys, or attachment data.
- Do not resolve conflicts by trusting the backend account password.
- Do not advance pull cursor or clear conflicts before local import and tombstone handling succeeds.
- Do not add side-by-side decrypted comparison in this slice.

## Architecture

- `SecurityCenterPage` owns the conflict dialog and master-password prompt because it already loads conflict state.
- `AppServices` remains the UI facade. It exposes `clearSyncConflict()` only for safe post-import cleanup paths and test fakes.
- `SyncService` delegates conflict clearing to `SyncStateDao`.
- `downloadCloudEncryptedVault()` imports the staged cloud backup first, applies remote tombstones, commits pulled item revisions/cursor, then clears conflicts for the imported item ids.

## TDD Steps

- [x] Add a widget test that tapping the Security Center conflict card opens a list of unresolved conflicts with safe metadata and no payload bytes.
- [x] Add a widget test that the conflict dialog can start cloud download after local master-password confirmation, refreshes the conflict count, and does not expose the password.
- [x] Add a service test proving successful cloud download clears only conflicts for pulled item ids after import/commit.
- [x] Add `SyncService.clearConflict()` and `AppServices.clearSyncConflict()` or an equivalent narrowly scoped cleanup path.
- [x] Implement the Security Center dialog and explicit download action.
- [x] Run targeted Flutter tests and `flutter analyze`.

## Verification

- `flutter test test/features/security_center_test.dart test/app/cloud_sync_test.dart test/core/sync/sync_service_test.dart`
- `flutter analyze`

## Acceptance

- Security Center conflict count remains visible.
- Conflict details are actionable without leaking payload data.
- Conflict cleanup happens after successful verified import, not before.
- Analyzer reports no issues.
