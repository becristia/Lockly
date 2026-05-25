# LAN Selective Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Lockly App cloud sync with user-selected LAN transfer where the receiver scans a sender QR code, enters the sender master password, skips conflicts, and re-encrypts accepted entries under the receiver vault key.

**Architecture:** Remove App-side backend sync wiring and cloud UI from this branch, while preserving local encrypted backup and vault features. Add a `core/lan_sync` layer for QR payloads, one-time transfer encryption, short-lived HTTP serving, downloading, and import orchestration. Reuse `BackupService` and `VaultService` for the source master-password verification and receiver-side re-encryption path, adding selected export and conflict-aware import instead of building a separate plaintext migration path.

**Tech Stack:** Flutter/Dart, `dart:io` `HttpServer`/`HttpClient`, existing `cryptography` AES-GCM via `CryptoService`, existing sqflite vault repository, `qr_flutter` for QR rendering, `mobile_scanner` for QR scanning, Flutter widget tests and unit tests.

---

## Implementation Gate

This plan is documentation only. Do not edit code until the user explicitly confirms this plan.

All implementation work stays inside `Lockly`. Do not modify `backend-pass` or any other folder.

If package download fails, retry at most three total times. Stop implementation if the same network resource download fails three consecutive times.

## Scope Check

The approved spec covers one subsystem: App-only LAN selective exchange replacing App cloud sync in this branch. It does not require backend changes. The plan below keeps the implementation in one feature stream because every task either removes cloud sync from the App surface or builds the LAN replacement.

## File Structure

### Create

| File | Responsibility |
| --- | --- |
| `lib/core/lan_sync/lan_transfer_models.dart` | QR payload, transfer envelope, session, conflict, and result value objects. |
| `lib/core/lan_sync/lan_transfer_crypto.dart` | AES-GCM transport encryption, SHA-256 package fingerprinting, random token/key generation, and constant-time token comparison. |
| `lib/core/lan_sync/lan_transfer_server.dart` | Sender-side short-lived local HTTP server exposing one authenticated transfer endpoint. |
| `lib/core/lan_sync/lan_transfer_client.dart` | Receiver-side HTTP download and transfer envelope validation. |
| `lib/core/lan_sync/lan_transfer_service.dart` | App-facing orchestration for selected export, send session creation, receive download, source-password import, and conflict result mapping. |
| `lib/features/lan_sync/lan_sync_page.dart` | Entry screen for Send and Receive flows. |
| `lib/features/lan_sync/lan_send_page.dart` | Sender list/search/filter/multi-select, options, QR display, countdown, and cancel flow. |
| `lib/features/lan_sync/lan_receive_page.dart` | QR scan, source master-password prompt, import progress, and result screen. |
| `test/core/lan_sync/lan_transfer_models_test.dart` | QR payload parsing/validation and secret-boundary tests. |
| `test/core/lan_sync/lan_transfer_crypto_test.dart` | Transfer encryption, fingerprint, and token tests. |
| `test/core/lan_sync/lan_transfer_transport_test.dart` | In-process server/client tests for token, expiry, one-time download, and integrity checks. |
| `test/core/lan_sync/lan_transfer_service_test.dart` | End-to-end service tests with two local vault harnesses. |
| `test/features/lan_sync_page_test.dart` | Widget tests for settings entry, send flow, receive flow, conflict result, and no cloud UI. |
| `docs/manual-lan-sync-test-plan-2026-05-25.md` | Manual test checklist replacing the cloud-sync manual path for this branch. |

### Modify

| File | Change |
| --- | --- |
| `pubspec.yaml` | Add QR generation/scanning dependencies and remove cloud-only dependencies only if they become unused. |
| `lib/main.dart` | Stop building `SyncService`, `SyncStateDao`, and `LOCKLY_SYNC_BASE_URL`; wire `LanTransferService`. |
| `lib/app/app_services.dart` | Remove cloud sync and remote emergency-access facade methods; add LAN transfer facade methods and fake overrides. |
| `lib/app/app.dart` | Add `/lan-sync`, `/lan-sync/send`, and `/lan-sync/receive` routes. |
| `lib/core/backup/backup_service.dart` | Add selected export and conflict-aware import under the existing encrypted backup envelope. |
| `lib/core/vault/vault_service.dart` | Expose narrow import/decrypt helpers needed by `BackupService` without exposing DEK or plaintext outside service boundaries. |
| `lib/data/db/app_database.dart` | Bump schema and drop unused cloud sync state tables on upgrade; stop creating sync tables for new installs. |
| `lib/features/settings/settings_page.dart` | Replace cloud sync section with LAN exchange entry and remove cloud dialogs. |
| `lib/features/security_center/security_center_page.dart` | Remove cloud/device/remote emergency sections; keep local health, migration, autofill, attachments, passkeys, trash, and backup posture. |
| `lib/shared/i18n/app_strings.dart` | Add typed getters or text keys for LAN strings. |
| `lib/shared/i18n/app_strings_zh.dart` | Add Chinese LAN strings and remove visible cloud strings that are no longer referenced. |
| `lib/shared/i18n/app_strings_en.dart` | Add English LAN strings and remove visible cloud strings that are no longer referenced. |
| `android/app/src/main/AndroidManifest.xml` | Add `android.permission.CAMERA`; keep `INTERNET`, `USE_BIOMETRIC`, and backup disabled. |
| `test/android_integration_test.dart` | Rename network permission test from cloud sync to LAN transfer and assert camera permission. |
| `test/features/generator_settings_test.dart` | Replace cloud settings tests with LAN settings tests. |
| `test/features/security_center_test.dart` | Replace cloud conflict/device/emergency tests with local-only security center tests. |
| `test/ui/visual_system_test.dart` | Replace cloud visual assertions with LAN exchange assertions. |
| `test/core/backup/backup_service_test.dart` | Add selected export and conflict-aware import tests. |

### Delete

| File or folder | Reason |
| --- | --- |
| `lib/app/sync_service_factory.dart` | Cloud backend factory is not used by LAN exchange. |
| `lib/core/sync/` | Cloud API, credentials, models, payload guard, and sync service are removed from this branch. |
| `lib/data/db/sync_state_dao.dart` | Cloud sync cursors/conflicts are removed from App code. |
| `lib/features/emergency_access/emergency_access_page.dart` | Current emergency access implementation depends on backend sync APIs. |
| `lib/core/emergency/emergency_crypto_service.dart` | Only used by removed remote emergency access UI/tests. |
| `test/app/cloud_sync_test.dart` | Replaced by LAN transfer service tests. |
| `test/app/main_sync_wiring_test.dart` | Cloud boot wiring is removed. |
| `test/core/sync/` | Cloud sync core is removed. |
| `test/data/db/sync_state_dao_test.dart` | Cloud sync DAO is removed. |
| `test/features/emergency_access_page_test.dart` | Remote emergency access page is removed. |
| `test/core/emergency/emergency_crypto_service_test.dart` | Remote emergency crypto is removed with the feature. |

