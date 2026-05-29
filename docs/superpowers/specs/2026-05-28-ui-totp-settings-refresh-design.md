# Lockly UI, TOTP, and Settings Refresh Design

## Goal

Refresh Lockly so the app feels lighter and less oppressive, remove the redundant Security tab from primary navigation, support standalone MFA/TOTP entries from the TOTP page, align settings card widths, improve dialog styling, and preserve the existing master-password and encrypted-vault security model.

## Security Decisions

- The master password remains local-only and is never synced.
- Standalone MFA secrets are not stored in settings or plaintext preferences.
- Standalone MFA entries are saved as encrypted vault items with an `isStandaloneTotp` marker inside the encrypted payload. Legacy `standaloneTotp` is accepted on read.
- Password vault listing and password health analysis skip standalone TOTP entries so they do not look like empty-password records.
- TOTP listing includes both password-linked TOTP entries and standalone TOTP entries.
- Backup and LAN transfer continue to operate on encrypted vault records. Standalone MFA entries are selectable in LAN send, but no plaintext TOTP secret is added to QR payloads, logs, settings, or UI previews.

## UI Direction

- Keep the existing Flutter Material 3 stack and icon system.
- Lighten the global palette: brighter background, softer surfaces, more cyan/green accents, and higher contrast text.
- Keep card radius at or below the app's current constrained radius rules.
- Add decorative but non-animated header chips/marks to the TOTP page.
- Improve global `AlertDialog`/dialog surfaces through `dialogTheme`, while preserving existing sensitive prompt behavior.

## Navigation

- Remove the Security tab from `VaultShellPage`.
- Keep password health, tags, LAN exchange, backup, and danger workflows reachable from Settings.
- Keep existing security-center code only if it remains harmless and unreferenced; the user-facing page is optimized away by navigation removal.

## TOTP

- TOTP page gains a top header with two action buttons:
  - Scan QR code
  - Enter manually
- Manual entry asks for display title, optional account, and Base32 secret or otpauth URL.
- Scan flow accepts a QR payload, extracts `otpauth://` data, and reuses the same save path.
- Saved standalone TOTP entries are encrypted through `AppServices.createVaultItem`.
- TOTP cards show whether an entry is vault-linked or standalone MFA.
- Standalone TOTP cards can be edited or deleted from the TOTP page, while standalone entries remain hidden from the normal password list and password-health scoring.
- Standalone TOTP edit does not prefill or preview the saved secret. Leaving the secret field empty keeps the existing encrypted secret; entering a new valid secret replaces it.
- The TOTP parser normalizes Base32 secrets, accepts supported `otpauth://totp` payloads, and rejects unsupported algorithms, digit counts, or periods instead of silently saving an entry the app cannot generate correctly.

## Settings

- Settings content stretches sections to one consistent width.
- Language and theme segmented controls fill their card width.
- Add missing vertical spacing before the LAN exchange section.
- After a LAN send session is created, auto-lock is temporarily extended to at least 5 minutes. Existing values above 5 minutes are preserved, and stricter values are restored after successful cancel, expiry, or page cleanup.
- Saving dialogs for master password changes and attachment creation use `barrierDismissible: false`, disabled cancel buttons, and `PopScope(canPop: !_isSaving)` so route dismissal cannot bypass the busy state.

## Verification

- Add/adjust widget and unit tests before implementation.
- Static verification uses `flutter analyze`.
- Widget tests were added/updated for TOTP, settings/LAN, visual system, routing, and vault item behavior.
- Native asset execution is unblocked by the supplied local Windows assets and the local `build/windows/x64/_deps/nuget-src/nuget.exe`.
- `flutter build windows --release` passes with that NuGet directory prepended to `PATH` for the build process, and the generated `Lockly.exe` passes a startup smoke test.
- Android compatibility is verified by `flutter test test/android_integration_test.dart -r compact` and `flutter build apk --debug`.
- `rg -n "AlertDialog\(" lib` has no output.
- Installer script configuration is statically verified, and `windows/installer/install_smoke.ps1` provides a reproducible compile/install/launch/uninstall smoke path that installs only into `build/windows/install-smoke/Lockly`.
- Actual Inno Setup package generation and install/uninstall execution passes with Inno Setup 6.7.3 via `powershell -ExecutionPolicy Bypass -File windows\installer\install_smoke.ps1 -IsccPath 'C:\Users\office\AppData\Local\Programs\Inno Setup 6\ISCC.exe'`.
- Code-review subagents reviewed the implementation and follow-up fixes; the final review reported no warning-or-higher issues.
