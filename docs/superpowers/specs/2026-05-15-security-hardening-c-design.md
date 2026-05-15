# Security Hardening C Design

Date: 2026-05-15

## Goal

Strengthen the existing local password manager without expanding MVP scope by making Argon2id the default KDF for new and rotated vaults, preserving PBKDF2 compatibility for existing vaults, and hardening Android biometric DEK storage so biometric unlock remains a convenience path with master-password fallback.

## Scope

In scope:

- Add Argon2id support to the KDF layer.
- Use Argon2id for newly created vaults.
- Keep PBKDF2-HMAC-SHA256 vaults unlockable.
- Migrate PBKDF2 vaults to Argon2id when the user successfully changes the master password.
- Harden Android biometric secure storage options so the DEK copy is protected by Android biometric authentication where the platform supports it.
- Add tests for KDF dispatch, vault creation, password rotation migration, biometric storage options, and fallback behavior.
- Update security documentation to describe the new KDF and biometric storage posture.

Out of scope for this iteration:

- Automatic KDF migration during ordinary unlock.
- Cloud sync, remote backup, sharing, or browser integration.
- Database rollback/tamper detection.
- Backup file magic/version redesign.
- Password strength entropy UI.
- Native-device manual testing automation.

## KDF Design

`KdfParams` will support two named algorithms:

- `pbkdf2-hmac-sha256`
- `argon2id`

PBKDF2 remains supported for existing vault metadata. It keeps the current validation floor of at least 100,000 iterations, 256-bit output, and a 16-byte minimum salt.

Argon2id becomes the default for new vault metadata. The default parameters will be conservative enough for mobile MVP use while still clearly stronger than PBKDF2 against GPU attacks:

- memory: 64 MiB
- iterations: 3
- parallelism: 1
- output: 256 bits
- salt: existing 16-byte random salt minimum

The implementation will derive a 32-byte KEK from the master password and stored salt. `vault_meta.kdf` and `vault_meta.kdf_params` continue to be the source of truth for unlock. This keeps old vaults readable and allows future parameter upgrades without schema churn.

If the chosen Dart Argon2id dependency is unavailable or unsuitable during implementation, the implementation must stop and report the blocker rather than silently falling back to PBKDF2 for new vaults. PBKDF2 fallback is only for already-existing metadata that explicitly says `pbkdf2-hmac-sha256`.

## Vault Migration Design

New vault creation:

- `VaultService.createVault()` generates the DEK as today.
- It derives the KEK with default Argon2id params.
- It encrypts the DEK with AES-256-GCM as today.
- It stores `vault_meta.kdf = "argon2id"` and matching Argon2id JSON parameters.

Existing PBKDF2 unlock:

- `VaultService.unlock()` reads metadata and derives the KEK with the stored KDF params.
- PBKDF2 vaults unlock normally.
- Ordinary unlock does not rewrite metadata, avoiding extra write risk on the most common authentication path.

Master password change:

- `VaultService.changeMasterPassword()` first validates the old password using the stored KDF.
- It derives the new KEK with default Argon2id params.
- It re-encrypts only the DEK, not every vault item.
- It writes updated metadata with Argon2id params.
- The old master password must fail after rotation and the new password must unlock existing items.

Backups:

- Export continues to include whatever KDF metadata the vault currently uses.
- Import continues to verify and restore/re-encrypt using the source metadata.
- Imported PBKDF2 backups remain readable. They migrate only when the user changes the master password after import.

## Biometric Storage Design

Biometric unlock continues to follow the existing security rule:

```text
master password unlock
  -> enable biometric
  -> store a system-protected DEK copy
  -> biometric unlock reads that DEK copy
  -> failure falls back to master password
```

The Android-backed `SecureStorageDekStore` will use biometric Android storage options from `flutter_secure_storage` instead of generic storage options. The intended properties are:

- stored DEK copy is protected by Android Keystore-backed storage;
- read access requires biometric authentication where supported;
- biometric enrollment changes or unavailable secure hardware cause read failure or unavailability;
- failures never unlock the vault and are reported as fallback-to-master-password;
- disabling biometric deletes the stored DEK copy before the database flag is cleared.

The service will keep the existing `SecureDekReadRequirement` abstraction because some secure-storage configurations can manage authentication during `readDek()`, while fakes and explicit-auth configurations remain useful in tests. Production Android should prefer store-managed biometric protection if the package supports it reliably.

If platform support cannot be verified from the package API, implementation must preserve the existing explicit `local_auth.authenticate()` gate and add tests/documentation showing that the storage options are the strongest available in the installed package version.

## Error Handling

- Unsupported KDF names throw a non-sensitive exception.
- Invalid KDF parameters throw non-sensitive validation errors.
- Argon2id dependency failures must not be swallowed during vault creation or password rotation.
- Biometric read/write/delete failures must not expose DEK bytes, master passwords, or item plaintext.
- Biometric unlock failure returns fallback-to-master-password.
- Master password rotation must remain transactional: failed biometric cleanup or failed metadata persistence must not leave the vault in a half-rotated state.

## Tests

Add or update tests to prove:

- Argon2id derives a deterministic 32-byte key for fixed password, salt, and params.
- Invalid Argon2id params are rejected.
- New vault metadata uses `argon2id`.
- PBKDF2 fixture vaults still unlock.
- Changing a PBKDF2 vault's master password migrates metadata to `argon2id`.
- Password rotation still preserves item readability and invalidates the old password.
- Biometric secure storage is configured with biometric Android options.
- Biometric store/auth failures fall back to master password.
- Security scans still find no MD5, SHA1, direct SHA256 master-password hashing, sensitive logging, or plaintext vault item columns.

## Documentation

Update `docs/security-check.md` after implementation to reflect:

- Argon2id is the default KDF for new and rotated vaults.
- PBKDF2-HMAC-SHA256 is retained only for compatibility with existing vault metadata.
- Android biometric unlock stores only a DEK copy and must fall back to the master password on failure.

## Acceptance Criteria

- Existing tests pass.
- New KDF and biometric tests pass.
- `flutter analyze` reports no issues.
- New vaults use Argon2id metadata.
- Existing PBKDF2 vaults remain unlockable.
- Master password rotation migrates PBKDF2 metadata to Argon2id without re-encrypting every item.
- Biometric unlock cannot become the only unlock method.
- No network permission, cloud sync, fake crypto, hardcoded key, sensitive logging, or plaintext vault item storage is introduced.