## Task 1: Remove App Cloud Sync Surface

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/main.dart`
- Modify: `lib/app/app_services.dart`
- Modify: `lib/data/db/app_database.dart`
- Modify: `lib/features/settings/settings_page.dart`
- Modify: `lib/features/security_center/security_center_page.dart`
- Modify: `lib/shared/i18n/app_strings.dart`
- Modify: `lib/shared/i18n/app_strings_zh.dart`
- Modify: `lib/shared/i18n/app_strings_en.dart`
- Delete: `lib/app/sync_service_factory.dart`
- Delete: `lib/core/sync/`
- Delete: `lib/data/db/sync_state_dao.dart`
- Delete: `lib/features/emergency_access/emergency_access_page.dart`
- Delete: `lib/core/emergency/emergency_crypto_service.dart`
- Delete: `test/app/cloud_sync_test.dart`
- Delete: `test/app/main_sync_wiring_test.dart`
- Delete: `test/core/sync/`
- Delete: `test/data/db/sync_state_dao_test.dart`
- Delete: `test/features/emergency_access_page_test.dart`
- Delete: `test/core/emergency/emergency_crypto_service_test.dart`
- Test: `test/features/generator_settings_test.dart`
- Test: `test/features/security_center_test.dart`
- Test: `test/ui/visual_system_test.dart`
- Test: `test/android_integration_test.dart`

- [ ] **Step 1: Write failing cloud-removal assertions**

Update settings and security center widget tests before deleting implementation. Add these assertions to the relevant tests:

```dart
testWidgets('settings exposes LAN exchange and no cloud sync actions', (tester) async {
  final services = AppServices.fake(hasVault: true, unlocked: true);

  await tester.pumpWidget(SecureBoxApp(services: services));
  await tester.pumpAndSettle();
  services.navigatorKey.currentState!.pushNamed(AppServices.routeSettings);
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('settings-section-lan-sync')), findsOneWidget);
  expect(find.byKey(const ValueKey('settings-lan-send')), findsOneWidget);
  expect(find.byKey(const ValueKey('settings-lan-receive')), findsOneWidget);
  expect(find.byKey(const ValueKey('settings-section-cloud-sync')), findsNothing);
  expect(find.byKey(const ValueKey('settings-cloud-register')), findsNothing);
  expect(find.byKey(const ValueKey('settings-cloud-sync-now')), findsNothing);
  expect(find.byKey(const ValueKey('settings-cloud-download')), findsNothing);
  expect(find.byKey(const ValueKey('settings-cloud-devices')), findsNothing);
});

testWidgets('security center is local-only after cloud removal', (tester) async {
  final services = AppServices.fake(hasVault: true, unlocked: true);

  await tester.pumpWidget(MaterialApp(home: SecurityCenterPage(services: services)));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('security-center-page')), findsOneWidget);
  expect(find.byKey(const ValueKey('security-center-health-card')), findsOneWidget);
  expect(find.byKey(const ValueKey('security-center-cloud-card')), findsNothing);
  expect(find.byKey(const ValueKey('security-center-conflicts-card')), findsNothing);
  expect(find.byKey(const ValueKey('security-center-devices-card')), findsNothing);
  expect(find.byKey(const ValueKey('security-center-emergency-card')), findsNothing);
  expect(find.byKey(const ValueKey('security-center-emergency-access')), findsNothing);
});
```

- [ ] **Step 2: Run targeted RED tests**

Run:

```powershell
flutter test test/features/generator_settings_test.dart test/features/security_center_test.dart test/ui/visual_system_test.dart -r compact
```

Expected: fail because LAN keys and local-only security center changes are not implemented yet.

- [ ] **Step 3: Remove cloud/backend boot wiring**

Implement these boot changes:

- In `lib/main.dart`, remove imports for `app/sync_service_factory.dart` and `data/db/sync_state_dao.dart`.
- Remove `const syncBaseUrl = String.fromEnvironment('LOCKLY_SYNC_BASE_URL');`.
- Remove `SyncStateDao(database)` and `buildProductionSyncService(...)`.
- Construct `AppServices` without `syncService`.
- Keep `BackupService`, `VaultService`, `AndroidAutofillService`, `BiometricService`, `ClipboardService`, language preference, and lifecycle behavior unchanged.
Production LAN service wiring is added in Task 5. Task 1 must still compile after removing cloud constructor arguments.

- [ ] **Step 4: Remove cloud facade from `AppServices`**

Remove these public types and methods from `lib/app/app_services.dart`:

- `CloudSyncResult`
- `loginCloudSync`
- `registerCloudSync`
- `logoutCloudSync`
- `cloudSyncAccountEmail`
- `isCloudSyncSignedIn`
- `listCloudSyncDevices`
- `revokeCloudSyncDevice`
- `renameCloudSyncDevice`
- `listSyncConflicts`
- `listSyncBlobConflicts`
- `clearSyncConflict`
- `clearSyncBlobConflict`
- `syncEncryptedVaultNow`
- `downloadCloudEncryptedVault`
- `_downloadCloudAdditionsBeforePush`
- `_applyRemoteDeletedSyncItems`
- `_applyRemoteDeletedSyncBlobs`
- `syncService` getter
- all cloud and remote emergency constructor override fields

Keep local emergency-facing text out of the UI until a backend-free recovery feature is designed. Preserve local backup/import methods.

Add route constants only, so settings tiles can compile before the LAN service implementation exists:

```dart
static const routeLanSync = '/lan-sync';
static const routeLanSend = '/lan-sync/send';
static const routeLanReceive = '/lan-sync/receive';
```

- [ ] **Step 5: Remove sync tables from new schema and drop them on upgrade**

Change `AppDatabase.schemaVersion` from `6` to `7`. Remove `_createSyncStateTables` and `_createSyncBlobStateTables` from `onCreate`. Add an `oldVersion < 7` upgrade block that drops the unused cloud state tables:

```dart
if (oldVersion < 7) {
  await db.execute('DROP TABLE IF EXISTS sync_blob_conflicts');
  await db.execute('DROP TABLE IF EXISTS sync_blob_state');
  await db.execute('DROP TABLE IF EXISTS sync_conflicts');
  await db.execute('DROP TABLE IF EXISTS sync_item_state');
  await db.execute('DROP TABLE IF EXISTS sync_state');
}
```

Keep vault, attachment, history, settings, and manifest tables intact.

- [ ] **Step 6: Replace cloud settings and security center UI**

In `settings_page.dart`, remove cloud state fields, cloud dialogs, cloud action methods, and the cloud section. Add a LAN section with keys:

```dart
const ValueKey('settings-section-lan-sync');
const ValueKey('settings-lan-send');
const ValueKey('settings-lan-receive');
```

In `security_center_page.dart`, remove imports and logic for `core/sync`, `sync_state_dao`, `EmergencyAccessPage`, cloud conflicts, device trust from cloud devices, and remote emergency cards. Keep local cards for health, migration, autofill, attachments, passkeys, and encrypted backup readiness.

- [ ] **Step 7: Remove cloud files and tests**

Delete the files and folders listed in the Delete section. After deletion, run:

```powershell
rg -n "LOCKLY_SYNC_BASE_URL|SyncService|SyncApiClient|SyncCredentialStore|SyncStateDao|settings-cloud|cloudSync|CloudSync|core/sync|emergency_access" lib test
```

Expected: no matches in `lib` or `test`.

- [ ] **Step 8: Run Task 1 tests**

Run:

```powershell
flutter test test/features/generator_settings_test.dart test/features/security_center_test.dart test/ui/visual_system_test.dart test/android_integration_test.dart -r compact
```

Expected: pass. No failures should reference deleted cloud imports.

- [ ] **Step 9: Commit Task 1**

```powershell
git add pubspec.yaml lib test android/app/src/main/AndroidManifest.xml
git commit -m "refactor: remove cloud sync app surface"
```

## Task 2: LAN Transfer Models and Crypto

**Files:**
- Create: `lib/core/lan_sync/lan_transfer_models.dart`
- Create: `lib/core/lan_sync/lan_transfer_crypto.dart`
- Create: `test/core/lan_sync/lan_transfer_models_test.dart`
- Create: `test/core/lan_sync/lan_transfer_crypto_test.dart`

- [ ] **Step 1: Write failing model tests**

Create `test/core/lan_sync/lan_transfer_models_test.dart` with tests covering schema, expiry, host/port, package fingerprint, and QR secret boundary:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';

void main() {
  test('QR payload roundtrip validates schema and omits vault plaintext', () {
    final payload = LanTransferQrPayload(
      host: '192.168.1.20',
      port: 49152,
      sessionId: 'session-1',
      token: 'token-value',
      transferKey: 'transfer-key-value',
      packageSha256: 'a' * 64,
      selectedCount: 3,
      expiresAt: DateTime.utc(2026, 5, 25, 12),
      senderName: 'Pixel 8',
    );

    final encoded = payload.encode();
    expect(encoded, contains('lockly-lan-transfer-v1'));
    expect(encoded, isNot(contains('master')));
    expect(encoded, isNot(contains('secret-password')));
    expect(encoded, isNot(contains('totp')));

    final decoded = LanTransferQrPayload.decode(encoded);
    expect(decoded.host, '192.168.1.20');
    expect(decoded.port, 49152);
    expect(decoded.selectedCount, 3);
  });

  test('QR payload rejects expired and malformed values', () {
    expect(
      () => LanTransferQrPayload.decode('{"schema":"wrong"}'),
      throwsA(isA<LanTransferFormatException>()),
    );

    expect(
      () => LanTransferQrPayload(
        host: '',
        port: 0,
        sessionId: 'session-1',
        token: 'token-value',
        transferKey: 'transfer-key-value',
        packageSha256: 'bad',
        selectedCount: 1,
        expiresAt: DateTime.utc(2020),
        senderName: 'Phone',
      ).validate(now: DateTime.utc(2026, 5, 25)),
      throwsA(isA<LanTransferFormatException>()),
    );
  });
}
```

