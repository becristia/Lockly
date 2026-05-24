# Encrypted Attachments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add zero-knowledge encrypted attachment blobs for vault items, with backend blob sync endpoints and frontend local encryption, manifest coverage, service APIs, and minimal UI hooks.

**Architecture:** Attachments are independent encrypted blob rows, not enlarged vault item ciphertext. Frontend encrypts metadata and bytes locally with a blob-scoped key derived from the unlocked vault DEK; backend stores only opaque blob ciphertext packages and revision metadata. Item sync and blob sync remain separate but share account/device auth and optimistic conflict semantics.

**Tech Stack:** Flutter/Dart, sqflite, cryptography HKDF/AES-GCM, existing Lockly VaultService/AppServices/SyncService; FastAPI, SQLAlchemy, Alembic, pytest.

---

## File Structure

Backend files:

- Create `backend-pass/backend/app/blobs/__init__.py`
- Create `backend-pass/backend/app/blobs/routes.py`
- Modify `backend-pass/backend/app/main.py`
- Modify `backend-pass/backend/app/models.py`
- Create `backend-pass/backend/migrations/versions/20260523_0005_vault_blobs.py`
- Modify `backend-pass/tests/test_auth_devices_vault_sync.py`
- Modify `backend-pass/tests/test_migrations.py`
- Modify `backend-pass/tests/test_api_contract_docs.py`
- Modify `backend-pass/docs/api.md`
- Modify `backend-pass/docs/sync_protocol.md`
- Modify `backend-pass/docs/security.md`
- Modify `backend-pass/docs/database.md`

Frontend files:

- Create `Lockly/lib/data/models/encrypted_vault_blob.dart`
- Create `Lockly/lib/data/db/vault_blobs_dao.dart`
- Modify `Lockly/lib/data/db/app_database.dart`
- Modify `Lockly/lib/core/vault/vault_repository.dart`
- Modify `Lockly/lib/core/vault/vault_manifest_service.dart`
- Modify `Lockly/lib/core/vault/vault_service.dart`
- Modify `Lockly/lib/app/app_services.dart`
- Modify `Lockly/lib/features/vault_detail/vault_detail_page.dart`
- Modify `Lockly/lib/core/sync/sync_models.dart`
- Modify `Lockly/lib/core/sync/sync_api_client.dart`
- Modify `Lockly/lib/core/sync/sync_service.dart`
- Modify `Lockly/lib/data/db/sync_state_dao.dart`
- Modify `Lockly/lib/core/sync/sync_backup_adapter.dart`
- Modify `Lockly/lib/core/backup/backup_service.dart`
- Modify `Lockly/test/data/db/vault_database_test.dart`
- Modify `Lockly/test/core/vault/vault_service_test.dart`
- Modify `Lockly/test/core/backup/backup_service_test.dart`
- Modify `Lockly/test/core/sync/sync_models_test.dart`
- Modify `Lockly/test/core/sync/sync_api_client_test.dart`
- Modify `Lockly/test/core/sync/sync_service_test.dart`
- Modify `Lockly/test/app/cloud_sync_test.dart`
- Modify `Lockly/test/features/vault_item_flow_test.dart`
- Modify `Lockly/docs/security-check.md`

---

## Task 1: Backend Blob API

**Files:**
- Create: `backend-pass/backend/app/blobs/__init__.py`
- Create: `backend-pass/backend/app/blobs/routes.py`
- Modify: `backend-pass/backend/app/main.py`
- Modify: `backend-pass/backend/app/models.py`
- Create: `backend-pass/backend/migrations/versions/20260523_0005_vault_blobs.py`
- Modify/Test: `backend-pass/tests/test_auth_devices_vault_sync.py`
- Modify/Test: `backend-pass/tests/test_migrations.py`
- Modify/Test: `backend-pass/tests/test_api_contract_docs.py`
- Modify Docs: `backend-pass/docs/api.md`, `backend-pass/docs/sync_protocol.md`, `backend-pass/docs/security.md`, `backend-pass/docs/database.md`

- [ ] **Step 1: Write failing backend API tests**

Add tests covering these behaviors before production code:

