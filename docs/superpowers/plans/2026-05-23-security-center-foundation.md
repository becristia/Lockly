# Security Center Foundation Plan

> For agentic workers: implement this plan with TDD. Keep changes scoped to `Lockly` unless a step explicitly says otherwise. Do not revert edits made by other workers.

## Goal

Add a Security Center page to the unlocked Lockly shell that consolidates local password health, sync conflict visibility, cloud device posture, and the roadmap entry points for migration, Autofill, attachments, passkeys, and emergency access.

## Architecture

- `AppServices` remains the UI facade.
- `SyncService` exposes read-only local conflict records from `SyncStateDao`.
- `SecurityCenterPage` is a Flutter page under `lib/features/security_center/`.
- Password health analysis is explicit user action only; opening the page must not decrypt every vault item.
- `VaultShellPage` adds a Security tab between Vault and TOTP.
- No master password, key material, decrypted item payload, TOTP secret, or attachment/passkey plaintext is sent to backend or persisted outside the encrypted vault.

## File Map

| File | Action | Purpose |
| --- | --- | --- |
| `lib/core/sync/sync_service.dart` | Modify | Add read-only `conflicts()` facade over `SyncStateDao.conflicts()` |
| `lib/app/app_services.dart` | Modify | Add `listSyncConflicts()` plus fake/test override |
| `lib/features/security_center/security_center_page.dart` | Create | Render dashboard and async summaries |
| `lib/features/vault_shell/vault_shell_page.dart` | Modify | Add Security Center navigation destination |
| `test/features/security_center_test.dart` | Create | Widget tests for dashboard states |
| `test/app/app_routing_test.dart` | Modify | Confirm tab navigation keeps shell behavior stable |

## TDD Steps

- [ ] Add tests that a fake unlocked app can open the Security tab and see password health, cloud sync, device trust, migration, Autofill, attachments, passkeys, and emergency access sections.
- [ ] Add tests that `AppServices.fake` can provide local sync conflicts and the Security Center displays the unresolved count without exposing remote ciphertext.
- [ ] Add tests that opening Security Center does not run password health analysis until the user explicitly starts the local check.
- [ ] Add `SyncService.conflicts()` and `AppServices.listSyncConflicts()`.
- [ ] Implement `SecurityCenterPage` with stable keys and Material icons.
- [ ] Wire the page into `VaultShellPage` for mobile and desktop navigation.
- [ ] Run targeted Flutter tests, then `flutter analyze`.

## Acceptance

- The Security Center loads when the vault is unlocked.
- The page works when cloud sync is unavailable or not logged in.
- Conflict count comes from local sync state and does not display encrypted payload bytes.
- Device posture is summarized from the cloud device list when available.
- Analyzer reports no warning-or-higher findings.
