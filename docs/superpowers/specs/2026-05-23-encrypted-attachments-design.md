# Encrypted Attachments Design

## Context

Lockly already has a zero-knowledge item sync boundary: local vault rows are encrypted before persistence and cloud sync only transmits `ciphertext`, `nonce`, `aad`, revisions, deletion state, and timestamps. The backend rejects obvious plaintext/key-material field names and does not decrypt vault item ciphertext.

Encrypted attachments should extend that model without weakening it. The backend must never receive a master password, vault key, derived attachment key, plaintext filename, plaintext MIME type, plaintext file bytes, plaintext hash, TOTP secret, passkey private material, or decrypted note/password data.

## Chosen Approach

Use a separate encrypted blob resource for attachments.

Alternatives considered:

- Embed attachment bytes inside encrypted vault item ciphertext. This keeps the backend simple but makes item sync heavy, causes conflicts for large files, and forces every item edit to resync attachment bytes.
- Add a backend CSV/file import endpoint. This violates the local-only plaintext boundary and gives the backend too much responsibility.
- Store encrypted blobs separately and keep only encrypted attachment metadata/references inside the local vault. This is the chosen approach because it aligns with the existing revisioned sync model and keeps plaintext handling local.

## Frontend Architecture

Add a local `vault_attachments` table with one row per encrypted blob:

- `blob_id`: UUID-safe identifier generated locally.
- `item_id`: parent vault item id.
- encrypted metadata envelope: `metadata_nonce`, `metadata_ciphertext`, `metadata_mac` for JSON containing display name, media type, and plaintext byte length.
- encrypted content envelope: `nonce`, `ciphertext`, and `mac` for the file bytes.
- local lifecycle fields: created/updated/deleted timestamps.

Attachment metadata and bytes are encrypted on the client before they reach SQLite or the sync client. Metadata is encrypted because filenames often contain sensitive account names or recovery context. Plain size can be shown only after decrypting metadata; backend-visible ciphertext size remains operational metadata.

The attachment encryption key is derived from the unlocked vault DEK with HKDF and `blob_id`-scoped info. The app never stores the derived key. Master-password changes continue to work because they rewrap the DEK rather than changing vault content keys.

`VaultManifestService` will include attachment descriptors in the encrypted manifest payload. This makes local attachment tampering fail closed like item/password-history tampering.

## Backend Architecture

Add a `vault_blobs` table and `/blobs/push`, `/blobs/pull` endpoints. The route uses account auth plus active device checks, matching item sync. Each payload entry contains:

- `blob_id`
- `item_id`
- `metadata_ciphertext`
- `metadata_nonce`
- `metadata_aad`
- `ciphertext`
- `nonce`
- `aad`
- `ciphertext_sha256`
- `ciphertext_size`
- `revision`
- `deleted`
- `client_updated_at`

The backend stores and returns only opaque encrypted blob data. It validates shape, field names, safe token values, bounded sizes, AAD schema, revision types, delete booleans, device ownership, and user ownership. It rejects forbidden fields and unsafe values before persistence.

Use `schema: lockly-blob-v1` for content AAD and `schema: lockly-blob-meta-v1` for metadata AAD. Do not use `attachment`, `filename`, `mime`, `path`, or `file` as backend request fields or AAD values because the plaintext guard treats those words as sensitive.

## Sync Flow

Upload:

1. Frontend verifies the current vault manifest.
2. Frontend pushes vault metadata and item rows as today.
3. Frontend pushes encrypted blob rows for attachments.
4. Backend applies optimistic revision checks independently for blobs and returns applied rows or metadata-only conflicts.

Download:

1. Frontend pulls item rows and blob rows with separate cursors.
2. Frontend imports only encrypted rows into local storage.
3. User still needs the master password to unlock and decrypt local content.

Blob conflicts are not automatically merged. A conflict records only `blob_id`, `client_revision`, and `server_revision`; it must not include ciphertext or plaintext.

## User Experience

For this slice, expose minimal but real attachment management from the item detail/edit flow:

- list encrypted attachments after unlocking the vault;
- add an attachment from bytes supplied by the UI/service layer;
- delete an attachment;
- download/decrypt an attachment only after the vault is unlocked.

The implementation may avoid a new file-picker dependency in the first slice. The service API must be ready for a file picker later by accepting bytes plus metadata and returning decrypted bytes for export.

## Security Requirements

- Master password is never synced.
- Backend auth password is unrelated to the vault master password and never derives vault keys.
- Plain attachment bytes exist only in local process memory during add/download.
- Plain filenames and media types are encrypted before SQLite and before sync.
- Backend rejects `password`, `plaintext`, `secret`, `key`, `totp`, `passkey`, and `attachment`-named fields in blob request bodies.
- Backend and frontend docs must state that cloud blob storage is zero-knowledge and metadata-only conflicts are intentional.
- Tests must prove plaintext bytes and filename strings are absent from local DB rows and backend responses.

## Testing Strategy

Frontend:

- RED/GREEN tests for attachment encryption/decryption, local DB plaintext absence, manifest tamper failure, and AppServices add/list/delete/download flows.
- Sync API client/model tests for blob payload validation and rejected plaintext-shaped fields.
- Sync service tests for blob push/pull revision state.

Backend:

- RED/GREEN tests for blob push/pull, cross-user isolation, revoked device denial, forbidden plaintext field rejection, size/type validation, optimistic conflict responses, soft delete, docs contract, and Alembic schema.

## Out Of Scope

- OS file picker integration.
- Attachment previews/thumbnails.
- Streaming chunk upload.
- Sharing attachments with other users.
- Server-side antivirus/content inspection, because that would require plaintext access.
