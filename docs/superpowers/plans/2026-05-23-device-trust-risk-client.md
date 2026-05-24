# Device Trust And Risk Client Plan

> For agentic workers: implement after or alongside the backend device metadata contract. Keep changes scoped to `Lockly` and do not revert unrelated dirty files.

## Goal

Show a useful device trust posture in Lockly without mixing backend account trust with vault unlock or key derivation.

## Contract

Backend device payloads can include:

- `id`
- `device_name`
- `device_type`
- `platform`
- `client_version`
- `trusted`
- `last_sync_at`
- `last_ip_address`
- `last_user_agent`
- `created_at`
- `revoked_at`

`PATCH /devices/{device_id}` accepts `device_name` and returns the updated device.

## Client Changes

- Extend `SyncDevice` with nullable `platform`, `clientVersion`, `lastIpAddress`, and `lastUserAgent`.
- Extend `SyncApiClient.registerDevice()` with optional `platform` and `clientVersion`.
- Add `SyncApiClient.renameDevice()` and a matching `SyncService` / `AppServices` facade if the UI needs it.
- Keep `device_public_key` out of user-facing DTOs unless a later protocol exposes a public-key fingerprint.
- Security Center device card summarizes active/trusted/revoked devices and flags missing metadata or stale sync as risk indicators.
- Settings device list can show platform/client version/last sync metadata and later attach rename controls.

## Security Rules

- Device metadata is account operational metadata only.
- Device metadata must not unlock the vault, derive a key, wrap a key, or change the local master-password flow.
- Do not display sync conflict remote payloads, vault ciphertext, usernames, passwords, notes, TOTP secrets, or attachment/passkey material in device trust UI.

## Tests

- DTO tests parse optional device metadata and remain backward-compatible when fields are absent.
- API client tests assert register sends bounded platform/client version when provided and rename uses `PATCH /devices/{id}`.
- Security Center tests assert revoked/untrusted/missing-metadata devices change the risk summary without plaintext/ciphertext exposure.
- Existing sync tests continue to pass.

