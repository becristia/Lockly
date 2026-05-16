# Device Rollback Anchor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a platform secure-storage vault anchor that detects whole-database rollback, and tighten DEK/plaintext cleanup on lock and failure paths.

**Architecture:** Introduce a small vault anchor model, secure-storage-backed store, and service under `lib/core/vault/`. `VaultService` verifies the encrypted manifest first, then compares the accepted manifest against the anchor before unlocking or mutating state. Session-owned DEK buffers are explicitly zeroed and tests prove the behavior.

**Tech Stack:** Flutter/Dart, `flutter_secure_storage`, `cryptography` SHA-256, existing SQLite DAOs, existing `VaultService`, `VaultManifestService`, and Flutter test suite.

---

## File Structure

- Create `lib/core/vault/vault_anchor.dart`
  - Immutable non-secret model for secure-storage anchor state.
- Create `lib/core/vault/vault_anchor_store.dart`
  - `VaultAnchorStore` interface, `SecureStorageVaultAnchorStore`, and `MemoryVaultAnchorStore` for tests.
- Create `lib/core/vault/vault_anchor_service.dart`
  - Digest, comparison, missing-anchor policy, and generic anchor exceptions.
- Modify `lib/core/vault/vault_service.dart`
  - Inject and call `VaultAnchorService` after manifest verification and after manifest rewrites.
- Modify `lib/main.dart`
  - Wire production secure-storage anchor store into `VaultService`.
- Modify `lib/core/vault/vault_session.dart`
  - Keep current zeroing behavior and expose a test-only way to prove lock clears copied session bytes without leaking production API.
- Modify `lib/core/biometric/biometric_service.dart`
  - Zero temporary DEK copies after biometric enable/read result construction where ownership is clear.
- Modify `lib/core/backup/backup_service.dart`
  - Ensure backup import paths that rewrite manifests also update the anchor through `VaultService`.
- Test `test/core/vault/vault_anchor_service_test.dart`
  - Unit tests for anchor digest, missing anchor, rollback, mismatch, and malformed anchor handling.
- Test `test/core/vault/vault_service_anchor_test.dart`
  - Integration tests for create/unlock/biometric/mutation/clear behavior.
- Modify `test/core/vault/vault_service_test.dart`
  - Add or adjust session DEK zeroing tests if easier to keep with existing vault tests.
- Modify `docs/security-check.md`
  - Document rollback-anchor verification and latest test count.

## Task 1: Anchor Model, Store, and Service

**Files:**
- Create: `lib/core/vault/vault_anchor.dart`
- Create: `lib/core/vault/vault_anchor_store.dart`
- Create: `lib/core/vault/vault_anchor_service.dart`
- Test: `test/core/vault/vault_anchor_service_test.dart`

- [ ] **Step 1: Write failing anchor service tests**

Create `test/core/vault/vault_anchor_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/vault/vault_anchor.dart';
import 'package:secure_box/core/vault/vault_anchor_service.dart';
import 'package:secure_box/core/vault/vault_anchor_store.dart';
import 'package:secure_box/data/models/vault_manifest.dart';

void main() {
  VaultManifest manifest({int epoch = 1, int counter = 1, String mac = 'mac'}) {
    return VaultManifest(
      version: 1,
      epoch: epoch,
      counter: counter,
      nonce: 'nonce',
      ciphertext: 'ciphertext',
      mac: mac,
      updatedAt: 1760000000000 + counter,
    );
  }

  test('writeAcceptedManifest stores non-secret manifest anchor', () async {
    final store = MemoryVaultAnchorStore();
    final service = VaultAnchorService(store: store);

    await service.writeAcceptedManifest(
      vaultId: 'vault-1',
      manifest: manifest(counter: 2),
      updatedAt: 1760000001000,
    );

    final anchor = await store.read(vaultId: 'vault-1');
    expect(anchor, isNotNull);
    expect(anchor!.vaultId, 'vault-1');
    expect(anchor.schemaVersion, 1);
    expect(anchor.manifestEpoch, 1);
    expect(anchor.manifestCounter, 2);
    expect(anchor.manifestDigest, isNot(contains('ciphertext')));
    expect(anchor.manifestDigest, isNot(contains('mac')));
  });

  test('verifyAgainstAnchor accepts matching manifest', () async {
    final store = MemoryVaultAnchorStore();
    final service = VaultAnchorService(store: store);
    final current = manifest(counter: 3);
    await service.writeAcceptedManifest(
      vaultId: 'vault-1',
      manifest: current,
      updatedAt: 1760000003000,
    );

    final result = await service.verifyAgainstAnchor(
      vaultId: 'vault-1',
      manifest: current,
    );

    expect(result, VaultAnchorVerificationResult.matched);
  });

  test('verifyAgainstAnchor reports missing anchor without throwing', () async {
    final service = VaultAnchorService(store: MemoryVaultAnchorStore());

    final result = await service.verifyAgainstAnchor(
      vaultId: 'vault-1',
      manifest: manifest(),
    );

    expect(result, VaultAnchorVerificationResult.missing);
  });

  test('verifyAgainstAnchor rejects rollback to lower counter', () async {
    final store = MemoryVaultAnchorStore();
    final service = VaultAnchorService(store: store);
    await service.writeAcceptedManifest(
      vaultId: 'vault-1',
      manifest: manifest(counter: 5),
      updatedAt: 1760000005000,
    );

    expect(
      () => service.verifyAgainstAnchor(
        vaultId: 'vault-1',
        manifest: manifest(counter: 4),
      ),
      throwsA(isA<VaultAnchorException>()),
    );
  });

  test('verifyAgainstAnchor rejects same counter digest mismatch', () async {
    final store = MemoryVaultAnchorStore();
    final service = VaultAnchorService(store: store);
    await service.writeAcceptedManifest(
      vaultId: 'vault-1',
      manifest: manifest(counter: 5),
      updatedAt: 1760000005000,
    );

    expect(
      () => service.verifyAgainstAnchor(
        vaultId: 'vault-1',
        manifest: manifest(counter: 5, mac: 'different-mac'),
      ),
      throwsA(isA<VaultAnchorException>()),
    );
  });

  test('deleteAnchor removes stored anchor', () async {
    final store = MemoryVaultAnchorStore();
    final service = VaultAnchorService(store: store);
    await service.writeAcceptedManifest(
      vaultId: 'vault-1',
      manifest: manifest(),
      updatedAt: 1760000000000,
    );

    await service.deleteAnchor(vaultId: 'vault-1');

    expect(await store.read(vaultId: 'vault-1'), isNull);
  });

  test('VaultAnchor rejects malformed schema version', () {
    expect(
      () => VaultAnchor.fromJson({
        'vault_id': 'vault-1',
        'schema_version': 2,
        'manifest_epoch': 1,
        'manifest_counter': 1,
        'manifest_digest': 'digest',
        'updated_at': 1760000000000,
      }),
      throwsFormatException,
    );
  });
}
```

