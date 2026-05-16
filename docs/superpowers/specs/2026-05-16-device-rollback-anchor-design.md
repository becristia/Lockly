# Device Rollback Anchor and Plaintext Lifetime Design

Date: 2026-05-16

## Context

Secure Box already encrypts local vault items, uses Argon2id for new vaults and password rotation, protects biometric unlock as a DEK copy, and verifies a vault manifest on unlock, detail reads, item mutations, and backup import/export. The manifest detects item tampering, item deletion, metadata replacement, and malformed backup state.

The next security gap is whole-database rollback. If an attacker replaces the entire SQLite database with an older copy, the encrypted manifest and its counter can roll back with the database. A local-only app cannot fully prevent this without a trusted external or platform-backed monotonic state, but it can make rollback detectable on devices where platform secure storage survives.

The second area is unlocked-session hygiene. The app should reduce how long DEKs and decrypted sensitive fields remain reachable after lock, unlock failure, biometric failure, import overwrite, or navigation away from sensitive views.

## Goals

- Detect rollback of the SQLite vault manifest when platform secure storage contains a newer trusted anchor.
- Fail closed on rollback detection without revealing whether item data, metadata, or the anchor caused the failure.
- Rebuild the local anchor only after a successful trusted unlock or after creating/importing a vault.
- Keep biometric unlock as convenience only; master password remains the recovery path when the platform anchor is missing or invalid.
- Clear in-memory DEK material and transient plaintext state as soon as the vault locks or a sensitive operation fails.
- Preserve the current no-cloud, no-network, local-only model.

## Non-Goals

- Do not add cloud sync, remote attestation, remote backup, or account recovery.
- Do not make rollback detection absolute on every platform. This design improves protection where platform secure storage persists and is trusted.
- Do not store plaintext vault item fields, DEK, master password, or backup passwords in SQLite, logs, settings, or normal files.
- Do not replace the current vault manifest design.

## Approach

Add a small `VaultAnchorService` backed by platform secure storage. The anchor stores only non-secret integrity metadata:

- `vault_id`: stable identifier derived from or stored with `vault_meta`.
- `manifest_epoch`: latest accepted manifest epoch.
- `manifest_counter`: latest accepted manifest counter.
- `manifest_digest`: HMAC or SHA-256 digest over the manifest row metadata, keyed with an app/domain constant only if no DEK is available at write time, and preferably written after DEK-backed manifest verification.
- `schema_version`: anchor format version.

The anchor is not used to decrypt data. It is a local tamper-evidence checkpoint. On successful vault creation, import, unlock, item mutation, biometric state change, password rotation, and backup restore, the app updates the anchor after the manifest has been verified or rewritten. On unlock and sensitive reads, the app compares the verified SQLite manifest against the anchor. If SQLite is older than the anchor, or the digest does not match the expected accepted manifest state, the vault locks and raises a generic integrity error.

If the anchor is missing but SQLite has a valid manifest, the app treats this as a platform state reset. Master-password unlock may succeed, but biometric unlock must not silently recreate trust. The app should recreate the anchor only after master-password unlock succeeds and should disable biometric convenience state if platform secure storage indicates reset. This keeps recovery possible while avoiding biometric-only trust bootstrap.

## Components

### VaultAnchor

A model containing `vaultId`, `schemaVersion`, `manifestEpoch`, `manifestCounter`, `manifestDigest`, and `updatedAt`. It must not contain DEK bytes, encrypted DEK bytes, master password material, or item fields.

### VaultAnchorStore

An interface with `read`, `write`, and `delete`. The production implementation uses `flutter_secure_storage` with the same conservative platform handling already used by biometric storage. Tests use an in-memory fake.

### VaultAnchorService

Owns comparison and update rules:

- `verifyAgainstAnchor(vaultId, manifest)` returns success, missing anchor, or rollback/tamper failure.
- `writeAcceptedManifest(vaultId, manifest)` writes the latest accepted counter and digest.
- `deleteAnchor(vaultId)` removes anchor state when the local vault is cleared.

