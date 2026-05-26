# Secure Box Security Check

Date: 2026-05-24

## Commands

- `flutter test --reporter compact`
- `flutter analyze`
- `rg -n "MD5|SHA1|sha1|sha256\(|print\(|debugPrint\(|log\(|password|masterPassword|secret" lib test`
- `rg -n "CREATE TABLE vault_items|CREATE TABLE vault_manifest|username|password|notes|title|vault_anchor|anchor" lib/data/db lib/data/models lib/core/vault`
- `rg -n "android.permission.INTERNET" android`
- `flutter test --reporter compact test\core\sync test\data\db\sync_state_dao_test.dart test\ui\visual_system_test.dart test\android_integration_test.dart`
- `flutter test -r compact test\core\autofill\android_autofill_service_test.dart test\android_integration_test.dart test\ui\visual_system_test.dart`
- `flutter test -r compact test\core\sync\sync_api_client_test.dart test\core\sync\sync_models_test.dart`
- `flutter test -r compact test\core\sync\sync_api_client_test.dart test\core\sync\sync_service_test.dart`
- `flutter test -r compact test\features\generator_settings_test.dart test\features\security_center_test.dart test\app\cloud_sync_test.dart`
- `flutter test`
- `python -m pytest -q` in `backend-pass`
- `flutter build apk --debug --dart-define=LOCKLY_SYNC_BASE_URL=http://10.0.2.2:8765`
- `adb install -r build\app\outputs\flutter-apk\app-debug.apk`
- `adb shell monkey -p com.lockly.securebox 1`
- `adb shell uiautomator dump /sdcard/lockly_ui.xml`

## Result

