# Secure Box Security Check

Date: 2026-05-16

## Commands

- `flutter test`
- `flutter analyze`
- `rg -n "MD5|SHA1|sha1|sha256\(|print\(|debugPrint\(|log\(|password|masterPassword|secret" lib test`
- `rg -n "CREATE TABLE vault_items|CREATE TABLE vault_manifest|username|password|notes|title" lib/data/db lib/data/models`
- `rg -n "android.permission.INTERNET" android`

## Result

- `flutter test` passed after manifest integrity hardening: 177 tests.
- `flutter analyze` passed: no issues found.
- No MD5 or SHA1 usage was found.
- `sha256` appears only as the HMAC algorithm inside PBKDF2-HMAC-SHA256, HKDF/HMAC-SHA256 manifest key derivation, canonical manifest digests, and corresponding tests. It is not used as a direct master-password hash.
- Argon2id is the default KDF for newly created vaults and for master-password rotation.
- PBKDF2-HMAC-SHA256 remains supported only for existing vault metadata and imported legacy backups.
- No `print`, `debugPrint`, or logging call that writes sensitive values was found. The `log(` scan matches `AlertDialog(` UI code only.
- Sensitive names such as `password`, `masterPassword`, and `secret` appear in service parameters, UI controllers, decrypted model code, and test fixture values. They are not logged.
- `vault_items` stores only `id`, `nonce`, `ciphertext`, `mac`, timestamps, and deletion state.
- `vault_manifest` stores only singleton metadata, manifest version, epoch, counter, nonce, ciphertext, mac, and updated timestamp.
- Sensitive item fields are serialized into one JSON payload and encrypted before persistence.
- Vault manifest integrity is enabled for new vaults and normal unlock now fails closed if the manifest is missing or invalid.
- Live vault mutations verify the previous manifest and rewrite one new manifest in the same transaction, detecting item tampering, item deletion, metadata envelope replacement, and manifest rollback/mismatch.
- Backup version 2 includes `magic`, `item_count`, source biometric metadata needed for manifest verification, and an encrypted manifest. Version 1 backup import remains supported as a legacy path that generates a target manifest.
- Version 2 backup import verifies the backup master password and manifest before writing target data, and rejects item, manifest, biometric metadata, item count, and magic mismatches.
- Android manifests contain no `android.permission.INTERNET` permission, and `USE_BIOMETRIC` is declared for biometric quick unlock.
- Android `MainActivity` uses `FlutterFragmentActivity` for `local_auth` compatibility and enables `FLAG_SECURE` for screenshot/task-preview masking.
- Android biometric unlock stores only a DEK copy, uses biometric Android secure storage options with `enforceBiometrics: true`, and still requires the app-level `local_auth` biometric-only gate before reading the DEK copy.
- Biometric unlock failure continues to fall back to the master password.

## Residual Notes

- Native Android APK build verification was attempted during Android hardening but was blocked by an external Maven Central HTTP 403 dependency download. Flutter tests, analyzer, source manifest checks, and Android integration source tests passed.