- [ ] **Step 2: Run the anchor tests and verify they fail**

Run:

```bash
flutter test --reporter compact test/core/vault/vault_anchor_service_test.dart
```

Expected: FAIL because `VaultAnchor`, `VaultAnchorService`, and `MemoryVaultAnchorStore` do not exist.

- [ ] **Step 3: Add `VaultAnchor` model**

Create `lib/core/vault/vault_anchor.dart`:

```dart
class VaultAnchor {
  const VaultAnchor({
    required this.vaultId,
    required this.schemaVersion,
    required this.manifestEpoch,
    required this.manifestCounter,
    required this.manifestDigest,
    required this.updatedAt,
  });

  static const currentSchemaVersion = 1;

  final String vaultId;
  final int schemaVersion;
  final int manifestEpoch;
  final int manifestCounter;
  final String manifestDigest;
  final int updatedAt;

  Map<String, Object?> toJson() {
    return {
      'vault_id': vaultId,
      'schema_version': schemaVersion,
      'manifest_epoch': manifestEpoch,
      'manifest_counter': manifestCounter,
      'manifest_digest': manifestDigest,
      'updated_at': updatedAt,
    };
  }

  factory VaultAnchor.fromJson(Map<String, Object?> json) {
    final schemaVersion = _readRequiredInt(json, 'schema_version');
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('Invalid vault anchor schema version');
    }
    final manifestEpoch = _readRequiredInt(json, 'manifest_epoch');
    final manifestCounter = _readRequiredInt(json, 'manifest_counter');
    if (manifestEpoch < 1 || manifestCounter < 1) {
      throw const FormatException('Invalid vault anchor manifest position');
    }

    return VaultAnchor(
      vaultId: _readRequiredString(json, 'vault_id'),
      schemaVersion: schemaVersion,
      manifestEpoch: manifestEpoch,
      manifestCounter: manifestCounter,
      manifestDigest: _readRequiredString(json, 'manifest_digest'),
      updatedAt: _readRequiredInt(json, 'updated_at'),
    );
  }

  static String _readRequiredString(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! String || value.isEmpty) {
      throw FormatException('Invalid "$field": expected a non-empty string');
    }
    return value;
  }

  static int _readRequiredInt(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! int) {
      throw FormatException('Invalid "$field": expected an int');
    }
    return value;
  }
}
```

- [ ] **Step 4: Add anchor store implementations**

Create `lib/core/vault/vault_anchor_store.dart`:

```dart
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:secure_box/core/vault/vault_anchor.dart';

abstract class VaultAnchorStore {
  Future<VaultAnchor?> read({required String vaultId});

  Future<void> write(VaultAnchor anchor);

  Future<void> delete({required String vaultId});
}

class SecureStorageVaultAnchorStore implements VaultAnchorStore {
  SecureStorageVaultAnchorStore({
    FlutterSecureStorage? storage,
    AndroidOptions androidOptions = _defaultAndroidOptions,
  }) : _storage = storage ?? FlutterSecureStorage(aOptions: androidOptions),
       _androidOptions = androidOptions;

  static const _keyPrefix = 'vault_anchor_';
  static const _defaultAndroidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    storageNamespace: 'secure_box_vault_anchor',
    resetOnError: true,
  );

  final FlutterSecureStorage _storage;
  final AndroidOptions _androidOptions;

  @override
  Future<VaultAnchor?> read({required String vaultId}) async {
    final value = await _storage.read(
      key: _keyFor(vaultId),
      aOptions: _androidOptions,
    );
    if (value == null) {
      return null;
    }

    final decoded = jsonDecode(value);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Invalid vault anchor JSON');
    }

    return VaultAnchor.fromJson(Map<String, Object?>.from(decoded));
  }

  @override
  Future<void> write(VaultAnchor anchor) {
    return _storage.write(
      key: _keyFor(anchor.vaultId),
      value: jsonEncode(anchor.toJson()),
      aOptions: _androidOptions,
    );
  }

  @override
  Future<void> delete({required String vaultId}) {
    return _storage.delete(key: _keyFor(vaultId), aOptions: _androidOptions);
  }

  String _keyFor(String vaultId) => '$_keyPrefix$vaultId';
}

class MemoryVaultAnchorStore implements VaultAnchorStore {
  final Map<String, VaultAnchor> _anchors = {};

  @override
  Future<VaultAnchor?> read({required String vaultId}) async {
    return _anchors[vaultId];
  }

  @override
  Future<void> write(VaultAnchor anchor) async {
    _anchors[anchor.vaultId] = anchor;
  }

  @override
  Future<void> delete({required String vaultId}) async {
    _anchors.remove(vaultId);
  }
}
```