- `flutter test -r compact` passed after encrypted attachment sync, backup hardening, passkey preparation metadata, attachment UI management, Android Autofill Stage A, Emergency Access client DTO/API integration, Emergency path-segment hardening, Emergency Access client crypto, service facade wiring, Emergency recipient public-key private-token rejection, Emergency Access management UI, vault metadata device/revision sync, and blob-conflict UI status: 480 tests.
- Backend `python -m pytest -q` passed after Emergency Access grant/package, duplicate-grant hardening, concurrent grant state-transition hardening, active-contact package release gating, and vault metadata active-device/revision conflict handling: 107 tests.
- `flutter analyze` passed on 2026-05-24: no issues found.
- No MD5 or SHA1 usage was found.
- `sha256` appears only as the HMAC algorithm inside PBKDF2-HMAC-SHA256, HKDF/HMAC-SHA256 manifest key derivation, canonical manifest digests, and corresponding tests. It is not used as a direct master-password hash.
- Argon2id is the default KDF for newly created vaults and for master-password rotation.
- PBKDF2-HMAC-SHA256 remains supported only for existing vault metadata and imported legacy backups.
- No `print`, `debugPrint`, or logging call that writes sensitive values was found. The `log(` scan matches `AlertDialog(` UI code only.
- Sensitive names such as `password`, `masterPassword`, and `secret` appear in service parameters, UI controllers, decrypted model code, and test fixture values. They are not logged.
- `vault_items` stores only `id`, `nonce`, `ciphertext`, `mac`, timestamps, and deletion state.
- `vault_manifest` stores only singleton metadata, manifest version, epoch, counter, nonce, ciphertext, mac, and updated timestamp.
- `vault_blobs` stores only blob/item ids, encrypted metadata/content nonces, ciphertexts, macs, timestamps, and deletion state. It does not store attachment filename, MIME type, path, plaintext bytes, or raw keys.
- Sensitive item fields are serialized into one JSON payload and encrypted before persistence.
- Vault manifest integrity is enabled for new vaults and normal unlock now fails closed if the manifest is missing or invalid.
- Live vault mutations verify the previous manifest and rewrite one new manifest in the same transaction, detecting item tampering, item deletion, metadata envelope replacement, and manifest rollback/mismatch.
- Vault rollback anchor is stored in platform secure storage, not SQLite, and contains only vault id, schema version, manifest epoch/counter, manifest digest, and timestamp.
- Master-password unlock can recreate a missing platform anchor only after encrypted manifest verification succeeds.
- Biometric unlock requires an existing matching platform anchor and falls back to the master password if the anchor is missing or invalid.
- Runtime unlock and mutation preflight require an existing platform anchor to match the encrypted manifest epoch, counter, and digest exactly, so whole-database rollback below the platform anchor or SQLite advancing beyond a stale anchor fails closed.
- Backup import anchor preflight checks run before destructive writes. Overwrite import verifies the existing target anchor, checks the imported vault-id anchor before accepting the replacement, and skip no-op verifies the current target anchor before returning success.
- Backup version 2 includes `magic`, `item_count`, source biometric metadata needed for manifest verification, and an encrypted manifest. Version 1 backup import remains supported as a legacy path that generates a target manifest.
- Version 2 backup import verifies the backup master password and manifest before writing target data, and rejects item, manifest, biometric metadata, item count, and magic mismatches.
- Android manifests declare `android.permission.INTERNET` for explicit opt-in LAN exchange and `USE_BIOMETRIC` for biometric quick unlock. Android platform backup remains disabled so local vault data is not uploaded through OS backup.
- Android Autofill Stage A declares a native `AutofillService` with `BIND_AUTOFILL_SERVICE`, `android.service.autofill.AutofillService`, and `android.autofill` metadata. The native service currently returns no fill datasets, so Android can enable the provider without the background service reading SQLite, secure storage, master password material, DEK/KEK, or decrypted item fields.
- The Flutter `lockly/autofill` platform channel reads Android support/enabled status and opens system Autofill settings only. The Settings Autofill section does not request the local vault passphrase or expose plaintext values.
- LAN exchange has no cloud account, cloud cursor, remote backend, or shared master password. The sender creates a short-lived local HTTP listener and QR payload; the payload carries an application-layer encrypted package plus an unguessable token.
- LAN exchange sends only user-selected records. The receiver imports non-conflicting records only; conflicting identities are reported and skipped.
- The receiver must enter the sender's master password to decrypt the transfer package. Accepted records and attachments are then re-encrypted under the receiver's current vault key before local persistence, so the two devices do not need matching master keys.
- LAN transfer HTTP is local transport only. The QR payload uses local/private host constraints, a short expiry, a one-use token, and encrypted package integrity checks; no plaintext password, raw DEK/KEK, biometric DEK copy, TOTP plaintext, or attachment plaintext is exposed to the transport.
- Passkey Stage A stores relying-party and credential metadata only inside encrypted vault item JSON. No passkey private key, raw credential secret, user handle, or platform-bound secret is exposed as backend fields; sync still transmits only opaque item ciphertext.
- Attachment export and LAN transfer include encrypted blob metadata/content only. Attachment display names, MIME types, and file bytes are encrypted locally under a per-blob HKDF key.
- Attachment UI management is unlocked-vault only. Attachment lists show decrypted display names and sizes, but plaintext content is loaded only after an explicit open action; add/open dialog plaintext is kept in transient widget state and then passed to the existing encrypted blob service boundary.
- LAN package DTOs and models validate QR payload shape, expiry, local/private hosts, encrypted envelope structure, and package integrity before import.
- LAN import requires the source master password before imported ciphertext is accepted through the existing backup manifest verification path.
- Backup version 2 includes encrypted attachment blobs and signs the selected backup items, encrypted blobs, and password-history records in the manifest. Backups reject tampered blob metadata/content by manifest verification and preserve attachments across overwrite, skip, and different-envelope imports by re-encrypting blobs under the target vault key when needed.
- Import migration supports local plaintext CSV parsing only inside the unlocked client. CSV passwords, notes, and TOTP secrets are not sent to the backend or rendered in previews; imported rows are immediately written through encrypted vault item creation.
- Passkey Stage A stores relying-party and credential metadata only inside encrypted vault item JSON. No passkey private key, raw credential secret, or platform-bound secret is exposed as backend fields; sync still transmits only opaque item ciphertext.
- Android `MainActivity` uses `FlutterFragmentActivity` for `local_auth` compatibility and enables `FLAG_SECURE` for screenshot/task-preview masking.
- Android biometric unlock stores only a DEK copy, uses biometric Android secure storage options with `enforceBiometrics: true`, and still requires the app-level `local_auth` biometric-only gate before reading the DEK copy.
- Biometric unlock failure continues to fall back to the master password.
- `VaultSession.lock()` zeroes session-owned DEK bytes before dropping the reference.
- Temporary DEK copies in biometric enable/unlock are zeroed where ownership is clear, including invalid-length biometric DEK reads.
- Password detail and edit pages clear transient plaintext state from controllers/state during dispose.

## Residual Notes

- Android debug APK build and install were verified on the `Pixel_10_Pro_XL` emulator. The installed app launched to the first-run master password setup UI. Screenshots are black by design because `FLAG_SECURE` blocks capture; UI readiness was verified through `uiautomator` hierarchy text and absence of `DatabaseException`, unhandled Dart exception, `FATAL EXCEPTION`, or `AndroidRuntime` crash logs.