The service reports generic exceptions to callers. UI should show an integrity warning without exposing internal counter or digest details.

### VaultService Integration

Integrate anchor checks after manifest cryptographic verification and before marking the session unlocked. Integrate anchor updates in the same logical success paths that update the manifest:

- `createVault`
- master-password unlock
- biometric unlock, only if an anchor already exists and matches
- create, update, delete item
- enable or disable biometric unlock
- change master password
- backup import overwrite, skip, and merge paths when target data changes
- clear local vault

If an anchor write fails, the safest default is to keep the vault locked for unlock/create/import paths and fail the mutation for already-unlocked paths. This avoids accepting a state that cannot be checkpointed.

### Plaintext Lifetime Tightening

Add explicit cleanup paths where they are missing:

- `VaultSession.lock()` zeroes the active DEK buffer before dropping it.
- Temporary DEK buffers produced during failed unlock, manifest verification, biometric enable/disable, and backup import/export are zeroed in `finally` blocks where ownership is clear.
- Detail/edit UI clears password controllers and revealed-password state on `dispose`, lock notifications, and failed save where practical.
- App-level `lockVault()` remains the central clearing path for auto-lock and background lock.

## Data Flow

Unlock with master password:

1. Read vault metadata and decrypt DEK from the master password.
2. Verify the encrypted vault manifest with the DEK.
3. Read platform anchor.
4. If anchor is newer than SQLite manifest or digest mismatches, zero DEK, lock, and fail closed.
5. If anchor is missing, allow only master-password trust bootstrap and write the current verified manifest anchor.
6. Mark session unlocked.

Biometric unlock:

1. Authenticate through biometric flow and retrieve DEK copy.
2. Verify encrypted vault manifest with the DEK.
3. Require an existing matching anchor.
4. If anchor is missing or mismatched, zero DEK, lock, and fall back to master password.
5. Mark session unlocked only after anchor and manifest both verify.

Mutation:

1. Verify current manifest and anchor.
2. Apply the data change and rewrite manifest in the existing transaction.
3. After transaction success, write the accepted anchor.
4. If anchor write fails, report failure and lock. The data may already be committed, but the next master-password unlock can verify manifest and re-anchor only if policy allows; tests should document this edge.

## Error Handling

- Use generic integrity errors for rollback, digest mismatch, malformed anchor, and secure-storage read errors.
- Missing anchor is recoverable only through successful master-password unlock.
- Biometric unlock never creates a missing anchor.
- Anchor deletion during clear-vault is best-effort but should be attempted after SQLite cleanup.
- Avoid logging anchor values, manifest digests, passwords, DEKs, or decrypted item fields.

## Testing

Add focused tests for:

- Creating a vault writes an anchor after manifest creation.
- Master-password unlock succeeds when anchor matches.
- Master-password unlock rejects a database rolled back below anchor counter.
- Biometric unlock falls back to master password when anchor is missing.
- Biometric unlock rejects mismatched anchor even when the manifest itself is valid.
- Item create/update/delete updates the anchor counter after manifest rewrite.
- Clearing the local vault deletes anchor state.
- `VaultSession.lock()` zeroes DEK bytes before clearing the reference.
- Temporary DEKs are zeroed on unlock failure and manifest failure where ownership is clear.

Run full `flutter test --reporter compact` and `flutter analyze` before merging.

## Acceptance Criteria

- A whole-database rollback to an older manifest counter is detected on a device with a newer secure-storage anchor.
- Master password can recover from missing anchor state; biometric unlock cannot silently recover from missing anchor state.
- No new plaintext sensitive fields appear in SQLite, settings, logs, or backup JSON.
- DEK buffers owned by session code are zeroed on lock.
- Existing manifest integrity, backup v2, biometric fallback, clipboard cleanup, and auto-lock tests still pass.

## Self-Review

- Scope is limited to local rollback detection and memory hygiene.
- The design does not introduce cloud, network, mock crypto, or hardcoded secret keys.
- Missing-anchor behavior is explicit and separates master-password recovery from biometric convenience.
- The mutation anchor-write edge case is called out for tests and implementation policy.
