# Audit hardening progress - 2026-05-30

Scope: all changes are under `Lockly/`.

## Security and logic

- LAN transfer no longer uses the source master password as transferred package wrapping material. The sender master password is used only for local re-authentication; the package is wrapped with a generated one-time LAN package password carried in the QR payload.
- LAN QR payload validation now includes the package password field, keeps transfer key/token out of the HTTP URI, and the server still enforces TTL plus single-use transfer semantics.
- Imported or mutated manifests now stage a pending anchor marker inside the same database transaction before anchor acceptance. A verified pending manifest can be repaired on the next master-password unlock if secure anchor writing failed after commit.
- Vault manifest mutations are serialized through an async commit mutex so concurrent writes cannot interleave manifest and anchor acceptance.
- Biometric metadata rewrites now use the same serialized manifest/anchor commit path as item mutations, preventing a concurrent operation from observing a committed manifest before its anchor is accepted.
- Biometric unlock can repair a verified pending-anchor manifest after a post-commit anchor write failure, while a missing anchor still fails closed for biometric unlock.
- Backup import paths stage pending anchors for imported manifests before accepting them.
- KDF parameter parsing now rejects excessive PBKDF2 and Argon2id work factors before derivation.
- LAN server response cleanup now closes the session in a `finally` path after the response attempt.
- Plaintext CSV import now uses a bulk vault item creation path for production imports, so imported rows are committed under one manifest mutation instead of per-row best-effort rollback.
- LAN send auto-lock extension is runtime-only and no longer persists a temporary 5-minute timeout setting.
- Windows tray minimize now lets Flutter process the minimize lifecycle message before the native window hides to tray.

## Usability

- Windows right-edge auto-hide is disabled by default; the legacy behavior remains opt-in and the poll interval is 250 ms instead of 50 ms.
- Tray and Flutter window tooltips now say "Minimize to tray" and the native tray menu exposes Restore and Exit.
- The unlocked vault shell has a Lock now action.
- Attachment deletion requires a destructive confirmation dialog that includes the attachment name.
- Settings load failures show a retry state instead of failing silently.
- Setup and LAN copy explain that the master password is not saved or recoverable, and that LAN is a one-time local transfer, not continuous sync.
- Windows titlebar controls are wrapped in an overlay so tooltips can render outside the Navigator tree.

## Verification

- Passed: `flutter analyze --no-pub`
- Passed after final review fixes: `flutter analyze --no-pub`
- Passed after final review fixes: `flutter test --no-pub --reporter compact -j 1 test/core/vault/vault_service_anchor_test.dart test/core/vault/vault_service_test.dart` (72 tests)
- Final read-only subagent re-review after the vault manifest/anchor fixes: no warning-or-higher issues found.
- Passed: `flutter test --no-pub --reporter compact -j 1 test/core/crypto/crypto_service_test.dart test/core/lan_sync/lan_transfer_models_test.dart test/core/lan_sync/lan_transfer_service_test.dart test/core/lan_sync/lan_transfer_transport_test.dart test/core/vault/vault_service_anchor_test.dart test/core/backup/backup_service_test.dart test/features/lan_sync_page_test.dart` (151 tests)
- Passed after the final backup import serialization pass: `flutter test --no-pub --reporter compact -j 1 test/core/lan_sync/lan_transfer_service_test.dart test/core/vault/vault_service_anchor_test.dart test/core/backup/backup_service_test.dart` (91 tests)
- Passed: `flutter test --no-pub --reporter compact -j 1 test/app/app_routing_test.dart test/features/setup_unlock_test.dart test/features/vault_item_flow_test.dart test/features/generator_settings_test.dart test/ui/visual_system_test.dart test/ui/windows_window_controls_test.dart test/windows_configuration_test.dart` (70 tests)
- Attempted full suite: `flutter test --no-pub --reporter compact -j 1` exceeded the 6-minute command timeout; a leftover `flutter_tester` process was stopped. No assertion failure was captured before timeout.

Environment note: Flutter tests need proxy variables cleared and `NO_PROXY/no_proxy=localhost,127.0.0.1,::1`; otherwise the test runner WebSocket can fail with an invalid upgrade.

## Follow-up review and platform verification - 2026-05-30

Scope: all follow-up edits remained under `Lockly/`.

### Review findings closed

- Security: pending vault anchors are now written and matched through the secure anchor store instead of a forgeable SQLite marker. A forged SQLite pending-anchor setting no longer bypasses rollback protection.
- Security: LAN receive clears a pasted QR payload after successful parsing so the one-time transfer key, token, and package password do not remain visible in the text field.
- Security: fake app services no longer retain the plaintext master password after create-vault setup.
- Logic: overwrite backup import explicitly clears `password_history` before replacing blobs/items and accepting the imported manifest, so manifest/anchor acceptance does not depend on SQLite cascade behavior.
- Security: manifest mutations now write the secure pending anchor inside the database transaction before saving the new manifest. If pending anchor writing fails, the database mutation rolls back instead of leaving SQLite ahead of the accepted anchor with no recovery marker.
- Security: backup import manifest rewrites now stage the pending anchor inside the import transaction and skip duplicate post-commit pending writes during anchor acceptance.
- Security: merge imports verify the existing target manifest/anchor before any blob-only or history-only mutation, so a tampered local vault state cannot be signed into a new accepted anchor.
- Logic/usability: migration and backup-export flows block route pops while work is busy, validate required JSON/password fields before import, and show Security Center import completion feedback.
- Usability: Security Center is exposed as a primary shell destination, includes encrypted backup export plus migration import, and pads the refresh action away from the shell lock button.
- Platform: Windows frame content updates when parent state changes while preserving the overlay needed for titlebar tooltips.
- Test hygiene: the TOTP URL-without-issuer fixture now uses a valid unpadded Base32 secret length instead of weakening TOTP secret validation.

### Verification

- Passed after follow-up fixes: `flutter analyze --no-pub` (no issues found).
- Passed after follow-up fixes: `flutter test --no-pub --reporter compact -j 1` (498 tests).
- Passed: `flutter build windows --debug --no-pub`; output `build\windows\x64\runner\Debug\Lockly.exe`.
- Passed: `flutter build apk --debug --no-pub` with `JAVA_HOME=D:\Program Files\Android\Android Studio\jbr`; output `build\app\outputs\flutter-apk\app-debug.apk`.
- Passed: `flutter install -d emulator-5554 --debug`; installed the debug APK on the Android emulator `sdk gphone16k x86 64`.