```python
def test_blob_push_pull_roundtrip_requires_active_device(client):
    tokens = register_and_login(client)
    headers = auth_headers(tokens)
    client.post("/vault/init", json=safe_vault_payload(), headers=headers)
    device = register_device(client, headers)

    response = client.post(
        "/blobs/push",
        json={"device_id": device["id"], "blobs": [safe_blob_payload()]},
        headers=headers,
    )

    assert response.status_code == 200
    assert response.json()["applied"][0]["blob_id"] == "blob-safe-1"
    pulled = client.get(
        f"/blobs/pull?since=1970-01-01T00:00:00Z&device_id={device['id']}",
        headers=headers,
    )
    assert pulled.status_code == 200
    body = pulled.json()
    assert body["blobs"][0]["metadata_ciphertext"] == "meta-cipher"
    assert "filename" not in pulled.text


def test_blob_push_rejects_plaintext_fields_without_persisting(client):
    tokens = register_and_login(client)
    headers = auth_headers(tokens)
    client.post("/vault/init", json=safe_vault_payload(), headers=headers)
    device = register_device(client, headers)

    response = client.post(
        "/blobs/push",
        json={
            "device_id": device["id"],
            "blobs": [
                {
                    **safe_blob_payload(),
                    "filename": "recovery-codes.txt",
                }
            ],
        },
        headers=headers,
    )

    assert response.status_code == 422
    with TestingSessionLocal() as session:
        assert session.query(VaultBlob).count() == 0


def test_blob_push_conflict_is_metadata_only(client):
    tokens = register_and_login(client)
    headers = auth_headers(tokens)
    client.post("/vault/init", json=safe_vault_payload(), headers=headers)
    device = register_device(client, headers)
    client.post(
        "/blobs/push",
        json={"device_id": device["id"], "blobs": [safe_blob_payload()]},
        headers=headers,
    )

    conflict = client.post(
        "/blobs/push",
        json={
            "device_id": device["id"],
            "blobs": [safe_blob_payload(ciphertext="changed-cipher", revision=0)],
        },
        headers=headers,
    )

    assert conflict.status_code == 409
    body = conflict.json()
    assert body["conflicts"] == [
        {"blob_id": "blob-safe-1", "client_revision": 0, "server_revision": 1}
    ]
    assert "ciphertext" not in body["conflicts"][0]
```

Use existing helpers in `tests/conftest.py`. Add local helper `safe_blob_payload()` in the test file with fields: `blob_id`, `item_id`, `metadata_ciphertext`, `metadata_nonce`, `metadata_aad`, `ciphertext`, `nonce`, `aad`, `ciphertext_sha256`, `ciphertext_size`, `revision`, `deleted`, and `client_updated_at`.

- [ ] **Step 2: Run RED tests**

Run:

```powershell
python -m pytest -q tests/test_auth_devices_vault_sync.py::test_blob_push_pull_roundtrip_requires_active_device tests/test_auth_devices_vault_sync.py::test_blob_push_rejects_plaintext_fields_without_persisting tests/test_auth_devices_vault_sync.py::test_blob_push_conflict_is_metadata_only
```

Expected: fail because `/blobs/*` routes and `VaultBlob` do not exist.

- [ ] **Step 3: Implement model, migration, and router**

Implement `VaultBlob` in `backend/app/models.py` with unique `(user_id, blob_id)`, indexed `user_id`, `vault_id`, `item_id`, `blob_id`, and `server_updated_at`. Add Alembic migration `20260523_0005_vault_blobs.py`.

Implement `backend/app/blobs/routes.py` with:

- `POST /blobs/push`
- `GET /blobs/pull?since=<iso>&device_id=<id>`
- active user and active device checks equivalent to sync routes;
- vault initialized check;
- optimistic revision behavior equivalent to item sync;
- conflict body with `blob_id`, `client_revision`, `server_revision` only;
- request validation rejecting forbidden field names and unsafe `blob_id`, `item_id`, encrypted values, AAD values, size/hash mismatch, non-int revisions, non-bool deleted.

`ciphertext_size` is the UTF-8 encoded ciphertext string length. `ciphertext_sha256` is SHA-256 hex of the UTF-8 ciphertext string.

- [ ] **Step 4: Run backend feature tests**

Run:

```powershell
python -m pytest -q tests/test_auth_devices_vault_sync.py
```

Expected: pass.

- [ ] **Step 5: Add migration/docs contract tests**

Update `test_migrations.py` to assert `vault_blobs` exists with not-null encrypted fields and indexes. Update `test_api_contract_docs.py` to assert `/blobs/push`, `/blobs/pull`, zero-knowledge blob wording, and metadata-only blob conflicts.

Run:

```powershell
python -m pytest -q tests/test_migrations.py tests/test_api_contract_docs.py
```

Expected: pass.

---

## Task 2: Frontend Local Encrypted Blobs

**Files:**
- Create: `Lockly/lib/data/models/encrypted_vault_blob.dart`
- Create: `Lockly/lib/data/db/vault_blobs_dao.dart`
- Modify: `Lockly/lib/data/db/app_database.dart`
- Modify: `Lockly/lib/core/vault/vault_repository.dart`
- Modify: `Lockly/lib/core/vault/vault_manifest_service.dart`
- Modify: `Lockly/lib/core/vault/vault_service.dart`
- Modify: `Lockly/lib/app/app_services.dart`
- Modify/Test: `Lockly/test/data/db/vault_database_test.dart`
- Modify/Test: `Lockly/test/core/vault/vault_service_test.dart`
- Modify/Test: `Lockly/test/features/vault_item_flow_test.dart`

