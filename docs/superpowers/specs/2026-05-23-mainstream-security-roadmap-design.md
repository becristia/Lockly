# Lockly Mainstream Security Roadmap Design

## Goal

Evolve Lockly from a local-first password manager with zero-knowledge cloud sync into a mainstream password-manager workflow while keeping the existing security boundary intact:

- The master password, KEK, raw DEK, biometric DEK copy, decrypted entries, TOTP secrets, attachment plaintext, and passkey private material never leave the client.
- The backend account password authenticates only to `backend-pass`; it never unlocks the vault and never derives or wraps vault keys.
- Backend storage remains account/device/session/audit/ciphertext infrastructure. It may store encrypted vault metadata, encrypted item rows, encrypted attachment blobs, encrypted emergency packages, opaque passkey record ciphertext, revisions, and conflict metadata.

## Product Slices

### 1. Security Center Foundation

Build a first-class Security Center inside the unlocked app shell. It summarizes:

- local password health score and finding count;
- unresolved sync conflict count from local sync state;
- cloud device trust posture from the device API;
- sync/download readiness and the need for local master-password confirmation;
- migration, Autofill, attachment, passkey, and emergency-access readiness states.

This page does not decrypt or upload data during initial load. It can offer an explicit local health check that decrypts items only after the user asks for analysis. It connects existing local services into a coherent operational dashboard and becomes the entry point for later flows.

### 2. Sync Conflict Resolution

Keep conflicts conservative. The backend returns revision conflicts and never chooses a winner. The client stores encrypted remote conflict metadata locally and asks the user to resolve after local unlock. Resolution choices:

- keep local: push current local ciphertext with the latest server revision;
- accept remote: import remote encrypted payload through the same manifest/integrity path used by cloud download;
- duplicate: keep both records with a local rename before pushing.

The first UI can show unresolved conflicts and metadata. A later slice adds decrypted side-by-side comparison after the user explicitly unlocks and chooses to inspect.

### 3. Device Trust And Risk

Extend device data without exposing vault contents:

- platform, client version, last sync time, last IP address, last user agent, trusted/revoked state;
- local risk labels: current device, inactive device, revoked device, unknown platform, stale client;
- rename and revoke workflows.

Backend device metadata is operational account metadata, not vault key material. Device revocation stops future sync but does not erase or decrypt local data.

### 4. Import And Migration Wizard

Replace the current single paste/import flow with a guided migration wizard:

- Lockly encrypted JSON import/export remains the safest path;
- CSV/plaintext import is local-only, warns before parsing, and immediately writes into encrypted local vault rows;
- large imports are size-limited and streamed or chunked when dependencies are available;
- imported plaintext is never sent to backend and never stored outside encrypted vault rows.

Initial dependency-free implementation can support paste-based Lockly JSON and CSV. File pickers can be added after dependency availability is verified.

### 5. Android Autofill

Implement Android Autofill as a platform slice:

- native Android AutofillService declared in the Android manifest;
- package/domain matching before suggestions;
- local unlock or biometric confirmation before filling;
- no plaintext cache in platform storage;
- fill responses contain only the selected username/password for the active request.

This slice needs official Android documentation verification before coding because platform APIs and manifest requirements are unstable over time.

Stage A is now the selected foundation: Lockly declares a native Android `AutofillService`, exposes a `lockly/autofill` platform channel for support/enabled status and settings launch, and keeps the service zero-plaintext by returning no fill datasets until a later authenticated credential-picker flow exists.

### 6. Encrypted Attachments

Attachments use client-side encryption before sync:

- local attachment metadata is part of the encrypted record or an encrypted child record;
- attachment bytes are encrypted with per-attachment random keys wrapped by the vault DEK or derived subkeys;
- backend stores opaque blob ciphertext, nonce, MAC, size, content type, item id, and revision only;
- sync and backup treat attachments as ciphertext packages.

No attachment filename, OCR text, note, or preview should be uploaded in plaintext unless the user explicitly marks it non-sensitive, which is outside this roadmap.

### 7. Passkey Record Preparation

Add passkey record support in two stages:

- Stage A: encrypted record type and UI fields for relying party id, credential id, user handle, display name, public-key metadata, and platform readiness.
- Stage B: real platform passkey creation/assertion after platform APIs are researched and tested.

Private keys or platform-bound secrets must not be synced as backend-readable fields. If exportable passkeys are ever supported, they must be encrypted as vault ciphertext.

### 8. Emergency Access

Emergency access must remain zero-knowledge:

- trusted contact receives or stores a public-key encrypted recovery package;
- backend can store invite state, encrypted package, waiting period, cancellation, and audit events;
- backend cannot decrypt the package;
- user can revoke pending access before the waiting period completes.

This is a design-first slice because a wrong implementation would weaken the master-password boundary.

## Implementation Order

1. Security Center foundation and local conflict visibility.
2. Device trust/risk API and UI polish.
3. Import/migration wizard.
4. Sync conflict resolution workflow.
5. Encrypted attachment data model and backend blob API.
6. Android Autofill native integration.
7. Passkey record preparation.
8. Emergency access protocol and UX.

The order prioritizes shared visibility and low-risk account/device improvements before large platform or cryptographic protocol additions.

## Review Policy

After each functional slice:

- dispatch a frontend review subagent for UI, local crypto boundary, state handling, tests, and Flutter analyzer risks;
- dispatch a backend review subagent for endpoint authorization, payload validation, zero-knowledge violations, migrations, and pytest coverage;
- fix warning-or-higher findings before moving to the next slice.
