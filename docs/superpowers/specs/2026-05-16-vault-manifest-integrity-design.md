# Vault Manifest Integrity Design

Date: 2026-05-16

## Goal

Add local tamper and rollback detection for the password vault and encrypted backups without expanding Secure Box beyond a local-first MVP.

The feature protects against an attacker who can edit, delete, or replace local SQLite rows or backup JSON files but cannot decrypt the DEK. It does not claim to defeat full-device compromise while the vault is unlocked, malware with process memory access, or a user intentionally importing an older valid backup.

## Recommended Approach

Use a vault-level encrypted manifest authenticated with a key derived from the DEK.

Two alternatives were considered:

- Per-row sequence numbers only: simple, but it does not reliably detect whole-database rollback or silent item deletion.
- Backup-only checksums: useful for file corruption, but it leaves the live SQLite vault without a clear integrity boundary.
- Vault-level manifest: covers live storage and backups with one design, gives explicit failure behavior, and fits the current local-only architecture.

The vault-level manifest is the recommended approach.

## Manifest Model

Add a `vault_manifest` table with one singleton row:

- `singleton_key`: fixed singleton guard.
- `version`: manifest format version, initially `1`.
- `epoch`: monotonic integer changed whenever the vault encryption envelope is replaced, such as overwrite import or vault recreation.
- `counter`: monotonic integer incremented on every manifest-protected data mutation.
- `nonce`: base64 nonce used to encrypt the manifest payload.
- `ciphertext`: base64 encrypted manifest payload.
- `mac`: base64 AEAD authentication tag.
- `updated_at`: local timestamp for display/debugging only, not trusted for security decisions.

The encrypted manifest payload contains non-sensitive structural state:

```json
{
  "version": 1,
  "vault_id": "uuid",
  "epoch": 1,
  "counter": 42,
  "kdf": "argon2id",
  "kdf_params_digest": "base64url",
  "encrypted_dek_digest": "base64url",
  "active_item_count": 12,
  "deleted_item_count": 3,
  "items_digest": "base64url"
}
```

`items_digest` is computed over canonical item descriptors sorted by item id. Each descriptor includes item id, nonce, ciphertext, mac, created_at, updated_at, and deleted_at. It does not decrypt or include plaintext item fields.

`kdf_params_digest` and `encrypted_dek_digest` bind the manifest to the current vault metadata without storing secrets in plaintext.

## Key Derivation

Derive a manifest key from the unlocked DEK:

```text
DEK -> HKDF-SHA256(info: "secure-box:vault-manifest:v1") -> 256-bit manifest key
```

The manifest key is used only for manifest encryption/authentication. It must not replace the existing DEK usage for item encryption.

If the existing crypto dependency does not expose HKDF cleanly, add a small `KeyDerivationService` wrapper around a well-reviewed package API. Do not hand-roll HKDF.

## Data Flow

Vault creation:

- Create `vault_meta` as today.
- Create an empty manifest in the same transaction.
- Initial `epoch = 1`, `counter = 1`.

Unlock:

- Decrypt the DEK using the master password or biometric path.
- Load and verify the manifest before returning an unlocked session.
- If the manifest is missing on an old schema, perform a legacy upgrade after successful master-password unlock.
- If the manifest is present but invalid, lock the session and throw a non-sensitive integrity exception.

Item add/edit/delete:

- Complete the item mutation and manifest rewrite in one repository transaction.
- Recompute the manifest from the transaction view of `vault_meta` and `vault_items`.
- Increment `counter` exactly once per logical mutation.

Master password change:

- Re-encrypt only the DEK as today.
- Update the manifest in the same transaction so metadata digests match the new encrypted DEK envelope.
- Increment `counter`; keep `epoch`.

Overwrite import:

- Replace metadata and items.
- Replace manifest using the imported backup manifest when valid, or generate a new manifest if importing a legacy backup after successful password verification.
- Preserve the source manifest `epoch` when importing a version 2 backup with the same encrypted DEK envelope.
- Start a fresh local `epoch = 1` when importing a legacy version 1 backup because it has no authenticated manifest state.

Skip/merge import:

- Verify the source backup manifest when present.
- Re-encrypt imported items when needed as today.
- Recompute the target vault manifest after inserted or merged items.
- Increment the target counter once per import operation, not once per row.

## Backup Format

Introduce backup version `2` while keeping version `1` import support.

Version 2 adds:

- `magic`: `"secure-box-backup"`.
- `manifest`: encrypted manifest row fields.
- `created_at`: backup export timestamp.
- `item_count`: active item count copied from export state.

Export:

- Verify the live manifest before export.
- Export metadata, active items, and manifest together.
- Fail export if the live manifest does not verify.

Import:

- Version 2 backups must verify their manifest before writing anything.
- Version 1 backups remain supported as legacy backups after master-password verification.
- Legacy imports generate a new target manifest after import.
- Corrupt, truncated, mismatched, or unsupported backup payloads must fail with `BackupFormatException` or a non-sensitive integrity exception.

## Error Handling

Add a `VaultIntegrityException` with generic messages such as:

- `Vault integrity check failed`
- `Vault manifest is missing`
- `Backup integrity check failed`

Do not report which digest mismatched in UI-facing errors. Detailed mismatch values must not be logged.

On any integrity failure:

- Lock the in-memory session.
- Do not return decrypted items.
- Do not attempt automatic repair.
- Allow the user to retry with another database or backup file.

Legacy upgrade is the only automatic write path and only after successful master-password unlock of a vault that has no manifest.

## Compatibility

SQLite schema version increases from `1` to `2`.

Migration from version 1:

- Create `vault_manifest`.
- Do not fabricate a manifest during raw schema migration because the DEK is not available.
- Mark the vault as requiring manifest initialization.
- On the next successful master-password unlock, create and verify the manifest.

Biometric unlock of a legacy vault without a manifest must fail closed and require master-password unlock once, because the upgrade needs a high-confidence recovery path.

## Testing

Add tests for:

- New vault creates a valid manifest.
- Correct master password unlock verifies manifest.
- Tampering with `vault_items.ciphertext` fails unlock/listing.
- Deleting an item row directly fails manifest verification.
- Replacing `vault_meta` encrypted DEK fields fails manifest verification.
- Add/edit/delete rewrites manifest and increments counter.
- Master password change rewrites manifest and old password still fails.
- Schema version 1 vault upgrades manifest only after successful master-password unlock.
- Biometric unlock of legacy no-manifest vault falls back to master password.
- Backup v2 export includes magic, item count, and manifest.
- Backup v2 import rejects manifest mismatch before writes.
- Backup v1 import still works and generates a target manifest.

## Acceptance Criteria

- Live vault storage detects item tampering, item deletion, and metadata envelope replacement.
- Version 2 backups detect corruption or mismatch before import.
- Version 1 backups remain importable.
- No plaintext username, password, notes, title, or master password is added to SQLite or backup metadata.
- All integrity failures produce non-sensitive errors and leave the vault locked.
- Full `flutter test` and `flutter analyze` pass.
