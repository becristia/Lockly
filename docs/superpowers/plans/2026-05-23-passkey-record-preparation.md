# Passkey Record Preparation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Stage A passkey record preparation so Lockly can store passkey metadata inside the encrypted vault item payload without implementing platform passkey creation/assertion yet.

**Architecture:** Passkey metadata is a local encrypted item-field only. The backend and sync protocol continue to see only opaque item ciphertext, nonce, AAD, revisions, and timestamps; no top-level `passkey`, credential id, user handle, private key, or platform secret field is sent to `backend-pass`. UI exposes create/edit/detail support after vault unlock, and Security Center remains a readiness entry point rather than a platform authenticator.

**Tech Stack:** Flutter/Dart, existing `PasswordEntry` JSON encryption path, existing `VaultService` item CRUD, Flutter widget tests, `flutter analyze`.

---

## Scope

Implement Stage A only:

- encrypted data model for passkey metadata;
- edit/detail UI for relying party id, credential id, user handle, display name, public key algorithm, platform, and platform readiness;
- tests proving passkey metadata is encrypted at rest and never added to backend-facing sync DTOs;
- documentation of the zero-knowledge boundary.

Do not implement Android Credential Manager, WebAuthn assertion, private-key import/export, QR pairing, resident-key creation, or backend passkey fields in this slice.

## File Map

| File | Action | Purpose |
| --- | --- | --- |
| `lib/data/models/passkey_record.dart` | Create | Focused value object for Stage A passkey metadata and validation. |
| `lib/data/models/password_entry.dart` | Modify | Add optional encrypted `PasskeyRecord? passkey` field to item plaintext JSON before encryption. |
| `lib/features/vault_edit/vault_edit_page.dart` | Modify | Add Passkey preparation section and dialog; persist metadata through `PasswordEntry`. |
| `lib/features/vault_detail/vault_detail_page.dart` | Modify | Show passkey metadata only in unlocked detail view. |
| `test/data/models/password_entry_test.dart` | Create | Validate JSON roundtrip and private-material rejection. |
| `test/core/vault/vault_service_test.dart` | Modify | Prove passkey metadata survives CRUD and is absent from raw encrypted DB rows. |
| `test/features/vault_item_flow_test.dart` | Modify | Cover edit/detail UI persistence through fake services. |
| `docs/security-check.md` | Modify | Record Stage A passkey boundary. |

## Task 1: Passkey Value Object

**Files:**
- Create: `lib/data/models/passkey_record.dart`
- Modify: `lib/data/models/password_entry.dart`
- Create: `test/data/models/password_entry_test.dart`

- [ ] **Step 1: Write failing model tests**

Add tests that demonstrate the desired API:

```dart
test('PasswordEntry roundtrips encrypted passkey preparation metadata', () {
  final entry = PasswordEntry(
    title: 'GitHub',
    website: 'https://github.com',
    username: 'alice',
    password: 'local-password',
    notes: '',
    tags: const ['dev'],
    passkey: PasskeyRecord(
      relyingPartyId: 'github.com',
      credentialId: 'credential-id',
      userHandle: 'user-handle',
      displayName: 'Alice',
      publicKeyAlgorithm: 'ES256',
      platform: 'android',
      platformReady: false,
    ),
  );

  final parsed = PasswordEntry.fromJson(entry.toJson());

  expect(parsed.passkey!.relyingPartyId, 'github.com');
  expect(parsed.passkey!.credentialId, 'credential-id');
  expect(parsed.passkey!.userHandle, 'user-handle');
  expect(parsed.passkey!.displayName, 'Alice');
  expect(parsed.passkey!.publicKeyAlgorithm, 'ES256');
  expect(parsed.passkey!.platform, 'android');
  expect(parsed.passkey!.platformReady, isFalse);
});

test('PasskeyRecord rejects private material fields', () {
  expect(
    () => PasskeyRecord.fromJson({
      'relying_party_id': 'github.com',
      'credential_id': 'credential-id',
      'user_handle': 'user-handle',
      'display_name': 'Alice',
      'public_key_algorithm': 'ES256',
      'platform': 'android',
      'platform_ready': false,
      'private_key': 'raw-secret',
    }),
    throwsFormatException,
  );
});
```