- [ ] **Step 2: Write failing crypto tests**

Create `test/core/lan_sync/lan_transfer_crypto_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_crypto.dart';

void main() {
  test('transfer encryption roundtrip is authenticated and randomized', () async {
    final crypto = LanTransferCrypto(
      crypto: CryptoService(random: SecureRandom()),
      random: SecureRandom(),
    );
    final key = crypto.randomTransferKey();
    final plaintext = Uint8List.fromList(utf8.encode('{"version":2,"items":[]}'));

    final first = await crypto.encryptPackage(plaintext: plaintext, key: key);
    final second = await crypto.encryptPackage(plaintext: plaintext, key: key);

    expect(first.ciphertext, isNot(second.ciphertext));
    expect(await crypto.decryptPackage(envelope: first, key: key), plaintext);
    expect(first.packageSha256, crypto.sha256Hex(plaintext));
  });

  test('constant-time token check accepts exact token only', () {
    final crypto = LanTransferCrypto(
      crypto: CryptoService(random: SecureRandom()),
      random: SecureRandom(),
    );

    expect(crypto.tokenMatches('abc', 'abc'), isTrue);
    expect(crypto.tokenMatches('abc', 'abd'), isFalse);
    expect(crypto.tokenMatches('abc', 'abcd'), isFalse);
  });
}
```

- [ ] **Step 3: Run RED tests**

Run:

```powershell
flutter test test/core/lan_sync/lan_transfer_models_test.dart test/core/lan_sync/lan_transfer_crypto_test.dart -r compact
```

Expected: fail because `core/lan_sync` classes do not exist.

- [ ] **Step 4: Implement models**

Create these types in `lan_transfer_models.dart`:

```dart
const lanTransferSchema = 'lockly-lan-transfer-v1';

class LanTransferFormatException extends FormatException {
  const LanTransferFormatException(super.message, [super.source, super.offset]);
}

enum LanTransferConflictReason {
  existingLocalEntry,
  duplicateIncomingEntry,
}

class LanTransferQrPayload {
  const LanTransferQrPayload({
    required this.host,
    required this.port,
    required this.sessionId,
    required this.token,
    required this.transferKey,
    required this.packageSha256,
    required this.selectedCount,
    required this.expiresAt,
    required this.senderName,
  });

  final String host;
  final int port;
  final String sessionId;
  final String token;
  final String transferKey;
  final String packageSha256;
  final int selectedCount;
  final DateTime expiresAt;
  final String senderName;

  String encode();
  static LanTransferQrPayload decode(String value);
  void validate({DateTime? now});
  Uri transferUri();
}

class LanTransferEnvelope {
  const LanTransferEnvelope({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.contentLength,
    required this.packageSha256,
  });

  final String nonce;
  final String ciphertext;
  final String mac;
  final int contentLength;
  final String packageSha256;

  Map<String, Object?> toJson();
  factory LanTransferEnvelope.fromJson(Map<String, Object?> json);
}

class LanTransferConflict {
  const LanTransferConflict({
    required this.title,
    required this.website,
    required this.username,
    required this.reason,
  });

  final String title;
  final String website;
  final String username;
  final LanTransferConflictReason reason;
}

class LanTransferImportResult {
  const LanTransferImportResult({
    required this.importedCount,
    required this.skippedCount,
    required this.conflicts,
  });

  final int importedCount;
  final int skippedCount;
  final List<LanTransferConflict> conflicts;
}
```

