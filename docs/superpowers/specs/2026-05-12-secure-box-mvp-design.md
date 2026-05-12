# Secure Box MVP Design

Date: 2026-05-12

## Scope

Secure Box is an Android-first Flutter MVP for local password management. It stores all vault data locally in SQLite and encrypts sensitive item fields before persistence. The MVP excludes cloud sync, remote storage, browser extensions, team sharing, plaintext search indexes, and master-password recovery.

The approved implementation approach is a layered local vault:

- Flutter UI for setup, unlock, vault list, detail, edit, generator, and settings pages.
- Core services for vault operations, session state, biometric unlock, clipboard cleanup, and auto-lock behavior.
- SQLite repositories and DAOs for local persistence.
- Real cryptography for vault metadata and item encryption. No mock encryption is allowed.

Android is the target platform for MVP validation. Desktop support may be useful for development, but desktop biometric behavior is not part of MVP acceptance.

## Security Model

The vault uses this key hierarchy:

```text
Master password
  -> KDF
KEK
  -> decrypts
DEK
  -> encrypts and decrypts
Vault item JSON
```

The master password is never stored. A random DEK is generated when the vault is created. The KEK is derived from the master password and a random salt, then used only to encrypt or decrypt the DEK. Changing the master password re-encrypts the DEK with a new KEK and salt; it does not re-encrypt every vault item.

For the MVP, PBKDF2-HMAC-SHA256 is acceptable if Argon2id is not practical in the first implementation pass. The crypto layer should isolate KDF choice so a future Argon2id migration can replace or supplement PBKDF2 without rewriting vault features.

Item encryption uses AES-256-GCM. Every vault item stores an independent nonce and ciphertext. The item plaintext is serialized as one JSON object and encrypted as a whole, including title, website, username, password, notes, and tags. SQLite must not contain plaintext sensitive fields.

Plaintext exists only briefly in memory after unlock and while rendering or editing an item. Logs must not include master passwords, generated passwords, DEKs, KEKs, item plaintext, or decrypted backup contents.

## Biometric Unlock

Biometric unlock cannot replace the master password. The user must first unlock with the master password. If the user enables biometric unlock, the app stores a protected encrypted copy of the DEK using Android secure platform facilities through Flutter biometric/secure storage plugins.

The biometric flow is:

```text
Master password unlock succeeds
  -> user enables biometric unlock
  -> app stores a protected encrypted DEK copy
  -> subsequent biometric auth decrypts that DEK copy
  -> app opens the in-memory vault session
```

If biometric authentication fails, secure storage becomes unavailable, the app is reinstalled, or the Android secure area changes, the user must fall back to master-password unlock. Disabling biometric unlock deletes the biometric DEK copy and updates vault metadata.

## Data Storage

SQLite contains at least these tables:

- `vault_meta`: vault version, KDF name, KDF parameters, salt, encrypted DEK by master password, optional encrypted DEK by biometric, biometric enabled flag, created and updated timestamps.
- `vault_items`: item id, nonce, ciphertext, created and updated timestamps, optional deleted timestamp.
- `settings`: local settings such as auto-lock timeout and clipboard cleanup timeout.

No separate plaintext columns are created for title, website, username, password, notes, or tags. Search is performed only after the vault is unlocked and items are decrypted in memory. The MVP must not create a plaintext search index.

## Architecture

Recommended directory structure:

```text
lib/
  core/
    crypto/
    vault/
    biometric/
    clipboard/
    security/
  data/
    db/
    models/
  features/
    setup/
    unlock/
    vault_list/
    vault_detail/
    vault_edit/
    password_generator/
    settings/
  shared/
    widgets/
    utils/
```

Core responsibilities:

- `core/crypto`: secure random bytes, KDF parameters, AES-GCM encrypt/decrypt helpers, encoding helpers.
- `core/vault`: vault initialization, unlock, master password rotation, item encryption/decryption orchestration, session state.
- `core/biometric`: biometric availability, authentication, enable/disable behavior, fallback signaling.
- `core/clipboard`: copy operations and scheduled cleanup.
- `core/security`: app lifecycle guard, inactivity timer, sensitive preview masking, lock behavior.
- `data/db`: SQLite schema, migrations, DAOs.
- `data/models`: encrypted database records and decrypted domain models.
- `features/*`: page-level state and widgets. Feature pages call services; they do not own crypto logic.

## User Interface

The UI direction is a restrained Android-first security utility. It uses Chinese primary copy, compact mobile-first forms and lists, clear feedback for copy/save/delete actions, and visible warnings for irreversible operations.

The `ui-ux-pro-max` design system search recommended a security blue and protected green palette with clean Inter/system typography. The MVP should use this guidance conservatively:

- Primary blue: `#0369A1`
- Secondary blue: `#0EA5E9`
- Protected/success green: `#22C55E`
- Light background: `#F0F9FF`
- Primary text: `#0C4A6E`

Avoid playful styling, decorative gradients, emoji icons, and large marketing-style screens. Use normal controls for a productivity/security tool: forms for setup and edit pages, list rows for vault items, toggles for settings, segmented controls or chips for generator length, and icon buttons for copy, show/hide, edit, and delete.

Pages:

- Setup: create and confirm master password, show strength, warn that the master password cannot be recovered, optional biometric enablement after vault creation.
- Unlock: master-password unlock, biometric unlock when enabled, error feedback, increasing delay after repeated failures.
- Vault list: search unlocked items in memory, add item, open generator, open detail. Do not show passwords.
- Detail: show decrypted item fields after unlock, hide password by default, support copy username, copy password, edit, and delete.
- Edit: create and update title, website, username, password, notes, and tags. Accept generated password handoff.
- Generator: length options, character class toggles, exclude confusing characters, guarantee at least one selected class when enabled, generate multiple candidates, copy candidate, save candidate into edit page.
- Settings: change master password, enable/disable biometric unlock, auto-lock timeout, clipboard cleanup timeout, encrypted backup export/import, clear local vault with confirmation.

## App Security Behavior

The app locks when it enters the background and when the inactivity timer expires. The unlocked session should not be retained longer than necessary. Task-switcher previews should hide sensitive content.

Copying a password schedules clipboard cleanup. The default cleanup time is 30 seconds. Username copy may provide feedback but password copy is the required cleanup path. If the clipboard content has changed before the timer fires, cleanup should avoid overwriting newer user content when feasible.

Dangerous actions require confirmation:

- Delete item.
- Clear vault.
- Disable biometric unlock.
- Import backup with overwrite or merge effects.
- Change master password.

## Backup

The MVP supports encrypted local backup export and import. Export writes vault metadata and encrypted item records; it does not decrypt and reserialize plaintext item data.

Backup format:

```json
{
  "version": 1,
  "kdf": "pbkdf2-hmac-sha256",
  "kdf_params": {},
  "salt": "...",
  "encrypted_dek_by_master": "...",
  "items": [
    {
      "id": "...",
      "nonce": "...",
      "ciphertext": "..."
    }
  ]
}
```

Import validates file structure and version, asks for the master password, proves the DEK can be decrypted, then imports records. Duplicate handling for MVP should offer clear choices: overwrite, skip, or merge.

## Error Handling

Unlock failures show a generic wrong-password message and never expose crypto details. Repeated failures increase waiting time.

Corrupt vault metadata, unsupported backup versions, invalid backup JSON, failed biometric authentication, and missing secure-storage entries should all produce recoverable user-facing states. The user must always be able to return to master-password unlock unless the local vault itself is missing or corrupted.

## Testing

Tests prioritize security invariants and critical app behavior.

Crypto tests:

- Correct master password decrypts DEK.
- Wrong master password cannot decrypt DEK.
- Same plaintext encrypted multiple times yields different ciphertext.
- Every item nonce is unique across generated records.
- Master password rotation invalidates the old password and accepts the new password.

Vault and database tests:

- Create, read, update, and delete item flows work.
- Decrypted data matches saved input.
- SQLite storage does not contain plaintext password, username, notes, or other sensitive item fields.
- Backup export does not include plaintext item data.
- Backup import validates format and requires successful decrypt before import.

Generator tests:

- Generated password length is exact.
- Lowercase, uppercase, number, and symbol toggles are honored.
- Excluding confusing characters removes `O`, `o`, `1`, `l`, and `I`.
- Guarantee-each-selected-class mode includes at least one character from every enabled class.

Behavior tests:

- Clipboard cleanup clears copied passwords after the configured timeout.
- Biometric success can unlock the DEK when enabled.
- Biometric failure falls back to master-password unlock.
- Disabling biometric unlock removes the biometric DEK copy.
- Auto-lock triggers on background and inactivity timeout.

## Acceptance Criteria

The MVP is accepted when:

- A fresh Android app can create a master password and initialize a vault.
- Closing or backgrounding the app requires unlocking again.
- The user can unlock with the master password.
- The user can create, view, edit, delete, search, and copy vault entries.
- Passwords are hidden by default and shown only after user action.
- SQLite inspection does not reveal plaintext sensitive fields.
- The password generator can generate passwords and hand a selected result to the save flow.
- The user can change the master password without re-encrypting every item.
- Biometric unlock can be enabled and disabled, and never becomes the only unlock path.
- Password copy schedules clipboard cleanup.
- Encrypted backup export/import exists.
- The required unit and behavior tests pass.