- [ ] **Step 2: Run model tests and verify RED**

Run:

```powershell
flutter test test/data/models/password_entry_test.dart -r compact
```

Expected: fails because `PasskeyRecord` and `PasswordEntry.passkey` do not exist.

- [ ] **Step 3: Implement minimal model**

Create `PasskeyRecord` with immutable string fields and `platformReady`. Use snake_case JSON keys. Reject unknown fields and any field name containing private/key/secret material such as `private_key`, `raw_key`, `secret`, `credential_private_key`, or `client_secret`. Add `passkey` to `PasswordEntry.toJson()` and `PasswordEntry.fromJson()`.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
flutter test test/data/models/password_entry_test.dart -r compact
```

Expected: all tests pass.

## Task 2: Vault Encryption Coverage

**Files:**
- Modify: `test/core/vault/vault_service_test.dart`

- [ ] **Step 1: Write failing vault test**

Add a test near existing item CRUD coverage:

```dart
test('passkey preparation metadata is encrypted inside item rows', () async {
  final service = await buildService();
  await service.createVault(masterPassword: 'master-passphrase');
  await service.unlock(masterPassword: 'master-passphrase');

  final id = await service.createItem(
    PasswordEntry(
      title: 'GitHub passkey',
      website: 'https://github.com',
      username: 'alice',
      password: 'local-password',
      notes: '',
      tags: const ['passkey'],
      passkey: PasskeyRecord(
        relyingPartyId: 'github.com',
        credentialId: 'credential-id',
        userHandle: 'user-handle',
        displayName: 'Alice',
        publicKeyAlgorithm: 'ES256',
        platform: 'android',
        platformReady: false,
      ),
    ),
  );

  final entry = await service.getItem(id);
  expect(entry.passkey!.credentialId, 'credential-id');

  final rawRows = await service.repository.itemsDao.rawRowsForTest();
  final rawText = rawRows.toString();
  expect(rawText, isNot(contains('credential-id')));
  expect(rawText, isNot(contains('user-handle')));
  expect(rawText, isNot(contains('github.com')));
});
```

- [ ] **Step 2: Run test and verify RED**

Run:

```powershell
flutter test test/core/vault/vault_service_test.dart --plain-name "passkey preparation metadata is encrypted inside item rows" -r compact
```

Expected: fails until Task 1 model support is implemented.

- [ ] **Step 3: Verify GREEN after Task 1**

Run the same command again. Expected: passes because `VaultService` already encrypts the entire `PasswordEntry` JSON.

## Task 3: Edit And Detail UI

**Files:**
- Modify: `lib/features/vault_edit/vault_edit_page.dart`
- Modify: `lib/features/vault_detail/vault_detail_page.dart`
- Modify: `test/features/vault_item_flow_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add one edit/detail persistence test:

```dart
testWidgets('user can add passkey preparation metadata and see it in detail', (tester) async {
  final services = AppServices.fake(hasVault: true, unlocked: true);
  addTearDown(services.dispose);

  await tester.pumpWidget(SecureBoxApp(services: services));
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('鏂板瀵嗙爜'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, '鏍囬'), 'GitHub');
  await tester.enterText(find.widgetWithText(TextFormField, '缃戝潃'), 'https://github.com');
  await tester.enterText(find.widgetWithText(TextFormField, '鐢ㄦ埛鍚?), 'alice');
  await tester.enterText(find.widgetWithText(TextFormField, '瀵嗙爜'), 'local-password');

  await tester.ensureVisible(find.byKey(const ValueKey('passkey-add-button')));
  await tester.tap(find.byKey(const ValueKey('passkey-add-button')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('passkey-rp-id-input')), 'github.com');
  await tester.enterText(find.byKey(const ValueKey('passkey-credential-id-input')), 'credential-id');
  await tester.enterText(find.byKey(const ValueKey('passkey-user-handle-input')), 'user-handle');
  await tester.enterText(find.byKey(const ValueKey('passkey-display-name-input')), 'Alice');
  await tester.enterText(find.byKey(const ValueKey('passkey-algorithm-input')), 'ES256');
  await tester.enterText(find.byKey(const ValueKey('passkey-platform-input')), 'android');
  await tester.tap(find.byKey(const ValueKey('passkey-save-button')));
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.widgetWithText(FilledButton, '淇濆瓨'));
  await tester.tap(find.widgetWithText(FilledButton, '淇濆瓨'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('GitHub'));
  await tester.pumpAndSettle();

  expect(find.text('Passkey'), findsOneWidget);
  expect(find.text('github.com'), findsWidgets);
  expect(find.text('credential-id'), findsOneWidget);
  expect(find.text('Platform API not enabled'), findsOneWidget);
});
```

- [ ] **Step 2: Run widget test and verify RED**

Run:

```powershell
flutter test test/features/vault_item_flow_test.dart --plain-name "user can add passkey preparation metadata and see it in detail" -r compact
```

Expected: fails because the passkey UI keys are absent.

- [ ] **Step 3: Implement edit UI**

Add a Passkey section below TOTP in `VaultEditPage`. Use stable keys:

- `passkey-add-button`
- `passkey-remove-button`
- `passkey-rp-id-input`
- `passkey-credential-id-input`
- `passkey-user-handle-input`
- `passkey-display-name-input`
- `passkey-algorithm-input`
- `passkey-platform-input`
- `passkey-platform-ready-toggle`
- `passkey-save-button`

The dialog must not include private key, secret, raw key, or exported credential private material fields. Saving with empty relying party id or credential id should keep the dialog open and show form validation errors. Persist into `PasswordEntry(passkey: _passkeyRecord)`.

- [ ] **Step 4: Implement detail UI**

If `entry.passkey != null`, render a `Passkey` detail section after the password section and before attachments. Show relying party id, credential id, user handle, display name, algorithm, platform, and readiness text. Use readiness labels `Platform API ready` and `Platform API not enabled`.

- [ ] **Step 5: Verify GREEN**

Run:

```powershell
flutter test test/features/vault_item_flow_test.dart --plain-name "user can add passkey preparation metadata and see it in detail" -r compact
```

Expected: passes.

## Task 4: Sync Boundary And Docs

**Files:**
- Modify: `test/core/sync/sync_models_test.dart`
- Modify: `docs/security-check.md`

- [ ] **Step 1: Add sync boundary test if missing**

Ensure the sync model tests prove raw sync payloads reject top-level passkey fields. If coverage already exists, do not duplicate it; instead add a targeted assertion that `PasswordEntry.toJson()` passkey metadata is not part of `SyncItemPayload.toJson()` because sync receives only encrypted item rows.

- [ ] **Step 2: Update docs**

Add a short bullet to `docs/security-check.md`:

```markdown
- Passkey Stage A stores relying-party and credential metadata only inside encrypted vault item JSON. No passkey private key, raw credential secret, user handle, or platform-bound secret is exposed as backend fields; sync still transmits only opaque item ciphertext.
```

- [ ] **Step 3: Run verification**

Run:

```powershell
flutter test test/data/models/password_entry_test.dart test/core/vault/vault_service_test.dart test/features/vault_item_flow_test.dart test/core/sync/sync_models_test.dart -r compact
flutter analyze
```

Expected: all tests pass and analyzer reports no issues.

## Final Review

After implementation:

- dispatch a frontend review subagent to inspect model validation, UI state, encryption boundary, tests, and analyzer output;
- dispatch a backend review subagent to confirm no backend passkey fields were added and existing forbidden-field guards still reject top-level passkey/private-key payloads;
- fix all Critical/Warning findings before moving to the next slice.