Validation rules:

- schema must equal `lockly-lan-transfer-v1`.
- `host`, `sessionId`, `token`, `transferKey`, `senderName` cannot be blank.
- `port` must be 1 through 65535.
- `selectedCount` must be greater than 0.
- `packageSha256` must be exactly 64 lowercase hex characters.
- `expiresAt` must be in the future relative to the supplied `now` or current UTC time.

- [ ] **Step 5: Implement crypto**

Create `LanTransferCrypto` in `lan_transfer_crypto.dart` using existing `CryptoService`, `SecureRandom`, and `core/crypto/encoding.dart`.

Public methods:

```dart
class LanTransferCrypto {
  LanTransferCrypto({required CryptoService crypto, required SecureRandom random});

  String randomToken();
  Uint8List randomTransferKey();
  String encodeTransferKey(Uint8List key);
  Uint8List decodeTransferKey(String value);
  String sha256Hex(List<int> bytes);
  bool tokenMatches(String expected, String actual);
  Future<LanTransferEnvelope> encryptPackage({
    required Uint8List plaintext,
    required Uint8List key,
  });
  Future<Uint8List> decryptPackage({
    required LanTransferEnvelope envelope,
    required Uint8List key,
  });
}
```

Use SHA-256 from `package:hashlib/hashlib.dart` if already imported elsewhere, or Dart/cryptography primitives already in the project. Do not add a second hash package.

- [ ] **Step 6: Run Task 2 tests**

Run:

```powershell
flutter test test/core/lan_sync/lan_transfer_models_test.dart test/core/lan_sync/lan_transfer_crypto_test.dart -r compact
```

Expected: pass.

- [ ] **Step 7: Commit Task 2**

```powershell
git add lib/core/lan_sync test/core/lan_sync
git commit -m "feat: add LAN transfer models and crypto"
```

## Task 3: Selected Backup Export and Conflict-Aware Import

**Files:**
- Modify: `lib/core/backup/backup_service.dart`
- Modify: `lib/core/vault/vault_service.dart`
- Modify: `lib/app/app_services.dart`
- Modify: `test/core/backup/backup_service_test.dart`
- Create: `test/core/lan_sync/lan_transfer_service_test.dart`

- [ ] **Step 1: Write failing selected export tests**

Add tests to `test/core/backup/backup_service_test.dart`:

```dart
test('exportSelectedItemsBackup exports requested active items only', () async {
  final source = await _buildHarness();
  await source.vaultService.createVault(masterPassword: 'source-master');
  await source.vaultService.unlock(masterPassword: 'source-master');
  final firstId = await source.vaultService.createItem(
    PasswordEntry(
      title: 'GitHub',
      website: 'https://github.com',
      username: 'user@example.com',
      password: 'secret-password',
      notes: 'private note',
      tags: const ['dev'],
    ),
  );
  final secondId = await source.vaultService.createItem(
    PasswordEntry(
      title: 'Docs',
      website: 'https://docs.example',
      username: 'docs@example.com',
      password: 'docs-password',
      notes: 'not selected',
      tags: const ['docs'],
    ),
  );

  final backup = await source.backupService.exportSelectedItemsBackup(
    itemIds: [firstId],
    includeBlobs: true,
    includeHistory: false,
  );

  expect(backup.scope, 'selected');
  expect(backup.itemCount, 1);
  expect(backup.items.single.id, firstId);
  expect(backup.items.map((item) => item.id), isNot(contains(secondId)));
  expect(jsonEncode(backup.toJson()), isNot(contains('secret-password')));
  expect(jsonEncode(backup.toJson()), isNot(contains('docs-password')));
});
```

- [ ] **Step 2: Write failing conflict-aware import tests**

Add tests proving wrong source password imports nothing, different vault key re-encrypts, existing local conflicts are skipped, and package duplicates skip after first:

```dart
test('conflict-aware import skips local identity conflicts and re-encrypts accepted items', () async {
  final source = await _buildHarness();
  await source.vaultService.createVault(masterPassword: 'source-master');
  await source.vaultService.unlock(masterPassword: 'source-master');
  final conflictId = await source.vaultService.createItem(
    PasswordEntry(
      title: 'GitHub',
      website: 'https://www.github.com/',
      username: 'User@Example.com',
      password: 'source-conflict-password',
      notes: 'source conflict',
      tags: const ['dev'],
    ),
  );
  final importId = await source.vaultService.createItem(
    PasswordEntry(
      title: 'Docs',
      website: 'https://docs.example',
      username: 'docs@example.com',
      password: 'source-docs-password',
      notes: 'source docs',
      tags: const ['docs'],
    ),
  );
  final backup = await source.backupService.exportSelectedItemsBackup(
    itemIds: [conflictId, importId],
    includeBlobs: true,
    includeHistory: false,
  );

  final target = await _buildHarness();
  await target.vaultService.createVault(masterPassword: 'target-master');
  await target.vaultService.unlock(masterPassword: 'target-master');
  final localConflictId = await target.vaultService.createItem(
    PasswordEntry(
      title: ' github ',
      website: 'http://github.com',
      username: 'user@example.com',
      password: 'target-password',
      notes: 'local wins',
      tags: const ['local'],
    ),
  );

  final result = await target.backupService.importBackupSkippingIdentityConflicts(
    json: backup.toJson(),
    masterPassword: 'source-master',
  );

  expect(result.importedCount, 1);
  expect(result.skippedCount, 1);
  expect(result.conflicts.single.title, 'GitHub');
  expect((await target.vaultService.getItem(localConflictId)).password, 'target-password');
  expect((await target.vaultService.getItem(importId)).password, 'source-docs-password');

  target.vaultService.lock();
  expect(await target.vaultService.unlock(masterPassword: 'target-master'), isTrue);
  expect((await target.vaultService.getItem(importId)).password, 'source-docs-password');
});
```

- [ ] **Step 3: Run RED backup tests**

Run:

```powershell
flutter test test/core/backup/backup_service_test.dart -r compact
```

Expected: fail because selected export and conflict-aware import do not exist.

- [ ] **Step 4: Implement selected backup scope**

In `backup_service.dart`:

- Add `const String _backupScopeSelected = 'selected';`.
- Update `VaultBackup` validation to accept `full`, `item`, or `selected`.
- Reject `BackupImportMode.overwrite` for `item` and `selected` scopes.
- Add:

```dart
Future<VaultBackup> exportSelectedItemsBackup({
  required List<String> itemIds,
  bool includeBlobs = true,
  bool includeHistory = false,
});
```

Behavior:

- Throw `ArgumentError.value(itemIds, 'itemIds', 'At least one item must be selected')` when empty.
- Deduplicate item IDs while preserving input order.
- Require each item to exist and be active.
- Include active blobs only for selected items when `includeBlobs` is true.
- Include password history only for selected items when `includeHistory` is true.
- Build a version 2 backup with scope `selected`.

- [ ] **Step 5: Implement conflict key and result types**

In `backup_service.dart`, add public result objects:

```dart
enum BackupImportConflictReason {
  existingLocalEntry,
  duplicateIncomingEntry,
}

class BackupImportConflict {
  const BackupImportConflict({
    required this.itemId,
    required this.title,
    required this.website,
    required this.username,
    required this.reason,
  });

  final String itemId;
  final String title;
  final String website;
  final String username;
  final BackupImportConflictReason reason;
}

class ConflictAwareBackupImportResult {
  const ConflictAwareBackupImportResult({
    required this.importedCount,
    required this.skippedCount,
    required this.conflicts,
  });

  final int importedCount;
  final int skippedCount;
  final List<BackupImportConflict> conflicts;
}
```

Add normalization helpers matching the spec:

```dart
String backupIdentityConflictKey({
  required String title,
  required String website,
  required String username,
});
```

Use trim, lowercase, whitespace folding, `http://`/`https://` stripping, leading `www.` stripping, and trailing slash stripping.

- [ ] **Step 6: Implement conflict-aware import**

Add:

```dart
Future<ConflictAwareBackupImportResult> importBackupSkippingIdentityConflicts({
  required Map<String, Object?> json,
  required String masterPassword,
});
```

Implementation rules:

- Decode and validate the full `VaultBackup`.
- Verify source master password and full source manifest before conflict filtering.
- Require the target vault to be unlocked when importing into an existing different envelope.
- Decrypt source item metadata only in memory to compute conflict keys.
- Build local conflict keys from active target items.
- Skip local conflicts and package duplicates.
- Insert only accepted encrypted rows, blobs for accepted item IDs, and history for accepted item IDs.
- Re-encrypt accepted rows with the target vault key when the source and target envelope differ.
- Rewrite the target manifest after insertion.
- Zero plaintext byte buffers after use.
- Do not expose password, notes, TOTP, attachment bytes, or Passkey private fields in `BackupImportConflict`.

If adding a helper to `VaultService`, keep it package-private or narrowly public and do not expose raw DEK:

```dart
Future<List<PasswordEntry>> decryptImportedItemsForConflictCheck({
  required List<EncryptedVaultItem> items,
  required VaultMeta sourceMeta,
  required String sourcePassword,
});
```

- [ ] **Step 7: Expose through `AppServices`**

Add to `AppServices`:

```dart
Future<String> exportLanTransferBackupJson({
  required List<String> itemIds,
  required bool includeBlobs,
  required bool includeHistory,
});

Future<ConflictAwareBackupImportResult> importLanTransferBackupJson({
  required String backupJson,
  required String sourceMasterPassword,
});
```

`importLanTransferBackupJson` must keep `maxImportedBackupJsonBytes` and JSON map validation.

- [ ] **Step 8: Run Task 3 tests**

Run:

```powershell
flutter test test/core/backup/backup_service_test.dart -r compact
```

Expected: pass.

- [ ] **Step 9: Commit Task 3**

```powershell
git add lib/core/backup/backup_service.dart lib/core/vault/vault_service.dart lib/app/app_services.dart test/core/backup/backup_service_test.dart
git commit -m "feat: add conflict-aware selected backups"
```

## Task 4: LAN HTTP Server and Client

**Files:**
- Create: `lib/core/lan_sync/lan_transfer_server.dart`
- Create: `lib/core/lan_sync/lan_transfer_client.dart`
- Modify: `lib/core/lan_sync/lan_transfer_models.dart`
- Create: `test/core/lan_sync/lan_transfer_transport_test.dart`

- [ ] **Step 1: Write failing transport tests**

Create `test/core/lan_sync/lan_transfer_transport_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_client.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_crypto.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_server.dart';

void main() {
  test('server serves one authenticated encrypted package', () async {
    final crypto = LanTransferCrypto(
      crypto: CryptoService(random: SecureRandom()),
      random: SecureRandom(),
    );
    final server = LanTransferServer(crypto: crypto);
    final plaintext = Uint8List.fromList(utf8.encode('{"version":2,"items":[]}'));

    final session = await server.start(
      packageBytes: plaintext,
      selectedCount: 1,
      senderName: 'Sender',
      ttl: const Duration(minutes: 5),
      bindHost: '127.0.0.1',
      advertisedHost: '127.0.0.1',
    );
    addTearDown(server.close);

    final client = LanTransferClient(crypto: crypto);
    final downloaded = await client.download(session.qrPayload);
    expect(utf8.decode(downloaded), '{"version":2,"items":[]}');

    await expectLater(
      client.download(session.qrPayload),
      throwsA(isA<LanTransferUnavailableException>()),
    );
  });

  test('server rejects wrong token and expired session', () async {
    final crypto = LanTransferCrypto(
      crypto: CryptoService(random: SecureRandom()),
      random: SecureRandom(),
    );
    final server = LanTransferServer(crypto: crypto);
    addTearDown(server.close);

    final session = await server.start(
      packageBytes: Uint8List.fromList(utf8.encode('{"version":2,"items":[]}')),
      selectedCount: 1,
      senderName: 'Sender',
      ttl: const Duration(milliseconds: 1),
      bindHost: '127.0.0.1',
      advertisedHost: '127.0.0.1',
    );
    final badPayload = session.qrPayload.copyWith(token: 'bad-token');
    final client = LanTransferClient(crypto: crypto);

    await expectLater(
      client.download(badPayload),
      throwsA(isA<LanTransferUnavailableException>()),
    );

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await expectLater(
      client.download(session.qrPayload),
      throwsA(isA<LanTransferExpiredException>()),
    );
  });
}
```

- [ ] **Step 2: Run RED transport tests**

Run:

```powershell
flutter test test/core/lan_sync/lan_transfer_transport_test.dart -r compact
```

Expected: fail because server/client do not exist.

- [ ] **Step 3: Implement server**

Use `dart:io` `HttpServer.bind`. Public API:

```dart
class LanTransferServer {
  LanTransferServer({required LanTransferCrypto crypto});

  Future<LanTransferSession> start({
    required Uint8List packageBytes,
    required int selectedCount,
    required String senderName,
    Duration ttl = const Duration(minutes: 5),
    String bindHost = '0.0.0.0',
    String? advertisedHost,
  });

  Future<void> close();
}

class LanTransferSession {
  const LanTransferSession({
    required this.qrPayload,
    required this.expiresAt,
  });

  final LanTransferQrPayload qrPayload;
  final DateTime expiresAt;
}
```

Server behavior:

- Generate `sessionId`, token, and transfer key per session.
- Encrypt package bytes before accepting requests.
- Serve only `GET /v1/transfer/{sessionId}`.
- Require `Authorization: Bearer <token>`.
- Return `410` for expired session.
- Return `401` for wrong token.
- Return `404` for wrong path/session.
- Mark session consumed after the first `200` response.
- Close the server after consumption, explicit cancel, or expiry.
- Never write package bytes to disk.

- [ ] **Step 4: Implement client**

Public API:

```dart
class LanTransferClient {
  LanTransferClient({required LanTransferCrypto crypto});

  Future<Uint8List> download(LanTransferQrPayload payload);
}
```

Client behavior:

- Validate QR payload before network request.
- Send `Authorization: Bearer <token>`.
- Decode `LanTransferEnvelope`.
- Verify `packageSha256` from envelope equals QR `packageSha256`.
- Decrypt with QR `transferKey`.
- Verify decrypted bytes SHA-256 equals QR `packageSha256`.
- Throw typed exceptions for expired, unavailable, unauthorized, malformed, and integrity failures.

- [ ] **Step 5: Run Task 4 tests**

Run:

```powershell
flutter test test/core/lan_sync/lan_transfer_models_test.dart test/core/lan_sync/lan_transfer_crypto_test.dart test/core/lan_sync/lan_transfer_transport_test.dart -r compact
```

Expected: pass.

- [ ] **Step 6: Commit Task 4**

```powershell
git add lib/core/lan_sync test/core/lan_sync
git commit -m "feat: add LAN transfer transport"
```

## Task 5: LAN Transfer Service and App Routing

**Files:**
- Create: `lib/core/lan_sync/lan_transfer_service.dart`
- Modify: `lib/app/app_services.dart`
- Modify: `lib/app/app.dart`
- Modify: `lib/main.dart`
- Create: `test/core/lan_sync/lan_transfer_service_test.dart`

- [ ] **Step 1: Write failing service tests**

Create `test/core/lan_sync/lan_transfer_service_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_service.dart';

void main() {
  test('receiveSelectedBackup skips conflicts and hides secrets in result', () async {
    final harness = await LanTransferServiceTestHarness.build();
    await harness.seedSourceAndTargetWithOneConflict();

    final session = await harness.sourceService.createSendSession(
      itemIds: harness.sourceItemIds,
      includeBlobs: true,
      includeHistory: false,
      senderName: 'Source phone',
      bindHost: '127.0.0.1',
      advertisedHost: '127.0.0.1',
    );

    final result = await harness.targetService.receiveFromPayload(
      payload: session.qrPayload,
      sourceMasterPassword: 'source-master',
    );

    expect(result.importedCount, 1);
    expect(result.skippedCount, 1);
    expect(result.conflicts.single.title, 'GitHub');
    expect(result.conflicts.single.toString(), isNot(contains('source-conflict-password')));
    expect(jsonEncode(result.conflicts.map((item) => item.title).toList()), isNot(contains('totp-secret')));
  });
}
```

Implement `LanTransferServiceTestHarness` inside the test file using the same database harness pattern as `backup_service_test.dart`, not production storage.

- [ ] **Step 2: Run RED service tests**

Run:

```powershell
flutter test test/core/lan_sync/lan_transfer_service_test.dart -r compact
```

Expected: fail because `LanTransferService` does not exist.

- [ ] **Step 3: Implement service**

Create `LanTransferService`:

```dart
class LanTransferService {
  LanTransferService({
    required BackupService backupService,
    required LanTransferServer server,
    required LanTransferClient client,
  });

  Future<LanTransferSession> createSendSession({
    required List<String> itemIds,
    required bool includeBlobs,
    required bool includeHistory,
    required String senderName,
    Duration ttl = const Duration(minutes: 5),
    String bindHost = '0.0.0.0',
    String? advertisedHost,
  });

  Future<LanTransferImportResult> receiveFromPayload({
    required LanTransferQrPayload payload,
    required String sourceMasterPassword,
  });

  Future<void> cancelSendSession();
}
```

Implementation details:

- `createSendSession` calls `BackupService.exportSelectedItemsBackup`, JSON-encodes the backup with indentation, and passes UTF-8 bytes to `LanTransferServer.start`.
- `receiveFromPayload` downloads with `LanTransferClient`, decodes JSON, and calls `BackupService.importBackupSkippingIdentityConflicts`.
- Map `BackupImportConflictReason` to `LanTransferConflictReason`.
- Cancel closes the current server session.

- [ ] **Step 4: Wire AppServices and routes**

Add `LanTransferService? lanTransferService` to `AppServices`. Add fake overrides for widget tests:

```dart
Future<LanTransferSession> Function({
  required List<String> itemIds,
  required bool includeBlobs,
  required bool includeHistory,
  required String senderName,
})? createLanSendSessionOverride;

Future<LanTransferImportResult> Function({
  required LanTransferQrPayload payload,
  required String sourceMasterPassword,
})? receiveLanTransferOverride;
```

Add methods:

```dart
Future<LanTransferSession> createLanSendSession({
  required List<String> itemIds,
  required bool includeBlobs,
  required bool includeHistory,
  required String senderName,
});

Future<LanTransferImportResult> receiveLanTransfer({
  required LanTransferQrPayload payload,
  required String sourceMasterPassword,
});

Future<void> cancelLanSendSession();
```

Add routes in `AppServices`:

```dart
static const routeLanSync = '/lan-sync';
static const routeLanSend = '/lan-sync/send';
static const routeLanReceive = '/lan-sync/receive';
```

Update `resolveRouteName` and `SecureBoxApp._buildPageForRoute`.

- [ ] **Step 5: Wire production main**

In `main.dart`, create:

```dart
final lanTransferCrypto = LanTransferCrypto(
  crypto: CryptoService(random: SecureRandom()),
  random: SecureRandom(),
);
final lanTransferService = LanTransferService(
  backupService: BackupService(
    repository: repository,
    vaultService: vaultService,
  ),
  server: LanTransferServer(crypto: lanTransferCrypto),
  client: LanTransferClient(crypto: lanTransferCrypto),
);
```

Pass `lanTransferService` into `AppServices`.

- [ ] **Step 6: Run Task 5 tests**

Run:

```powershell
flutter test test/core/lan_sync/lan_transfer_service_test.dart test/app/app_services_test.dart -r compact
```

If `test/app/app_services_test.dart` does not exist, use:

```powershell
flutter test test/features/generator_settings_test.dart -r compact
```

Expected: service tests pass and App route compile errors are resolved.

- [ ] **Step 7: Commit Task 5**

```powershell
git add lib/core/lan_sync lib/app lib/main.dart test/core/lan_sync test/features/generator_settings_test.dart
git commit -m "feat: wire LAN transfer service"
```

