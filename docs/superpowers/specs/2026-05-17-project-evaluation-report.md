# Secure Box Project Evaluation Report

**Date:** 2026-05-17

## Executive Summary

Secure Box is no longer a toy password notebook. The security backbone is stronger than a typical MVP: Argon2id, AES-256-GCM, KEK/DEK layering, per-record nonce, biometric fallback semantics, manifest integrity, rollback anchor, auto-lock, clipboard cleanup, and master password policy are all present.

The main weakness is product maturity. The project currently feels like a secure engineering sample rather than a daily-use password manager. The cryptographic path is serious, but the user-facing security posture is under-explained, the UI is functional but plain, and practical workflows such as password health, generator presets, and backup usability are still thin.

## Scores

- Logic completeness: 8/10
- Security posture: 8.5/10
- Visual polish: 6/10
- Practical usability: 6.5/10
- MVP completeness: 8/10
- Long-term product potential: 7/10

## Logic Review

The application has a coherent local-first flow:

- First-run master password setup.
- Master password unlock and biometric fast unlock.
- Encrypted vault item CRUD.
- Password generator to save flow.
- Settings for biometric, auto-lock, clipboard cleanup, backup import/export, clear local vault.
- Manifest and rollback-anchor checks around critical mutations.

The codebase is also reasonably decomposed:

- `lib/core/crypto/` owns crypto and KDF behavior.
- `lib/core/vault/` owns vault semantics and integrity checks.
- `lib/core/backup/` owns backup import/export.
- `lib/core/security/` owns lifecycle, auto-lock, and master password policy.
- `lib/features/*` owns screens.

Sharp critique:

- Search decrypts every active item and filters in memory. This respects the "no plaintext index" constraint, but it will degrade as item count grows. A future secure in-memory index or unlocked-session cache will be needed.
- User-facing error categories are too coarse. Wrong master password, corrupted data, rollback detection, backup format errors, and biometric failure should not all feel like "try again later."
- The feature flow is complete, but not optimized. A user can accomplish tasks, but the interface does not yet reduce repeated friction for common actions.

## UI And Visual Review

The UI is clean and appropriately restrained for a security utility. The blue/green trust palette is reasonable, and the project avoids playful or decorative patterns that would weaken perceived security.

Sharp critique:

- The app still looks close to default Flutter Material. Cards, settings rows, detail rows, and form pages are functional but not distinctive.
- There is no dark mode, which makes the app feel less mature for a password manager.
- Security state is not visible enough. Users should see when the vault is locked, when a backup is verified, when a password is weak/reused, and when clipboard cleanup is pending.
- `SecureScaffold` is used on setup/generator/settings, while list/detail/edit use raw `Scaffold`. This creates subtle visual inconsistency.
- The generator screen is a form, not yet a tool. It lacks strength explanation, presets, copy-first behavior, and a stronger visual hierarchy for the generated secret.

## Security Review

Strong decisions:

- The master password is not stored.
- KEK/DEK layering is correct.
- Master password rotation rewraps DEK instead of re-encrypting all items.
- New and rotated vaults use Argon2id.
- AES-256-GCM is used with generated nonces.
- Biometric unlock does not replace the master password.
- The app clears pending password clipboard data on timeout/background.
- Manifest and rollback anchor checks defend against a meaningful local rollback class.
- Master password strength now rejects common weak patterns.

Residual risks:

- Decrypted item fields become Dart `String` values and `TextEditingController` text. These cannot be reliably zeroed. The app should minimize how long they stay referenced.
- Backup export UX is raw. Showing JSON to the user works for an MVP but encourages unsafe copy/paste habits.
- The app has no password health checks, so it cannot warn about repeated, weak, stale, or site-similar passwords.
- Unlock throttling exists, but the user experience around lockout/cooldown could be clearer.
- Integrity failures need a distinct, high-severity UI. Silent generic failure is not enough for a security product.

## Practical Usability Review

The app is usable for a small personal vault. It becomes less ergonomic as the number of records grows.

Missing or underdeveloped practical features:

- Local password health report.
- Reused password detection.
- Password age tracking and stale password warnings.
- Generator presets for default strong password, readable passphrase, and website-compatible password.
- Generated password copy action.
- More prominent one-tap copy actions in list/detail.
- Better backup import/export flow with file picker/share-sheet and verification result.
- Favorites, recently used items, sorting, and grouping.

## Priority Recommendation

Do not spend the next iteration swapping crypto algorithms. The core cryptographic design is already strong for this stage.

The next iteration should convert security capability into user-visible, daily-use product value:

1. Add local password health checks.
2. Harden sensitive plaintext lifecycle across detail, edit, generator, clipboard, and lock transitions.
3. Productize the password generator with presets, passphrases, strength explanations, and safer generated secret handling.