- [ ] **Step 1: Write failing local storage and service tests**

Add tests before implementation:

```dart
test('vault blobs store encrypted metadata and bytes only', () async {
  final db = await AppDatabase.openInMemory();
  addTearDown(db.close);

  final columns = await db.rawQuery('PRAGMA table_info(vault_blobs)');
  final names = columns.map((row) => row['name']).toSet();

  expect(names, containsAll([
    'blob_id',
    'item_id',
    'metadata_nonce',
    'metadata_ciphertext',
    'metadata_mac',
    'nonce',
    'ciphertext',
    'mac',
  ]));
  expect(names, isNot(contains('filename')));
  expect(names, isNot(contains('plaintext')));
  expect(names, isNot(contains('file_bytes')));
});

test('attachment add list open and delete never persist plaintext', () async {
  final harness = await createUnlockedVaultHarness();
  final itemId = await harness.vault.createItem(passwordEntry());

  final blobId = await harness.vault.addBlob(
    itemId: itemId,
    displayName: 'recovery-codes.txt',
    mediaType: 'text/plain',
    bytes: Uint8List.fromList(utf8.encode('plain recovery bytes')),
  );

  final rows = await harness.db.query('vault_blobs');
  expect(jsonEncode(rows), isNot(contains('recovery-codes.txt')));
  expect(jsonEncode(rows), isNot(contains('plain recovery bytes')));

  final list = await harness.vault.listBlobs(itemId);
  expect(list.single.displayName, 'recovery-codes.txt');
  final opened = await harness.vault.openBlob(blobId);
  expect(utf8.decode(opened.bytes), 'plain recovery bytes');

  await harness.vault.deleteBlob(blobId);
  expect(await harness.vault.listBlobs(itemId), isEmpty);
});
```

Use existing vault test harness helpers if present; otherwise add local helpers in the test file following the existing create/unlock pattern.

- [ ] **Step 2: Run RED tests**

Run:

```powershell
flutter test test/data/db/vault_database_test.dart test/core/vault/vault_service_test.dart test/features/vault_item_flow_test.dart
```

Expected: fail because `vault_blobs` and blob service APIs do not exist.

- [ ] **Step 3: Implement local blob model and DAO**

Create `EncryptedVaultBlob` with db conversion and strict type validation. Create `VaultBlobsDao` with `upsert`, `activeByItem`, `byBlobId`, `allForManifest`, `softDelete`, `softDeleteForItem`, `restoreForItem`, `hardDelete`, `hardDeleteForItem`, and `rawRowsForTest`.

Update `AppDatabase.schemaVersion` to `5`, create `vault_blobs`, add indexes, and create it in `onUpgrade` for `oldVersion < 5`.

Update `VaultRepository` to carry `blobsDao` through transactions.

- [ ] **Step 4: Implement encryption and manifest coverage**

In `VaultService`, add:

- `Future<String> addBlob({required String itemId, required String displayName, required String mediaType, required Uint8List bytes})`
- `Future<List<VaultBlobListItem>> listBlobs(String itemId)`
- `Future<DecryptedVaultBlob> openBlob(String blobId)`
- `Future<void> deleteBlob(String blobId)`

Derive a 32-byte blob key via HKDF-SHA256 from DEK with info `lockly:vault-blob:v1:<blob_id>`. Encrypt metadata JSON and content bytes separately. Zero the derived key after use.

Update manifest create/verify paths to include blob descriptors from `VaultBlobsDao.allForManifest()`. Existing vaults with no blob rows and older manifests remain accepted; after the next mutation, the manifest includes `blob_count` and `blobs_digest`.

Update item soft-delete/restore/permanent-delete/empty-trash flows so blob tombstones follow item lifecycle.

- [ ] **Step 5: Add AppServices and minimal UI hooks**

Add AppServices wrappers for `addVaultBlob`, `listVaultBlobs`, `openVaultBlob`, and `deleteVaultBlob`.

In `vault_detail_page.dart`, show an Attachments section that lists decrypted names and sizes. For this slice, add service-level support and a test-visible UI state; avoid adding a file-picker dependency.

- [ ] **Step 6: Run frontend local tests**

Run:

```powershell
flutter test test/data/db/vault_database_test.dart test/core/vault/vault_service_test.dart test/features/vault_item_flow_test.dart
flutter analyze
```

Expected: pass and no analyzer issues.

---

## Task 3: Frontend Blob Sync And Backup