## Task 6: LAN Exchange UI and Internationalization

**Files:**
- Create: `lib/features/lan_sync/lan_sync_page.dart`
- Create: `lib/features/lan_sync/lan_send_page.dart`
- Create: `lib/features/lan_sync/lan_receive_page.dart`
- Modify: `lib/features/settings/settings_page.dart`
- Modify: `lib/shared/i18n/app_strings.dart`
- Modify: `lib/shared/i18n/app_strings_zh.dart`
- Modify: `lib/shared/i18n/app_strings_en.dart`
- Modify: `pubspec.yaml`
- Create: `test/features/lan_sync_page_test.dart`
- Modify: `test/features/generator_settings_test.dart`
- Modify: `test/ui/visual_system_test.dart`

- [ ] **Step 1: Add QR dependencies**

Run:

```powershell
flutter pub add qr_flutter mobile_scanner
```

Expected: `pubspec.yaml` and `pubspec.lock` update successfully. If the command fails due to network download, retry at most two more times. Stop after three consecutive failures.

- [ ] **Step 2: Write failing widget tests**

Create `test/features/lan_sync_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_service.dart';
import 'package:secure_box/data/models/password_entry.dart';

void main() {
  testWidgets('settings opens LAN send flow and creates QR session', (tester) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: '',
          tags: const ['dev'],
        ),
      ],
      createLanSendSessionOverride: ({
        required itemIds,
        required includeBlobs,
        required includeHistory,
        required senderName,
      }) async {
        return LanTransferSession(
          qrPayload: LanTransferQrPayload(
            host: '127.0.0.1',
            port: 49152,
            sessionId: 'session-1',
            token: 'token-value',
            transferKey: 'transfer-key-value',
            packageSha256: 'a' * 64,
            selectedCount: itemIds.length,
            expiresAt: DateTime.utc(2099, 1, 1),
            senderName: senderName,
          ),
          expiresAt: DateTime.utc(2099, 1, 1),
        );
      },
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    services.navigatorKey.currentState!.pushNamed(AppServices.routeSettings);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-lan-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lan-send-page')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lan-send-item-item-1')));
    await tester.tap(find.byKey(const ValueKey('lan-send-create-session')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lan-send-qr')), findsOneWidget);
    expect(find.textContaining('secret-password'), findsNothing);
  });
}
```

Add this receive-flow test in the same file:

```dart
testWidgets('receive flow imports accepted entries and hides source password', (tester) async {
  String? submittedSourcePassword;
  final payload = LanTransferQrPayload(
    host: '127.0.0.1',
    port: 49152,
    sessionId: 'session-1',
    token: 'token-value',
    transferKey: 'transfer-key-value',
    packageSha256: 'a' * 64,
    selectedCount: 2,
    expiresAt: DateTime.utc(2099, 1, 1),
    senderName: 'Source phone',
  );
  final services = AppServices.fake(
    hasVault: true,
    unlocked: true,
    receiveLanTransferOverride: ({
      required payload,
      required sourceMasterPassword,
    }) async {
      submittedSourcePassword = sourceMasterPassword;
      return const LanTransferImportResult(
        importedCount: 1,
        skippedCount: 1,
        conflicts: [
          LanTransferConflict(
            title: 'GitHub',
            website: 'https://github.com',
            username: 'user@example.com',
            reason: LanTransferConflictReason.existingLocalEntry,
          ),
        ],
      );
    },
  );

  await tester.pumpWidget(SecureBoxApp(services: services));
  await tester.pumpAndSettle();
  services.navigatorKey.currentState!.pushNamed(AppServices.routeLanReceive);
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const ValueKey('lan-receive-paste-field')),
    payload.encode(),
  );
  await tester.tap(find.byKey(const ValueKey('lan-receive-use-pasted-payload')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('lan-source-master-password-field')),
    'source-master',
  );
  await tester.tap(find.byKey(const ValueKey('lan-receive-import-button')));
  await tester.pumpAndSettle();

  expect(submittedSourcePassword, 'source-master');
  expect(find.textContaining('source-master'), findsNothing);
  expect(find.byKey(const ValueKey('lan-import-result')), findsOneWidget);
  expect(find.textContaining('GitHub'), findsOneWidget);
});
```

- [ ] **Step 3: Run RED widget tests**

Run:

```powershell
flutter test test/features/lan_sync_page_test.dart test/features/generator_settings_test.dart test/ui/visual_system_test.dart -r compact
```

Expected: fail because LAN UI and dependency imports are not implemented.

- [ ] **Step 4: Add i18n keys**

Add keys in both language files:

- `lanExchangeTitle`
- `lanExchangeSubtitle`
- `lanSendData`
- `lanSendDataSubtitle`
- `lanReceiveData`
- `lanReceiveDataSubtitle`
- `lanSelectRecords`
- `lanSearchRecords`
- `lanIncludeAttachments`
- `lanIncludePasswordHistory`
- `lanPasswordHistoryRisk`
- `lanCreateQr`
- `lanQrReady`
- `lanQrExpires`
- `lanCancelSession`
- `lanScanQr`
- `lanPasteQrPayload`
- `lanSourceMasterPassword`
- `lanSourceMasterPasswordSubtitle`
- `lanImporting`
- `lanImportComplete`
- `lanImportedCount`
- `lanSkippedCount`
- `lanConflicts`
- `lanConflictExisting`
- `lanConflictDuplicate`
- `lanQrExpired`
- `lanNetworkUnavailable`
- `lanSessionUnavailable`
- `lanPackageIntegrityFailed`
- `lanSourcePasswordWrong`
- `lanLocalVaultLocked`
- `lanNoRecordsSelected`

Do not hardcode visible strings in the new widgets.

- [ ] **Step 5: Implement settings entry page**

In `settings_page.dart`, add the LAN section after encrypted backup or before migration:

- `settings-section-lan-sync` section title from `lanExchangeTitle`.
- `settings-lan-send` tile pushes `AppServices.routeLanSend`.
- `settings-lan-receive` tile pushes `AppServices.routeLanReceive`.

`LanSyncPage` can be used for a two-button entry route if settings needs a full page; settings tiles should still direct to send/receive directly for fewer taps.

- [ ] **Step 6: Implement sender UI**

`LanSendPage` behavior:

- Load `services.listVaultItems()` on init.
- Search client-side using title, website, username, and tags.
- Show stable row keys `lan-send-item-<id>`.
- Multi-select entries.
- Toggle `includeBlobs`, default true.
- Toggle `includeHistory`, default false, with risk text visible only when enabled.
- Disable create session until at least one entry is selected.
- On create, call `services.createLanSendSession`.
- Display QR with `QrImageView(data: session.qrPayload.encode())` and key `lan-send-qr`.
- Display selected count, sender host, expiry countdown, and cancel button.
- Cancel calls `services.cancelLanSendSession()` and returns to selection state.