- [ ] **Step 5: Add anchor service**

Create `lib/core/vault/vault_anchor_service.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:secure_box/core/crypto/encoding.dart';
import 'package:secure_box/core/vault/vault_anchor.dart';
import 'package:secure_box/core/vault/vault_anchor_store.dart';
import 'package:secure_box/data/models/vault_manifest.dart';

enum VaultAnchorVerificationResult { matched, missing }

class VaultAnchorException implements Exception {
  const VaultAnchorException([this.message = 'Vault anchor check failed']);

  final String message;

  @override
  String toString() => 'VaultAnchorException: $message';
}

class VaultAnchorService {
  VaultAnchorService({required VaultAnchorStore store}) : _store = store;

  final VaultAnchorStore _store;
  final Sha256 _sha256 = Sha256();

  Future<VaultAnchorVerificationResult> verifyAgainstAnchor({
    required String vaultId,
    required VaultManifest manifest,
  }) async {
    final VaultAnchor? anchor;
    try {
      anchor = await _store.read(vaultId: vaultId);
    } on Exception {
      throw const VaultAnchorException();
    }
    if (anchor == null) {
      return VaultAnchorVerificationResult.missing;
    }

    if (anchor.vaultId != vaultId ||
        anchor.schemaVersion != VaultAnchor.currentSchemaVersion) {
      throw const VaultAnchorException();
    }
    if (_isManifestOlderThanAnchor(manifest: manifest, anchor: anchor)) {
      throw const VaultAnchorException();
    }
    if (manifest.epoch == anchor.manifestEpoch &&
        manifest.counter == anchor.manifestCounter) {
      final digest = await digestManifest(manifest);
      if (digest != anchor.manifestDigest) {
        throw const VaultAnchorException();
      }
    }

    return VaultAnchorVerificationResult.matched;
  }

  Future<void> writeAcceptedManifest({
    required String vaultId,
    required VaultManifest manifest,
    required int updatedAt,
  }) async {
    final anchor = VaultAnchor(
      vaultId: vaultId,
      schemaVersion: VaultAnchor.currentSchemaVersion,
      manifestEpoch: manifest.epoch,
      manifestCounter: manifest.counter,
      manifestDigest: await digestManifest(manifest),
      updatedAt: updatedAt,
    );
    try {
      await _store.write(anchor);
    } on Exception {
      throw const VaultAnchorException();
    }
  }

  Future<void> deleteAnchor({required String vaultId}) async {
    try {
      await _store.delete(vaultId: vaultId);
    } on Exception {
      throw const VaultAnchorException();
    }
  }

  Future<String> digestManifest(VaultManifest manifest) async {
    final canonical = jsonEncode({
      'ciphertext': manifest.ciphertext,
      'counter': manifest.counter,
      'epoch': manifest.epoch,
      'mac': manifest.mac,
      'nonce': manifest.nonce,
      'updated_at': manifest.updatedAt,
      'version': manifest.version,
    });
    final digest = await _sha256.hash(utf8.encode(canonical));
    return b64(Uint8List.fromList(digest.bytes));
  }

  bool _isManifestOlderThanAnchor({
    required VaultManifest manifest,
    required VaultAnchor anchor,
  }) {
    if (manifest.epoch < anchor.manifestEpoch) {
      return true;
    }
    if (manifest.epoch > anchor.manifestEpoch) {
      return false;
    }
    return manifest.counter < anchor.manifestCounter;
  }
}
```

- [ ] **Step 6: Format and run anchor tests**

Run:

```bash
dart format lib/core/vault/vault_anchor.dart lib/core/vault/vault_anchor_store.dart lib/core/vault/vault_anchor_service.dart test/core/vault/vault_anchor_service_test.dart
flutter test --reporter compact test/core/vault/vault_anchor_service_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit Task 1**

```bash
git add lib/core/vault/vault_anchor.dart lib/core/vault/vault_anchor_store.dart lib/core/vault/vault_anchor_service.dart test/core/vault/vault_anchor_service_test.dart
git commit -m "feat: add vault rollback anchor service"
```

## Task 2: Wire Anchor Into Vault Creation and Unlock

**Files:**
- Modify: `lib/core/vault/vault_service.dart`
- Modify: `lib/main.dart`
- Test: `test/core/vault/vault_service_anchor_test.dart`

- [ ] **Step 1: Write failing creation and unlock tests**

Create `test/core/vault/vault_service_anchor_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/vault/vault_anchor_service.dart';
import 'package:secure_box/core/vault/vault_anchor_store.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_manifest_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<_Harness> buildHarness() async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final anchorStore = MemoryVaultAnchorStore();
    final service = VaultService(
      repository: VaultRepository(
        metaDao: VaultMetaDao(db),
        itemsDao: VaultItemsDao(db),
        manifestDao: VaultManifestDao(db),
        settingsDao: SettingsDao(db),
      ),
      random: SecureRandom(),
      kdf: KdfService(),
      crypto: CryptoService(random: SecureRandom()),
      anchorService: VaultAnchorService(store: anchorStore),
    );
    return _Harness(service: service, anchorStore: anchorStore);
  }

  test('createVault writes anchor for initial manifest', () async {
    final harness = await buildHarness();

    await harness.service.createVault(masterPassword: 'master-passphrase');

    final meta = await harness.service.repository.metaDao.get();
    final anchor = await harness.anchorStore.read(vaultId: meta!.id);
    final manifest = await harness.service.repository.manifestDao.get();
    expect(anchor, isNotNull);
    expect(anchor!.manifestEpoch, manifest!.epoch);
    expect(anchor.manifestCounter, manifest.counter);
  });

  test('master unlock succeeds when anchor matches', () async {
    final harness = await buildHarness();
    await harness.service.createVault(masterPassword: 'master-passphrase');
    harness.service.lock();

    final session = await harness.service.unlock(
      masterPassword: 'master-passphrase',
    );

    expect(session.isUnlocked, isTrue);
  });

  test('master unlock rejects database rollback below anchor counter', () async {
    final harness = await buildHarness();
    await harness.service.createVault(masterPassword: 'master-passphrase');
    final meta = await harness.service.repository.metaDao.get();
    final manifest = await harness.service.repository.manifestDao.get();
    await VaultAnchorService(
      store: harness.anchorStore,
    ).writeAcceptedManifest(
      vaultId: meta!.id,
      manifest: manifest!.copyWith(counter: manifest.counter + 1),
      updatedAt: manifest.updatedAt + 1,
    );

    await expectLater(
      harness.service.unlock(masterPassword: 'master-passphrase'),
      throwsA(isA<VaultIntegrityException>()),
    );
    expect(harness.service.isUnlocked, isFalse);
  });

  test('master unlock recreates missing anchor after manifest verification', () async {
    final harness = await buildHarness();
    await harness.service.createVault(masterPassword: 'master-passphrase');
    final meta = await harness.service.repository.metaDao.get();
    await harness.anchorStore.delete(vaultId: meta!.id);
    harness.service.lock();

    await harness.service.unlock(masterPassword: 'master-passphrase');

    expect(await harness.anchorStore.read(vaultId: meta.id), isNotNull);
  });

  test('biometric unlock fails when anchor is missing', () async {
    final harness = await buildHarness();
    final biometric = BiometricService(
      authenticator: FakeBiometricAuthenticator(
        canAuthenticate: true,
        succeeds: true,
      ),
      store: MemorySecureDekStore(),
    );
    await harness.service.createVault(masterPassword: 'master-passphrase');
    await harness.service.enableBiometricUnlock(
      masterPassword: 'master-passphrase',
      biometricService: biometric,
    );
    final meta = await harness.service.repository.metaDao.get();
    await harness.anchorStore.delete(vaultId: meta!.id);
    harness.service.lock();

    final unlocked = await harness.service.unlockWithBiometrics(
      biometricService: biometric,
    );

    expect(unlocked, isFalse);
    expect(harness.service.isUnlocked, isFalse);
    expect(await harness.anchorStore.read(vaultId: meta.id), isNull);
  });
}

class _Harness {
  _Harness({required this.service, required this.anchorStore});