**Files:**
- Modify: `Lockly/lib/core/sync/sync_models.dart`
- Modify: `Lockly/lib/core/sync/sync_api_client.dart`
- Modify: `Lockly/lib/core/sync/sync_service.dart`
- Modify: `Lockly/lib/data/db/sync_state_dao.dart`
- Modify: `Lockly/lib/core/sync/sync_backup_adapter.dart`
- Modify: `Lockly/lib/core/backup/backup_service.dart`
- Modify: `Lockly/lib/core/vault/vault_service.dart`
- Modify: `Lockly/lib/app/app_services.dart`
- Modify/Test: `Lockly/test/core/sync/sync_models_test.dart`
- Modify/Test: `Lockly/test/core/sync/sync_api_client_test.dart`
- Modify/Test: `Lockly/test/core/sync/sync_service_test.dart`
- Modify/Test: `Lockly/test/core/backup/backup_service_test.dart`
- Modify/Test: `Lockly/test/app/cloud_sync_test.dart`
- Modify Docs: `Lockly/docs/security-check.md`

- [ ] **Step 1: Write failing sync DTO/API tests**

Add tests for:

- `SyncBlobPayload.fromLocal()` emits `metadata_ciphertext`, `metadata_nonce`, `metadata_aad`, `ciphertext`, `nonce`, `aad`, `ciphertext_sha256`, `ciphertext_size`, `revision`, `deleted`, and `client_updated_at`.
- unsafe raw blob payloads containing `filename`, `plaintext`, `file_bytes`, `raw_key`, or `attachment_plaintext` are rejected before sending.
- `/blobs/push` 409 returns metadata-only blob conflicts.
- `/blobs/pull` rejects response objects with forbidden plaintext fields.

- [ ] **Step 2: Run RED sync tests**

Run:

```powershell
flutter test test/core/sync/sync_models_test.dart test/core/sync/sync_api_client_test.dart test/core/sync/sync_service_test.dart
```

Expected: fail because blob sync DTOs and methods do not exist.

- [ ] **Step 3: Implement blob sync DTOs, API client, and state**

Add `SyncBlobPayload`, `SyncBlob`, `SyncBlobConflict`, `SyncBlobPushResponse`, and `SyncBlobPullResponse`.

Add `SyncApiClient.pushBlobs()`, `pushRawBlobs()`, and `pullBlobs()` using `/blobs/push` and `/blobs/pull`.

Add `sync_blob_state`, `sync_blob_conflicts`, and `last_blob_pull_cursor` storage in `SyncStateDao`, including `clearAll()`.

Add `SyncService.pushEncryptedBlobs()`, `pullEncryptedBlobs()`, and conflict persistence.

- [ ] **Step 4: Integrate cloud sync and encrypted backup**

Extend `VerifiedEncryptedVaultSyncSnapshot` to include encrypted blobs. Update `AppServices.syncEncryptedVaultNow()` to push blobs after items.

Extend cloud download backup conversion so `prepareEncryptedVaultDownload()` includes encrypted blobs before backup manifest verification. Extend `BackupService` to export/import blob rows and re-encrypt blob content/metadata when merging into a different vault envelope.

- [ ] **Step 5: Run sync and backup tests**

Run:

```powershell
flutter test test/core/sync/sync_models_test.dart test/core/sync/sync_api_client_test.dart test/core/sync/sync_service_test.dart test/core/backup/backup_service_test.dart test/app/cloud_sync_test.dart
flutter analyze
```

Expected: pass and no analyzer issues.

---

## Task 4: Final Verification And Review

**Files:**
- All files changed by Tasks 1-3.

- [ ] **Step 1: Run full frontend verification**

Run:

```powershell
flutter test
flutter analyze
git diff --check
```

Expected: all tests pass, analyzer reports no issues, diff check exit code 0.

- [ ] **Step 2: Run full backend verification**

Run:

```powershell
python -m pytest -q
git diff --check
```

Expected: all tests pass and diff check exit code 0.

- [ ] **Step 3: Dispatch frontend and backend review agents**

Frontend reviewer checks:

- no plaintext bytes, filenames, media types, raw blob keys, master password, or DEK cross SQLite/sync/backup;
- manifest covers blob rows;
- download/import keeps master-password gate;
- UI does not expose stale plaintext after delete or lock.

Backend reviewer checks:

- `/blobs/*` stores only encrypted packages and operational metadata;
- device revocation and cross-user isolation cannot be bypassed;
- conflicts are metadata-only;
- docs and OpenAPI match implementation;
- no Warning+ issues remain.

- [ ] **Step 4: Fix review issues and rerun targeted verification**

For every Warning+ finding, write/adjust a failing test first, implement the minimal fix, rerun the targeted command, then rerun full verification if the fix touched shared behavior.

---

## Self-Review Notes

- The backend and frontend write sets are separated enough for parallel workers in Tasks 1 and 2.
- Task 3 depends on Task 1 API shape and Task 2 local blob model.
- No server endpoint accepts plaintext file bytes or file names.
- No AAD value uses `attachment`, `filename`, `mime`, `path`, or `file`.
