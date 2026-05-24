# Lockly Cloud Sync Client Design

## Goal

Add optional cloud sync to Lockly while preserving the local-first security model. The user account password authenticates to the backend only. The master password never leaves the device, and vault plaintext, KEK, and raw DEK never leave the client.

## Security Boundary

- Backend account login is separate from vault unlock. A successful cloud login must not unlock the local vault.
- The client uploads only encrypted vault metadata and encrypted item payloads.
- The client may upload `encrypted_dek_by_master`, its nonce, and MAC because these are a wrapped DEK encrypted locally by the master-password-derived KEK.
- The client uploads the encrypted vault manifest with vault metadata so cloud downloads can reuse the existing backup manifest verification path.
- The client must never send `master_password`, KEK, DEK plaintext, decrypted `PasswordEntry`, password history plaintext, TOTP plaintext, or local biometric DEK copies.
- Sync is available only after the local vault is unlocked, because the client needs to inspect encrypted local rows and update local metadata safely.
- Downloaded remote data is accepted only as ciphertext. Decryption remains a local operation guarded by the master password or biometric DEK copy.

## Architecture

Lockly gets a small sync layer under `lib/core/sync/`:

- `SyncApiClient`: HTTP JSON client for auth, devices, vault meta, push, and pull. It handles request/response mapping only; token refresh and retry policy belong to `SyncService`.
- `SyncCredentialStore`: stores backend access/refresh tokens and device id in secure storage.
- `SyncModels`: typed DTOs for backend requests and responses.
- `SyncStateDao`: stores the backend pull cursor as a server-time string, per-item server revisions, and encrypted remote conflict payloads. It must not store master-password material or decrypted vault fields.
- `SyncService`: orchestrates cloud account registration/login/logout, token refresh, device registration/list/revoke, vault meta upload/download, push, pull, and conflict handling.
- `VaultService` exposes encrypted export/import primitives so sync can move ciphertext without knowing vault plaintext.

Local SQLite remains the source of truth for day-to-day vault operations. Sync stores minimal per-item state locally: server revision and last synced timestamp. The first implementation can keep this state in a separate `sync_state` table keyed by item id to avoid changing encrypted item semantics.

## User Workflows

1. Cloud login: user enters backend email/password. Lockly stores returned tokens and registers the current device.
   - If an authenticated API call fails with `TOKEN_EXPIRED` or `UNAUTHORIZED`, `SyncService` refreshes once and retries the original call once.
   - Logout refreshes an expired access token once before attempting remote logout, then clears local sync credentials even if remote logout still fails.
   - Revoking the current device clears local sync tokens and the saved device id. Revoking another device leaves the current session intact.
2. Enable sync for an existing vault: after local unlock, Lockly first requires the master password and attempts to download the existing cloud vault through the encrypted backup import path. If the backend vault is not initialized yet, Lockly skips the download step. It then uploads the post-import local vault meta and encrypted rows.
3. Push: Lockly sends changed encrypted rows with the last known server revision. Soft-deleted rows are sent as `deleted=true`.
4. Pull: Lockly requests updates since the last pull time and records server revisions locally. Full cloud downloads request from the initial cursor and assemble a version 2 encrypted backup package. Ordinary UI sync must not treat a pull as an import by itself; it asks for the master password and reuses backup manifest verification before local vault rows change.
   - The first pull uses `1970-01-01T00:00:00.000Z`; successful pulls persist the backend `server_time` cursor.
5. Conflict: backend `409` conflicts are shown as unresolved sync issues. Lockly does not overwrite either side automatically.
6. Download/recovery: after cloud login on a new device, Lockly downloads vault meta, encrypted manifest, and ciphertext. The user must enter the master password so the existing backup import path can unwrap the DEK and verify the manifest before the vault becomes usable.

## Backend Expectations

The existing backend API is mostly aligned:

- `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`, `GET /auth/me`
- `POST /devices/register`, `GET /devices`, `DELETE /devices/{device_id}`
- `POST /vault/init`, `GET /vault/meta`, `PUT /vault/meta`
- `POST /sync/push`, `GET /sync/pull?since=...`

One compatibility decision is required on the client: backend `vault.encrypted_dek_by_master` is one string, while Lockly stores ciphertext, nonce, and MAC separately. Lockly will encode a JSON envelope as the backend field:

```json
{
  "ciphertext": "base64",
  "nonce": "base64",
  "mac": "base64"
}
```

Encrypted item sync follows the same pattern: backend has `ciphertext`, `nonce`, and optional `aad`; Lockly will put the local item MAC in `aad` as a JSON envelope:

```json
{
  "mac": "base64",
  "schema": "lockly-item-v1"
}
```

Vault metadata also carries `manifest`, a JSON object containing only the encrypted manifest row fields (`version`, `epoch`, `counter`, `nonce`, `ciphertext`, `mac`, `updated_at`). Biometric DEK fields are deliberately omitted from cloud metadata and cloud backup assembly.

## UI Scope

Add a settings section named cloud sync. It should include:

- account login/register/logout;
- current device registration and revocation status;
- manual sync button;
- last sync time;
- unresolved conflict count;
- download cloud vault action for a new/local-empty device.

The UI must keep security text explicit but operational: cloud account login is not vault unlock, and master password is required for downloaded vaults.

## Testing

Frontend tests should cover:

- sync DTO serialization does not contain forbidden key names;
- token store persists and clears credentials;
- API client attaches bearer tokens and preserves backend conflict responses;
- `SyncService` refreshes expired tokens when needed before retrying one authenticated request;
- sync service uploads only encrypted local rows;
- downloaded vault requires master-password validation before unlock;
- conflict responses are retained instead of auto-overwriting local data.

Integration verification should run:

```powershell
flutter test --reporter compact
flutter analyze
```