  final VaultService service;
  final MemoryVaultAnchorStore anchorStore;
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
flutter test --reporter compact test/core/vault/vault_service_anchor_test.dart
```

Expected: FAIL because `VaultService` has no `anchorService` parameter and does not write or verify anchors.

- [ ] **Step 3: Add `anchorService` dependency to `VaultService`**

In `lib/core/vault/vault_service.dart`, add imports:

```dart
import 'package:secure_box/core/vault/vault_anchor_service.dart';
import 'package:secure_box/core/vault/vault_anchor_store.dart';
```

Update constructor fields:

```dart
VaultService({
  required VaultRepository repository,
  required SecureRandom random,
  required KdfService kdf,
  required CryptoService crypto,
  VaultSession? session,
  VaultManifestService? manifestService,
  VaultAnchorService? anchorService,
}) : repository = repository,
     _random = random,
     _kdf = kdf,
     _crypto = crypto,
     _session = session ?? VaultSession(),
     _manifestService =
         manifestService ?? VaultManifestService(crypto: crypto),
     _anchorService =
         anchorService ??
         VaultAnchorService(store: MemoryVaultAnchorStore());

final VaultAnchorService _anchorService;
```

The memory fallback is acceptable for tests that instantiate `VaultService` directly. Production wiring in `main.dart` will provide secure storage.

- [ ] **Step 4: Add anchor helper methods to `VaultService`**

In `VaultService`, add helpers near manifest helpers:

```dart
Future<void> _verifyAnchorForManifest({
  required VaultMeta meta,
  required VaultManifest manifest,
  required bool allowMissingAnchor,
}) async {
  final result = await _anchorService.verifyAgainstAnchor(
    vaultId: meta.id,
    manifest: manifest,
  );
  if (result == VaultAnchorVerificationResult.missing && !allowMissingAnchor) {
    throw const VaultIntegrityException();
  }
}

Future<void> _writeAnchorForManifest({
  required VaultMeta meta,
  required VaultManifest manifest,
}) {
  return _anchorService.writeAcceptedManifest(
    vaultId: meta.id,
    manifest: manifest,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

Future<void> _deleteAnchorForMeta(VaultMeta? meta) async {
  if (meta == null) {
    return;
  }
  await _anchorService.deleteAnchor(vaultId: meta.id);
}
```

Wrap calls to `_anchorService` in existing `try` blocks so `VaultAnchorException` is normalized to `VaultIntegrityException` at public boundaries.

- [ ] **Step 5: Write anchor on `createVault`**

In `createVault`, after the transaction returns the saved manifest and before session unlock is accepted, write the anchor. If `createVault` currently returns `void`, use a local variable:

```dart
VaultMeta? createdMeta;
VaultManifest? createdManifest;
await repository.transaction((txn) async {
  ...
  createdMeta = meta;
  createdManifest = manifest;
});

try {
  await _writeAnchorForManifest(
    meta: createdMeta!,
    manifest: createdManifest!,
  );
  _session.unlock(dek);
} catch (_) {
  _session.lock();
  rethrow;
} finally {
  dek.fillRange(0, dek.length, 0);
}
```

If existing `createVault` already unlocks during creation, preserve current UX but ensure anchor write happens before marking the session usable.

- [ ] **Step 6: Verify anchor on master unlock**

In `unlock`, after `_manifestService.verifyManifest(...)` succeeds and before `_session.unlock(dek)`, add:

```dart
await _verifyAnchorForManifest(
  meta: meta,
  manifest: manifest,
  allowMissingAnchor: true,
);
await _writeAnchorForManifest(meta: meta, manifest: manifest);
```

Catch `VaultAnchorException` and throw `VaultIntegrityException`. Missing anchor is allowed only here because master password is the recovery path.

- [ ] **Step 7: Verify anchor on biometric unlock**

In `unlockWithBiometrics`, after manifest verification and before `_session.unlock(dek)`, add:

```dart
await _verifyAnchorForManifest(
  meta: meta,
  manifest: manifest,
  allowMissingAnchor: false,
);
```

Do not write a missing anchor from biometric unlock. If anchor verification fails, lock and return `false`, matching existing biometric failure behavior.

- [ ] **Step 8: Wire production anchor store**

In `lib/main.dart`, add imports:

```dart
import 'package:secure_box/core/vault/vault_anchor_service.dart';
import 'package:secure_box/core/vault/vault_anchor_store.dart';
```

When constructing `VaultService`, pass:

```dart
anchorService: VaultAnchorService(store: SecureStorageVaultAnchorStore()),
```

- [ ] **Step 9: Format and run anchor integration tests**

Run:

```bash
dart format lib/core/vault/vault_service.dart lib/main.dart test/core/vault/vault_service_anchor_test.dart
flutter test --reporter compact test/core/vault/vault_service_anchor_test.dart
flutter test --reporter compact test/core/vault/vault_service_test.dart
```

Expected: PASS.

- [ ] **Step 10: Commit Task 2**

```bash
git add lib/core/vault/vault_service.dart lib/main.dart test/core/vault/vault_service_anchor_test.dart
git commit -m "feat: verify vault anchor on unlock"
```

## Task 3: Update Anchor on Mutations, Biometric Metadata, Imports, and Clear

**Files:**
- Modify: `lib/core/vault/vault_service.dart`
- Modify: `lib/core/backup/backup_service.dart`
- Modify: `lib/app/app_services.dart`
- Test: `test/core/vault/vault_service_anchor_test.dart`
- Test: `test/core/backup/backup_service_test.dart`

- [ ] **Step 1: Add failing mutation and clear tests**

Append to `test/core/vault/vault_service_anchor_test.dart`:

```dart
import 'package:secure_box/data/models/password_entry.dart';

PasswordEntry _entry(String title) {
  return PasswordEntry(
    title: title,
    website: 'https://example.test',
    username: 'user@example.test',
    password: 'secret-password',
    notes: 'private note',
    tags: const ['tag'],
  );
}

test('item mutations update anchor counter after manifest rewrite', () async {
  final harness = await buildHarness();
  await harness.service.createVault(masterPassword: 'master-passphrase');
  await harness.service.unlock(masterPassword: 'master-passphrase');
  final meta = await harness.service.repository.metaDao.get();

  final id = await harness.service.createItem(_entry('One'));
  final afterCreate = await harness.anchorStore.read(vaultId: meta!.id);
  final manifestAfterCreate = await harness.service.repository.manifestDao.get();
  expect(afterCreate!.manifestCounter, manifestAfterCreate!.counter);

  await harness.service.updateItem(id, _entry('Two'));
  final afterUpdate = await harness.anchorStore.read(vaultId: meta.id);
  final manifestAfterUpdate = await harness.service.repository.manifestDao.get();
  expect(afterUpdate!.manifestCounter, manifestAfterUpdate!.counter);

  await harness.service.deleteItem(id);
  final afterDelete = await harness.anchorStore.read(vaultId: meta.id);
  final manifestAfterDelete = await harness.service.repository.manifestDao.get();
  expect(afterDelete!.manifestCounter, manifestAfterDelete!.counter);
});

test('item mutation rejects rollback before writing new data', () async {
  final harness = await buildHarness();
  await harness.service.createVault(masterPassword: 'master-passphrase');
  await harness.service.unlock(masterPassword: 'master-passphrase');
  final meta = await harness.service.repository.metaDao.get();
  final manifest = await harness.service.repository.manifestDao.get();
  await VaultAnchorService(
    store: harness.anchorStore,
  ).writeAcceptedManifest(
    vaultId: meta!.id,
    manifest: manifest!.copyWith(counter: manifest.counter + 2),
    updatedAt: manifest.updatedAt + 2,
  );

  await expectLater(
    harness.service.createItem(_entry('Blocked')),
    throwsA(isA<VaultIntegrityException>()),
  );
  expect(await harness.service.repository.itemsDao.rawRowsForTest(), isEmpty);
  expect(harness.service.isUnlocked, isFalse);
});

test('clearLocalVault deletes anchor state', () async {
  final harness = await buildHarness();
  await harness.service.createVault(masterPassword: 'master-passphrase');
  final meta = await harness.service.repository.metaDao.get();
  expect(await harness.anchorStore.read(vaultId: meta!.id), isNotNull);

  await harness.service.clearLocalVault();

  expect(await harness.anchorStore.read(vaultId: meta.id), isNull);
});
```

`VaultService.clearLocalVault()` does not exist before this task, so this test should fail until Step 6 adds it.

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
flutter test --reporter compact test/core/vault/vault_service_anchor_test.dart
```

Expected: FAIL because mutation and clear paths do not update/delete anchors yet.

- [ ] **Step 3: Verify anchor before mutation rewrite**

In `VaultService._rewriteManifestForMutation`, after reading and verifying the previous manifest and before calling the mutation action, add:

```dart
await _verifyAnchorForManifest(
  meta: meta,
  manifest: previous,
  allowMissingAnchor: false,
);
```

If verification fails, lock and throw `VaultIntegrityException` before writing item data.

- [ ] **Step 4: Write anchor after mutation transaction commits**

Change `_rewriteManifestForMutation` so it returns both the mutation result and the new manifest/meta needed for anchor update. A small private result type is enough:

```dart
class _ManifestMutationResult<T> {
  const _ManifestMutationResult({
    required this.value,
    required this.meta,
    required this.manifest,
  });

  final T value;
  final VaultMeta meta;
  final VaultManifest manifest;
}
```

After the repository transaction completes:

```dart
final mutation = await repository.transaction((txn) async {
  ...
  await txn.manifestDao.save(manifest);
  return _ManifestMutationResult(
    value: value,
    meta: meta,
    manifest: manifest,
  );
});
try {
  await _writeAnchorForManifest(meta: mutation.meta, manifest: mutation.manifest);
  return mutation.value;
} on VaultAnchorException {
  _session.lock();
  throw const VaultIntegrityException();
}
```

- [ ] **Step 5: Update anchor after biometric metadata and password rotation**

In `enableBiometricUnlock`, `disableBiometricUnlock`, and `changeMasterPassword`, identify the existing point where a new manifest is saved. After successful transaction commit, call:

```dart
await _writeAnchorForManifest(meta: updatedMeta, manifest: updatedManifest);
```

Use the same fail-closed rule: if the anchor write fails, lock and throw `VaultIntegrityException`.

- [ ] **Step 6: Add a VaultService clear helper**

First add DAO clear methods.

In `lib/data/db/vault_items_dao.dart`:

```dart
Future<void> deleteAll() async {
  await _db.delete('vault_items');
}
```

In `lib/data/db/vault_meta_dao.dart`:

```dart
Future<void> deleteAll() async {
  await _db.delete('vault_meta');
}
```

In `lib/data/db/settings_dao.dart`:

```dart
Future<void> deleteAll() async {
  await _db.delete('settings');
}
```

Then add `VaultService.clearLocalVault()`:

```dart
Future<void> clearLocalVault() async {
  final meta = await repository.metaDao.get();
  await repository.transaction((txn) async {
    await txn.itemsDao.deleteAll();
    await txn.manifestDao.deleteAll();
    await txn.metaDao.deleteAll();
    await txn.settingsDao.deleteAll();
  });
  await _deleteAnchorForMeta(meta);
  _session.lock();
}
```

Then modify `AppServices.clearLocalVault()` to delegate to `vaultService.clearLocalVault()` instead of manually clearing only SQLite and biometric state. Preserve biometric disable behavior:

```dart
await _biometricService?.disable();
await vaultService.clearLocalVault();
```

- [ ] **Step 7: Update backup import anchor handling**

In `BackupService.importBackup`, every path that calls `_rewriteManifestAfterImport` or writes a restored manifest must update the anchor. Prefer adding a `VaultService.acceptManifestForCurrentState(...)` method rather than making `BackupService` know about anchors:

```dart
Future<void> acceptManifestForCurrentState({
  required VaultMeta meta,
  required VaultManifest manifest,
}) {
  return _writeAnchorForManifest(meta: meta, manifest: manifest);
}
```

Call it after the import transaction succeeds and only when target data changed:

```dart
await vaultService.acceptManifestForCurrentState(
  meta: targetMeta,
  manifest: rewrittenManifest,
);
```

For overwrite imports that replace the target meta, use the imported/sanitized target meta and the newly created target manifest.

- [ ] **Step 8: Run focused tests**

Run:

```bash
dart format lib/core/vault/vault_service.dart lib/core/backup/backup_service.dart lib/app/app_services.dart lib/data/db/vault_items_dao.dart lib/data/db/vault_meta_dao.dart lib/data/db/settings_dao.dart test/core/vault/vault_service_anchor_test.dart test/core/backup/backup_service_test.dart
flutter test --reporter compact test/core/vault/vault_service_anchor_test.dart
flutter test --reporter compact test/core/backup/backup_service_test.dart
flutter test --reporter compact test/app/app_routing_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit Task 3**

```bash
git add lib/core/vault/vault_service.dart lib/core/backup/backup_service.dart lib/app/app_services.dart lib/data/db/vault_items_dao.dart lib/data/db/vault_meta_dao.dart lib/data/db/settings_dao.dart test/core/vault/vault_service_anchor_test.dart test/core/backup/backup_service_test.dart test/app/app_routing_test.dart
git commit -m "feat: maintain vault anchor across mutations"
```

## Task 4: Tighten DEK and Plaintext Lifetime

**Files:**
- Modify: `lib/core/vault/vault_session.dart`
- Modify: `lib/core/biometric/biometric_service.dart`
- Modify: `lib/core/vault/vault_service.dart`
- Modify: `lib/features/vault_detail/vault_detail_page.dart`
- Modify: `lib/features/vault_edit/vault_edit_page.dart`
- Test: `test/core/vault/vault_session_test.dart`
- Test: `test/core/biometric/biometric_service_test.dart`
- Test: existing feature tests if UI cleanup is testable without brittle internals.

- [ ] **Step 1: Write failing VaultSession zeroing tests**

Create `test/core/vault/vault_session_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/vault/vault_session.dart';

void main() {
  test('unlock copies caller DEK and lock zeroes session-owned bytes', () {
    final session = VaultSession();
    final callerDek = Uint8List.fromList(List<int>.filled(32, 7));

    session.unlock(callerDek);
    callerDek.fillRange(0, callerDek.length, 9);
    final sessionCopyBeforeLock = session.debugCopyDekForTest();
    expect(sessionCopyBeforeLock, List<int>.filled(32, 7));

    session.lock();

    expect(session.debugLastZeroedDekForTest, List<int>.filled(32, 0));
    expect(session.isUnlocked, isFalse);
  });

  test('withDekCopy zeroes temporary copy after action completes', () async {
    final session = VaultSession();
    session.unlock(Uint8List.fromList(List<int>.filled(32, 3)));
    Uint8List? actionCopy;

    await session.withDekCopy((dek) async {
      actionCopy = dek;
    });

    expect(actionCopy, List<int>.filled(32, 0));
  });
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
flutter test --reporter compact test/core/vault/vault_session_test.dart
```

Expected: FAIL because test-only debug accessors do not exist.

- [ ] **Step 3: Add test-only session inspection without exposing production secrets**

In `lib/core/vault/vault_session.dart`, import foundation:

```dart
import 'package:flutter/foundation.dart';
```

Add field and debug getters:

```dart
Uint8List? _lastZeroedDekForTest;

@visibleForTesting
Uint8List debugCopyDekForTest() {
  return _copyDek();
}

@visibleForTesting
Uint8List? get debugLastZeroedDekForTest {
  final value = _lastZeroedDekForTest;
  return value == null ? null : Uint8List.fromList(value);
}
```

Update `lock()`:

```dart
void lock() {
  final dek = _dek;
  if (dek != null) {
    dek.fillRange(0, dek.length, 0);
    assert(() {
      _lastZeroedDekForTest = Uint8List.fromList(dek);
      return true;
    }());
  }
  _dek = null;
}
```

Keep all test-only access behind `@visibleForTesting`. Do not add logs.

- [ ] **Step 4: Zero biometric temporary DEK copies**

In `BiometricService.enable`, write a copy and zero it after the store call:

```dart
final copy = Uint8List.fromList(dek);
try {
  await store.writeDek(copy);
} finally {
  copy.fillRange(0, copy.length, 0);
}
```

In `BiometricService.unlock`, after `BiometricUnlockResult.unlocked(dek)`, zero the `dek` returned by the store:

```dart
final result = BiometricUnlockResult.unlocked(dek);
dek.fillRange(0, dek.length, 0);
return result;
```

This preserves the result-owned copy while clearing the store-read temporary.

- [ ] **Step 5: Add biometric zeroing test**

Append to `test/core/biometric/biometric_service_test.dart` using a custom store:

```dart
test('unlock zeroes store-returned DEK after copying result', () async {
  final returnedDek = Uint8List.fromList(List<int>.filled(32, 4));
  final service = BiometricService(
    authenticator: FakeBiometricAuthenticator(
      canAuthenticate: true,
      succeeds: true,
    ),
    store: _SingleReadDekStore(returnedDek),
  );

  final result = await service.unlock();

  expect(result.status, BiometricUnlockStatus.unlocked);
  expect(result.dek, List<int>.filled(32, 4));
  expect(returnedDek, List<int>.filled(32, 0));
});

class _SingleReadDekStore implements SecureDekStore {
  _SingleReadDekStore(this.dek);

  final Uint8List dek;

  @override
  SecureDekReadRequirement get readRequirement =>
      SecureDekReadRequirement.explicitBiometricAuthentication;

  @override
  Future<bool> canUseBiometricProtection() async => true;

  @override
  Future<void> deleteDek() async {}

  @override
  Future<Uint8List?> readDek() async => dek;

  @override
  Future<void> writeDek(Uint8List dek) async {}
}
```

- [ ] **Step 6: Clear temporary DEKs in VaultService `finally` blocks**

Review `VaultService` methods that assign local `Uint8List? dek` or `sourceDek`. For every local buffer owned by the method and not passed into `_session.unlock` as the session-owned copy, add:

```dart
finally {
  dek?.fillRange(0, dek.length, 0);
}
```

Do this in:

- `createVault`
- `unlock`
- `unlockWithBiometrics`
- `enableBiometricUnlock`
- `changeMasterPassword`
- `verifyBackupManifest`
- backup/import helper methods that decrypt a source DEK

Avoid zeroing a buffer before an awaited operation that still needs it. When `_session.unlock(dek)` is called, it copies the DEK, so the local `dek` can be zeroed immediately after.

- [ ] **Step 7: Clear UI sensitive state on dispose**

In `lib/features/vault_detail/vault_detail_page.dart`, ensure `dispose()` clears any loaded entry and revealed-password flag:

```dart
@override
void dispose() {
  _entry = null;
  _passwordRevealed = false;
  super.dispose();
}
```

Use the actual state field names present in the file.

In `lib/features/vault_edit/vault_edit_page.dart`, update `dispose()` to clear sensitive controllers before disposal:

```dart
_passwordController.clear();
_usernameController.clear();
_notesController.clear();
```

Then dispose all controllers as it already does. Use actual field names.

- [ ] **Step 8: Run focused lifetime tests**

Run:

```bash
dart format lib/core/vault/vault_session.dart lib/core/biometric/biometric_service.dart lib/core/vault/vault_service.dart lib/features/vault_detail/vault_detail_page.dart lib/features/vault_edit/vault_edit_page.dart test/core/vault/vault_session_test.dart test/core/biometric/biometric_service_test.dart
flutter test --reporter compact test/core/vault/vault_session_test.dart
flutter test --reporter compact test/core/biometric/biometric_service_test.dart
flutter test --reporter compact test/features/vault_item_flow_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit Task 4**

```bash
git add lib/core/vault/vault_session.dart lib/core/biometric/biometric_service.dart lib/core/vault/vault_service.dart lib/features/vault_detail/vault_detail_page.dart lib/features/vault_edit/vault_edit_page.dart test/core/vault/vault_session_test.dart test/core/biometric/biometric_service_test.dart test/features/vault_item_flow_test.dart
git commit -m "fix: tighten vault plaintext lifetime"
```

## Task 5: Documentation and Final Verification

**Files:**
- Modify: `docs/security-check.md`

- [ ] **Step 1: Run full verification**

Run:

```bash
flutter test --reporter compact
flutter analyze
rg -n "MD5|SHA1|sha1|sha256\\(|print\\(|debugPrint\\(|log\\(|password|masterPassword|secret" lib test
rg -n "CREATE TABLE vault_items|CREATE TABLE vault_manifest|username|password|notes|title|vault_anchor|anchor" lib/data/db lib/data/models lib/core/vault
rg -n "android.permission.INTERNET" android
```

Expected:

- `flutter test --reporter compact`: PASS.
- `flutter analyze`: No issues found.
- No MD5/SHA1 usage.
- `sha256` only appears in approved KDF/HKDF/digest/anchor contexts.
- Sensitive names appear only in code parameters, UI controllers, and tests, not logs or SQLite columns.
- No plaintext anchor table is added to SQLite.
- No Android internet permission.

- [ ] **Step 2: Update security check documentation**

Update `docs/security-check.md`:

```markdown
- `flutter test --reporter compact` passed after device rollback anchor hardening: <actual test count> tests.
- `flutter analyze` passed: no issues found.
- Vault rollback anchor is stored in platform secure storage and contains only vault id, manifest epoch/counter, manifest digest, schema version, and timestamp.
- Master-password unlock can recreate a missing anchor only after encrypted manifest verification succeeds.
- Biometric unlock requires an existing matching anchor and falls back to master password if the anchor is missing or invalid.
- Whole-database rollback below the platform anchor counter fails closed.
- `VaultSession.lock()` zeroes session-owned DEK bytes before dropping the reference, and temporary DEK copies are zeroed where ownership is clear.
```

Use the actual test count from the full test output.

- [ ] **Step 3: Run docs diff review**

Run:

```bash
git diff -- docs/security-check.md
```

Expected: Diff only documents the new anchor and plaintext lifetime verification.

- [ ] **Step 4: Commit Task 5**

```bash
git add docs/security-check.md
git commit -m "docs: update rollback anchor security check"
```

## Final Branch Verification

- [ ] **Step 1: Confirm branch status**

Run:

```bash
git status --short --branch
```

Expected: clean working tree on the feature branch.

- [ ] **Step 2: Run final verification before review**

Run:

```bash
flutter test --reporter compact
flutter analyze
```

Expected: all tests pass and analyzer reports no issues.

- [ ] **Step 3: Request code review**

Use `superpowers:requesting-code-review`. The review must specifically inspect:

- Anchor missing behavior for master unlock versus biometric unlock.
- Anchor update order after manifest rewrites.
- Whole-database rollback test realism.
- No new plaintext sensitive persistence.
- DEK zeroing correctness without zeroing buffers before awaited consumers finish.

## Self-Review

- Spec coverage: Task 1 creates anchor primitives. Task 2 covers create/unlock/biometric missing-anchor policy. Task 3 covers mutations, biometric metadata, imports, and clear. Task 4 covers DEK/plaintext lifetime. Task 5 covers docs and final verification.
- Placeholder scan: no placeholder markers or unspecified test steps remain. DAO clear methods are named explicitly.
- Type consistency: `VaultAnchor`, `VaultAnchorStore`, `MemoryVaultAnchorStore`, `SecureStorageVaultAnchorStore`, `VaultAnchorService`, `VaultAnchorVerificationResult`, and `VaultAnchorException` are introduced before later tasks reference them.