- [ ] **Step 7: Implement receiver UI**

`LanReceivePage` behavior:

- Default tab uses `MobileScanner` and parses barcode text through `LanTransferQrPayload.decode`.
- Provide a manual paste fallback with key `lan-receive-paste-field` for desktop/tests.
- After payload validation, show source master-password dialog with visibility toggle.
- Call `services.receiveLanTransfer(payload: payload, sourceMasterPassword: password)`.
- Display result counts and conflict list with title, website, username, reason.
- Clear the source master-password controller before leaving the dialog.
- Do not render source password, imported password, TOTP secret, notes, or attachment content.

- [ ] **Step 8: Run Task 6 tests**

Run:

```powershell
flutter test test/features/lan_sync_page_test.dart test/features/generator_settings_test.dart test/ui/visual_system_test.dart -r compact
```

Expected: pass.

- [ ] **Step 9: Commit Task 6**

```powershell
git add pubspec.yaml pubspec.lock lib/features/lan_sync lib/features/settings lib/shared/i18n test/features test/ui
git commit -m "feat: add LAN exchange UI"
```

## Task 7: Android Permissions and Manual Test Plan

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `test/android_integration_test.dart`
- Create: `docs/manual-lan-sync-test-plan-2026-05-25.md`

- [ ] **Step 1: Write failing Android permission test**

Update `test/android_integration_test.dart`:

```dart
test('manifest declares biometric, LAN network, and camera permissions', () {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  expect(manifest, contains('android.permission.USE_BIOMETRIC'));
  expect(manifest, contains('android.permission.INTERNET'));
  expect(manifest, contains('android.permission.CAMERA'));
});
```

Also update release merged manifest assertions to expect `android.permission.CAMERA`.

- [ ] **Step 2: Run RED Android test**

Run:

```powershell
flutter test test/android_integration_test.dart -r compact
```

Expected: fail because `CAMERA` permission is not declared yet.

- [ ] **Step 3: Add camera permission**

Add this line to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
```

Keep these existing controls:

- `android.permission.USE_BIOMETRIC`
- `android.permission.INTERNET`
- `android:allowBackup="false"`
- `android:fullBackupContent="false"`

- [ ] **Step 4: Write manual LAN test plan**

Create `docs/manual-lan-sync-test-plan-2026-05-25.md` with these sections:

- Preconditions: two devices on same LAN, both with unlocked Lockly vaults.
- P0-01: send one selected password without conflict.
- P0-02: wrong sender master password imports nothing.
- P0-03: one local conflict is skipped and not overwritten.
- P0-04: package duplicate skips second incoming item.
- P0-05: attachment included by default.
- P0-06: attachment excluded when sender toggles it off.
- P0-07: old QR/session cannot be reused.
- P0-08: app background/auto-lock cancels sender session.
- P0-09: receiver vault remains unlockable with receiver master password.
- P1-01: network unavailable shows retryable message.
- P1-02: language switch updates LAN text.

- [ ] **Step 5: Run Task 7 tests**

Run:

```powershell
flutter test test/android_integration_test.dart -r compact
```

Expected: pass.

- [ ] **Step 6: Commit Task 7**

```powershell
git add android/app/src/main/AndroidManifest.xml test/android_integration_test.dart docs/manual-lan-sync-test-plan-2026-05-25.md
git commit -m "test: document LAN sync manual flow"
```

## Task 8: Final Verification and Review Closure

**Files:**
- Inspect: all modified files in `Lockly`
- Create only defect fixes found by verification

- [ ] **Step 1: Run dependency and static checks**

Run:

```powershell
flutter pub get
flutter analyze
```

Expected:

- `flutter pub get` succeeds.
- `flutter analyze` prints `No issues found!`.

- [ ] **Step 2: Run focused tests**

Run:

```powershell
flutter test test/core/lan_sync test/core/backup/backup_service_test.dart test/features/lan_sync_page_test.dart test/features/generator_settings_test.dart test/features/security_center_test.dart test/ui/visual_system_test.dart test/android_integration_test.dart --timeout 10m -r compact
```

Expected: all tests pass.

- [ ] **Step 3: Run full Flutter test suite**

Run:

```powershell
flutter test --timeout 10m -r compact
```

Expected: all tests pass.

- [ ] **Step 4: Run cloud-removal grep**

Run:

```powershell
rg -n "LOCKLY_SYNC_BASE_URL|SyncService|SyncApiClient|SyncCredentialStore|SyncStateDao|settings-cloud|cloudSync|CloudSync|core/sync|emergency_access|backend account|cloud account" lib test docs/manual-lan-sync-test-plan-2026-05-25.md
```

Expected: no matches. If docs mention historical cloud plans under `docs/superpowers` or older manual cloud docs, leave those historical docs unchanged; the grep scope above excludes those docs.

- [ ] **Step 5: Run secret rendering grep**

Run:

```powershell
rg -n "print\\(|debugPrint\\(|developer\\.log|sourceMasterPassword|secret-password|totp-secret|attachment plaintext" lib/core/lan_sync lib/features/lan_sync test/core/lan_sync test/features/lan_sync_page_test.dart
```

Expected:

- No `print`, `debugPrint`, or `developer.log` in LAN implementation.
- Test fixtures may contain `secret-password` or `totp-secret`; production `lib/core/lan_sync` and `lib/features/lan_sync` must not contain fixture secrets.
- Variables named `sourceMasterPassword` are allowed only as parameters/controllers and must not be logged or rendered after submission.

- [ ] **Step 6: Dispatch review subagents**

Use `superpowers:subagent-driven-development` or the available multi-agent tool to dispatch two independent reviews:

- Reviewer A: UI/UX and localization review for `lib/features/lan_sync`, `settings_page.dart`, `security_center_page.dart`, and i18n files.
- Reviewer B: security/crypto review for `core/lan_sync`, `backup_service.dart`, `vault_service.dart`, and tests.

Ask both reviewers to report warning-or-higher issues only. Fix every valid warning-or-higher issue, then rerun Steps 1 through 5.

- [ ] **Step 7: Commit review fixes**

If review fixes were made:

```powershell
git add lib test docs android pubspec.yaml pubspec.lock
git commit -m "fix: close LAN sync review findings"
```

If no fixes were made, do not create an empty commit.

- [ ] **Step 8: Final status**

Run:

```powershell
git status --short --branch
git log --oneline -5
```

Expected:

- Worktree is clean.
- Latest commits include the LAN selective sync implementation and review-fix commit when applicable.

Report to the user:

- Changed scope stayed inside `Lockly`.
- Cloud sync App surface is removed in this branch.
- LAN sender/receiver selective exchange is implemented.
- Verification commands and results.
- Any manual device test still requiring the user’s phone.
