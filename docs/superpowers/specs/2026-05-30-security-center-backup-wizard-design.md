# Security Center And Backup Wizard Design

## Goal

Make Security Center a first-class unlocked workflow and replace one-shot backup export with a guided local export flow.

## Scope

- Add Security Center as a primary vault shell tab on mobile and desktop.
- Keep Settings for preferences and safety switches, but expose local backup and migration actions from Security Center.
- Add an encrypted backup export wizard that reauthenticates locally, prepares the encrypted JSON without rendering it, shows verified backup metadata, and copies only after explicit confirmation.
- Keep the existing migration wizard path for Lockly JSON and CSV imports, with plaintext CSV still cleared after preview or failure.

## Security Boundaries

- Master password is never stored or synced.
- Backup export uses the master password only for local reauthentication.
- Exported backup remains encrypted and is never rendered in full on screen.
- CSV import remains local-only; plaintext source text is cleared after preview/failure and is not persisted.
- No backend/cloud flow is introduced by this slice.

## UX Shape

- Vault shell tabs become: Vault, Security, TOTP, Generator, Settings.
- Security Center shows local health plus a "Local backup and transfer" action group:
  - Export encrypted backup
  - Migration import
  - LAN send
  - LAN receive
- Backup export wizard has two visible states:
  - Prepare: enter master password, confirm local-only encrypted export.
  - Ready: show item/history/attachment counts and backup size; allow copy and clear clipboard.

## Testing

- Widget test confirms the unlocked shell exposes and opens the Security tab.
- Widget test confirms Security Center can open backup export and migration flows.
- Widget test confirms backup export wizard hides full JSON, shows backup metadata, and copies only after confirmation.
- Existing migration tests continue to verify CSV secret redaction and Lockly JSON import path.
