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
- Android manifests declare `android.permission.INTERNET` for explicit opt-in cloud sync and `USE_BIOMETRIC` for biometric quick unlock. Android platform backup remains disabled so local vault data is not uploaded through OS backup.
- Android Autofill Stage A declares a native `AutofillService` with `BIND_AUTOFILL_SERVICE`, `android.service.autofill.AutofillService`, and `android.autofill` metadata. The native service currently returns no fill datasets, so Android can enable the provider without the background service reading SQLite, secure storage, master password material, DEK/KEK, or decrypted item fields.
- The Flutter `lockly/autofill` platform channel reads Android support/enabled status and opens system Autofill settings only. The Settings Autofill section does not request the local vault passphrase or expose plaintext values.
- Cloud sync is gated by `LOCKLY_SYNC_BASE_URL`. Non-local cleartext HTTP endpoints are rejected; HTTPS is required outside localhost development. The only HTTP development exceptions are loopback hosts and Android emulator host alias `10.0.2.2`.
- Cloud account credentials are separate from the local master password. Cloud login does not unlock the vault.
- Cloud sync device ids and local sync cursor/revision/conflict state are account-scoped. Logging out or switching cloud accounts clears the local sync state before registering a new device; if account-change device registration fails, old device id and account binding are already removed.
- Cloud sync uploads encrypted vault metadata, encrypted manifest integrity data, and encrypted item rows only. It does not upload the master password, KEK, raw DEK, decrypted entries, password history plaintext, TOTP plaintext, or biometric DEK copies.
- Cloud vault metadata reads and updates include the active cloud device id. Metadata updates use the current server revision returned by `/vault/meta`, so stale encrypted manifest uploads receive a conflict instead of silently overwriting another device's manifest.
- Initial cloud vault metadata creation omits the update-only revision field, matching the backend `/vault/init` contract while still keeping the encrypted manifest zero-knowledge.
- Passkey Stage A stores relying-party and credential metadata only inside encrypted vault item JSON. No passkey private key, raw credential secret, user handle, or platform-bound secret is exposed as backend fields; sync still transmits only opaque item ciphertext.
- Cloud attachment sync uploads encrypted blob metadata/content only. Attachment display names, MIME types, and file bytes are encrypted locally under a per-blob HKDF key; sync payloads carry only encrypted fields, AAD mac/schema, ciphertext hash/size, revision, timestamps, and tombstone state.
- Attachment UI management is unlocked-vault only. Attachment lists show decrypted display names and sizes, but plaintext content is loaded only after an explicit open action; add/open dialog plaintext is kept in transient widget state and then passed to the existing encrypted blob service boundary.
- Cloud item/blob sync also carries client manifest timestamps (`created_at`, `updated_at`, `deleted_at`) so cloud download can rebuild the encrypted backup manifest exactly without inferring local row descriptors from a server cursor.
- Cloud sync rejects mixed `applied` plus `conflicts` push responses as a protocol violation. The backend returns `applied=[]` for item/blob conflict batches so encrypted rows and vault manifest metadata cannot be advanced out of step.
- Combined item+blob sync uses the backend `/sync/push-vault` atomic push when both domains are present, so a blob conflict cannot persist item rows, and an item conflict cannot persist blob rows under a mismatched manifest.
- Cloud attachment conflicts are metadata-only (`blob_id`, client revision, server revision) and do not echo encrypted blob payloads or plaintext attachment details.
- Security Center displays unresolved encrypted item and encrypted blob sync conflicts from local sync state without rendering remote payload ciphertext or attachment plaintext metadata.
- Settings reports `Sync conflicts detected` when encrypted item or blob pushes return conflicts, instead of presenting the sync action as successful.
- Successful non-empty cloud sync first performs a skip-mode cloud download to import remote additions without overwriting local duplicates or resurrecting local tombstones. That pre-sync path records revision state only for rows actually added locally and does not advance the global pull cursor, so skipped duplicate remote rows still conflict during the subsequent push instead of being silently overwritten.
- After the pre-sync additions pass, cloud sync pushes the refreshed local encrypted snapshot, uploads matching encrypted manifest metadata, and performs a final download/merge pass so pull cursors and remote tombstones converge after upload.
- Cloud downloads stage pulled encrypted rows without advancing `last_pull_cursor` or item revision state. Cursor/revision state is committed only after local backup import and remote tombstone handling succeed.
- Cloud downloads stage pulled encrypted blobs without advancing `last_blob_pull_cursor` or blob revision state. Blob cursor/revision state is committed only after local backup import and remote tombstone handling succeed.
- Remote deleted sync items are applied as local encrypted-vault soft deletes before the next upload, so a local item is not re-uploaded and resurrected after another device deleted it.
- Remote deleted sync blobs are applied as local encrypted-vault blob soft deletes before the next upload, so deleted attachments are not resurrected by a later sync.
- Cloud sync DTOs reject unsupported or forbidden response fields for auth, account, device, vault metadata, item, push, and pull responses. Wrapped backend responses must not include sibling fields outside the expected envelope.
- Blob sync DTOs reject plaintext-shaped attachment fields such as filename, MIME/media type, file path, raw key, plaintext, and file bytes before upload or import.
- Emergency Access sync DTOs parse contacts, grant metadata, grant list envelopes, and ready package download responses with zero-knowledge field checks. Contact public key and recipient key fingerprint are narrow protocol exceptions to the generic `key` field guard; unsupported or secret-shaped fields still fail closed.
- Emergency Access grant and package DTOs accept only official backend statuses: `pending_acceptance`, `active`, `access_requested`, `ready_for_download`, `downloaded`, `cancelled`, `revoked`, and `expired`; stale statuses such as `accepted` fail closed before UI logic can act on them.
- Emergency grant metadata and list responses reject `encrypted_recovery_package`; only the package download DTO accepts that encrypted envelope. Package download responses reject plaintext recovery fields and package envelopes with unsupported fields.
- Emergency Access request DTOs validate package envelopes as exact JSON object strings with `ciphertext`, `nonce`, and `mac`, validate `package_aad` with `schema: lockly-emergency-package-v1` and `mac`, and reject plaintext/key-material markers before `SyncApiClient` sends a request.
- Emergency Access client crypto uses versioned X25519 recipient keys, HKDF-SHA256, and AES-256-GCM. Recovery packages include the ephemeral sender public key only as ciphertext prefix, bind authenticated data to schema, mac, grant id, and recipient key fingerprint, and reject tampered envelopes, AAD, fingerprints, or wrong recipient private keys.
- Emergency Access contact DTOs reject versioned private-key token values in `recipient_public_key`, so a client cannot accidentally upload the recipient emergency private key through contact metadata.
- Emergency Access service facade methods only forward authenticated zero-knowledge contacts, grant metadata, request metadata, and encrypted recovery package DTOs through `SyncService`; they do not accept or upload the local master password, raw DEK/KEK, private emergency keys, or decrypted recovery package plaintext.
- Emergency package readiness and release require the backend contact to remain active. Promotion from `access_requested` to `ready_for_download` and final `ready_for_download` to `downloaded` both include active-contact database predicates, so contact revocation races fail closed and do not return `encrypted_recovery_package`.
- Emergency Access UI creates contacts and grants from local inputs while preserving the zero-knowledge boundary. Grant creation encrypts the local recovery package with the recipient public key before calling sync services, then clears the plaintext controller; generated recipient private keys are display-only without an AppServices clipboard path, and downloaded package decryption stays inside local UI dialogs without sending the private key or plaintext package to backend sync methods.
- Emergency Access package download UI appears for `ready_for_download` grants and for `access_requested` grants only after `ready_at` has elapsed. The backend still performs the authoritative waiting-period and active-contact checks before returning any encrypted package.
- Emergency Access OpenAPI metadata declares request bodies for grant creation, recipient acceptance, and access requests, matching the documented zero-knowledge API contract.
- Cloud vault metadata validates DEK envelopes and encrypted manifests fail-closed: only expected `ciphertext`, `nonce`, and `mac` fields are accepted, and obvious plaintext/key-material markers in those values are rejected before cloud backup import.
- Ordinary cloud sync and cloud download both require the local master password before imported remote ciphertext is accepted through the existing backup manifest verification path.
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
