# Vault Manifest Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add DEK-authenticated vault manifest checks so Secure Box detects local SQLite tampering, local rollback-like row replacement, and corrupt backup payloads.

**Architecture:** Add a singleton `vault_manifest` table and a focused `VaultManifestService` that derives a manifest key from the DEK, computes canonical digests over `vault_meta` and encrypted `vault_items`, and encrypts/authenticates the manifest payload. `VaultService` verifies the manifest before unlocking or returning decrypted data, rewrites it inside the same transaction as protected mutations, and upgrades legacy v1 vaults only after successful master-password unlock. `BackupService` exports version 2 backups with the manifest and keeps importing version 1 backups by generating a new target manifest.

**Tech Stack:** Flutter/Dart, sqflite, `cryptography` AES-GCM and HKDF/HMAC-SHA256 APIs, existing `CryptoService`, `VaultRepository`, `VaultMetaDao`, `VaultItemsDao`, and `flutter_test`.

---

## File Structure

- Create `lib/data/models/vault_manifest.dart`: DB row model plus encrypted payload model for the singleton manifest.
- Create `lib/data/db/vault_manifest_dao.dart`: save/get/delete singleton manifest rows.
- Modify `lib/data/db/app_database.dart`: bump schema version to 2, create `vault_manifest`, add `onUpgrade` from 1 to 2.
- Modify `lib/core/vault/vault_repository.dart`: include `VaultManifestDao` in repository construction and transaction cloning.
- Create `lib/core/vault/vault_manifest_service.dart`: canonical digest generation, HKDF manifest key derivation, manifest encrypt/verify/rewrite helpers.
- Modify `lib/core/vault/vault_service.dart`: manifest creation, verification, legacy upgrade, CRUD mutation rewrites, master-password rotation rewrite, and generic `VaultIntegrityException`.
- Modify `lib/core/backup/backup_service.dart`: backup version 2 with `magic`, `created_at`, `item_count`, and `manifest`; v1 compatibility path.
- Modify existing tests in `test/data/db/vault_database_test.dart`, `test/core/vault/vault_service_test.dart`, and `test/core/backup/backup_service_test.dart`.
- Update `docs/security-check.md` after implementation verification.

---

### Task 1: Schema, Model, DAO

**Files:**
- Create: `lib/data/models/vault_manifest.dart`
- Create: `lib/data/db/vault_manifest_dao.dart`
- Modify: `lib/data/db/app_database.dart`
- Modify: `lib/core/vault/vault_repository.dart`
- Test: `test/data/db/vault_database_test.dart`

- [ ] **Step 1: Write failing database tests**

Add tests in `test/data/db/vault_database_test.dart`:

```dart
test('schema version 2 creates vault_manifest table without plaintext fields', () async {
  final db = await AppDatabase.openInMemory();
  addTearDown(db.close);

  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'vault_manifest'",
  );
  expect(tables, hasLength(1));

  final columns = await db.rawQuery('PRAGMA table_info(vault_manifest)');
  final names = columns.map((row) => row['name']).toSet();
  expect(names, containsAll(<String>{
    'singleton_key',
    'version',
    'epoch',
    'counter',
    'nonce',
    'ciphertext',
    'mac',
    'updated_at',
  }));
  expect(names, isNot(contains('password')));
  expect(names, isNot(contains('username')));
  expect(names, isNot(contains('notes')));
  expect(names, isNot(contains('title')));
});

test('vault manifest dao stores exactly one singleton row', () async {
  final db = await AppDatabase.openInMemory();
  addTearDown(db.close);
  final dao = VaultManifestDao(db);

  await dao.save(
    const VaultManifest(
      version: 1,
      epoch: 1,
      counter: 1,
      nonce: 'nonce-a',
      ciphertext: 'ciphertext-a',
      mac: 'mac-a',
      updatedAt: 10,
    ),
  );
  await dao.save(
    const VaultManifest(
      version: 1,
      epoch: 1,
      counter: 2,
      nonce: 'nonce-b',
      ciphertext: 'ciphertext-b',
      mac: 'mac-b',
      updatedAt: 20,
    ),
  );

  final manifest = await dao.get();
  expect(manifest, isNotNull);
  expect(manifest!.counter, 2);
  expect(manifest.ciphertext, 'ciphertext-b');
});
```

Expected imports:

```dart
import 'package:secure_box/data/db/vault_manifest_dao.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```powershell
flutter test --reporter compact test/data/db/vault_database_test.dart
```

Expected: FAIL because `VaultManifest`, `VaultManifestDao`, and `vault_manifest` do not exist.

- [ ] **Step 3: Add manifest model**

Create `lib/data/models/vault_manifest.dart`:

```dart
import 'package:secure_box/data/db/app_database.dart';

class VaultManifest {
  const VaultManifest({
    required this.version,
    required this.epoch,
    required this.counter,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.updatedAt,
  });

  final int version;
  final int epoch;
  final int counter;
  final String nonce;
  final String ciphertext;
  final String mac;
  final int updatedAt;

  Map<String, Object?> toDb() => {
    'singleton_key': AppDatabase.vaultManifestSingletonKey,
    'version': version,
    'epoch': epoch,
    'counter': counter,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
    'updated_at': updatedAt,
  };

  factory VaultManifest.fromDb(Map<String, Object?> row) {
    return VaultManifest(
      version: _readRequiredInt(row, 'version'),
      epoch: _readRequiredInt(row, 'epoch'),
      counter: _readRequiredInt(row, 'counter'),
      nonce: _readRequiredString(row, 'nonce'),
      ciphertext: _readRequiredString(row, 'ciphertext'),
      mac: _readRequiredString(row, 'mac'),
      updatedAt: _readRequiredInt(row, 'updated_at'),
    );
  }

  VaultManifest copyWith({
    int? version,
    int? epoch,
    int? counter,
    String? nonce,
    String? ciphertext,
    String? mac,
    int? updatedAt,
  }) {
    return VaultManifest(
      version: version ?? this.version,
      epoch: epoch ?? this.epoch,
      counter: counter ?? this.counter,
      nonce: nonce ?? this.nonce,
      ciphertext: ciphertext ?? this.ciphertext,
      mac: mac ?? this.mac,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

int _readRequiredInt(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value is! int) {
    throw FormatException('Invalid "$field": expected an int');
  }
  return value;
}

String _readRequiredString(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value is! String) {
    throw FormatException('Invalid "$field": expected a string');
  }
  return value;
}
```

- [ ] **Step 4: Add DAO and schema**

Create `lib/data/db/vault_manifest_dao.dart`:

```dart
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:sqflite/sqflite.dart';

class VaultManifestDao {
  VaultManifestDao(this._db);

  final DatabaseExecutor _db;

  DatabaseExecutor get executor => _db;

  Future<void> save(VaultManifest manifest) async {
    await _db.insert(
      'vault_manifest',
      manifest.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<VaultManifest?> get() async {
    final rows = await _db.query('vault_manifest', limit: 2);
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      throw StateError('Expected at most one vault_manifest row');
    }
    return VaultManifest.fromDb(rows.single);
  }

  Future<void> deleteAll() async {
    await _db.delete('vault_manifest');
  }
}
```

Modify `lib/data/db/app_database.dart`:

```dart
static const int schemaVersion = 2;
static const int vaultManifestSingletonKey = 1;
```

Add table creation to `onCreate`:

```dart
await _createVaultManifestTable(db);
```

Add `onUpgrade` and helper:

```dart
onUpgrade: (db, oldVersion, newVersion) async {
  if (oldVersion < 2) {
    await _createVaultManifestTable(db);
  }
},
```

```dart
static Future<void> _createVaultManifestTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE vault_manifest (
      singleton_key INTEGER NOT NULL DEFAULT 1
        CHECK (singleton_key = $vaultManifestSingletonKey)
        UNIQUE,
      version INTEGER NOT NULL,
      epoch INTEGER NOT NULL,
      counter INTEGER NOT NULL,
      nonce TEXT NOT NULL,
      ciphertext TEXT NOT NULL,
      mac TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
}
```

Modify `lib/core/vault/vault_repository.dart` to include the DAO:

```dart
import 'package:secure_box/data/db/vault_manifest_dao.dart';
```

```dart
required this.manifestDao,
```

```dart
final VaultManifestDao manifestDao;
```

Include `manifestDao.executor` in `_inferDatabase`, and clone it inside `transaction`:

```dart
manifestDao: VaultManifestDao(txn),
```

Update all test harness repository construction sites to pass `manifestDao: VaultManifestDao(db)`.

- [ ] **Step 5: Run focused tests**

Run:

```powershell
flutter test --reporter compact test/data/db/vault_database_test.dart
```

Expected: PASS.

- [ ] **Step 6: Format and commit**

Run:

```powershell
dart format lib/data/models/vault_manifest.dart lib/data/db/vault_manifest_dao.dart lib/data/db/app_database.dart lib/core/vault/vault_repository.dart test/data/db/vault_database_test.dart
git add lib/data/models/vault_manifest.dart lib/data/db/vault_manifest_dao.dart lib/data/db/app_database.dart lib/core/vault/vault_repository.dart test/data/db/vault_database_test.dart
git commit -m "feat: add vault manifest storage"
```

---

### Task 2: Manifest Crypto Service

**Files:**
- Create: `lib/core/vault/vault_manifest_service.dart`
- Test: `test/core/vault/vault_manifest_service_test.dart`

- [ ] **Step 1: Write failing service tests**

Create `test/core/vault/vault_manifest_service_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/vault_meta.dart';

void main() {
  test('manifest service creates and verifies a manifest for encrypted state', () async {
    final service = VaultManifestService(
      crypto: CryptoService(random: SecureRandom()),
    );
    final dek = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final meta = _meta();
    final items = [_item(id: 'b'), _item(id: 'a')];

    final manifest = await service.createManifest(
      dek: dek,
      meta: meta,
      items: items,
      previous: null,
      updatedAt: 100,
    );

    expect(manifest.version, 1);
    expect(manifest.epoch, 1);
    expect(manifest.counter, 1);
    await service.verifyManifest(
      dek: dek,
      meta: meta,
      items: items.reversed.toList(),
      manifest: manifest,
    );
  });

  test('manifest verification rejects tampered item ciphertext', () async {
    final service = VaultManifestService(
      crypto: CryptoService(random: SecureRandom()),
    );
    final dek = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final meta = _meta();
    final item = _item(id: 'a');
    final manifest = await service.createManifest(
      dek: dek,
      meta: meta,
      items: [item],
      previous: null,
      updatedAt: 100,
    );

    expect(
      () => service.verifyManifest(
        dek: dek,
        meta: meta,
        items: [item.copyWith(ciphertext: 'tampered-ciphertext')],
        manifest: manifest,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
  });
}

VaultMeta _meta() {
  final params = KdfParams.argon2id(memoryKiB: 1024);
  return VaultMeta(
    id: 'vault-id',
    version: 2,
    kdf: params.name,
    kdfParams: params,
    salt: 'salt',
    encryptedDekByMaster: 'encrypted-dek',
    encryptedDekByMasterNonce: 'dek-nonce',
    encryptedDekByMasterMac: 'dek-mac',
    biometricEnabled: false,
    createdAt: 1,
    updatedAt: 2,
  );
}

EncryptedVaultItem _item({required String id}) {
  return EncryptedVaultItem(
    id: id,
    nonce: 'nonce-$id',
    ciphertext: 'ciphertext-$id',
    mac: 'mac-$id',
    createdAt: 10,
    updatedAt: 20,
  );
}
```

If `EncryptedVaultItem.copyWith` does not exist, add the tampered item by constructing a second `EncryptedVaultItem` with the same fields and changed `ciphertext`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
flutter test --reporter compact test/core/vault/vault_manifest_service_test.dart
```

Expected: FAIL because `VaultManifestService` and `VaultIntegrityException` do not exist.

- [ ] **Step 3: Implement service**

Create `lib/core/vault/vault_manifest_service.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/encoding.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:secure_box/data/models/vault_meta.dart';

class VaultIntegrityException implements Exception {
  const VaultIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'VaultIntegrityException: $message';
}

class VaultManifestService {
  VaultManifestService({required CryptoService crypto}) : _crypto = crypto;

  static const int manifestVersion = 1;
  static const String _hkdfInfo = 'secure-box:vault-manifest:v1';

  final CryptoService _crypto;

  Future<VaultManifest> createManifest({
    required Uint8List dek,
    required VaultMeta meta,
    required List<EncryptedVaultItem> items,
    required VaultManifest? previous,
    required int updatedAt,
  }) async {
    final payload = _buildPayload(
      meta: meta,
      items: items,
      epoch: previous?.epoch ?? 1,
      counter: (previous?.counter ?? 0) + 1,
    );
    final key = await _deriveManifestKey(dek);
    try {
      final encrypted = await _crypto.encryptBytes(
        key: key,
        plaintext: utf8.encode(jsonEncode(payload)),
      );
      return VaultManifest(
        version: manifestVersion,
        epoch: payload['epoch']! as int,
        counter: payload['counter']! as int,
        nonce: b64(encrypted.nonce),
        ciphertext: b64(encrypted.ciphertext),
        mac: b64(encrypted.mac),
        updatedAt: updatedAt,
      );
    } finally {
      _zeroBytes(key);
    }
  }

  Future<void> verifyManifest({
    required Uint8List dek,
    required VaultMeta meta,
    required List<EncryptedVaultItem> items,
    required VaultManifest manifest,
  }) async {
    if (manifest.version != manifestVersion) {
      throw const VaultIntegrityException('Vault integrity check failed');
    }
    final key = await _deriveManifestKey(dek);
    try {
      final clearBytes = await _crypto.decryptBytes(
        key: key,
        payload: EncryptedPayload(
          nonce: fromB64(manifest.nonce),
          ciphertext: fromB64(manifest.ciphertext),
          mac: fromB64(manifest.mac),
        ),
      );
      final decoded = jsonDecode(utf8.decode(clearBytes));
      if (decoded is! Map<Object?, Object?>) {
        throw const VaultIntegrityException('Vault integrity check failed');
      }
      final actual = Map<String, Object?>.from(decoded);
      final expected = _buildPayload(
        meta: meta,
        items: items,
        epoch: manifest.epoch,
        counter: manifest.counter,
      );
      if (jsonEncode(_canonicalize(actual)) != jsonEncode(_canonicalize(expected))) {
        throw const VaultIntegrityException('Vault integrity check failed');
      }
    } on CryptoException {
      throw const VaultIntegrityException('Vault integrity check failed');
    } on FormatException {
      throw const VaultIntegrityException('Vault integrity check failed');
    } finally {
      _zeroBytes(key);
    }
  }

  Map<String, Object?> _buildPayload({
    required VaultMeta meta,
    required List<EncryptedVaultItem> items,
    required int epoch,
    required int counter,
  }) {
    final activeCount = items.where((item) => item.deletedAt == null).length;
    final deletedCount = items.length - activeCount;
    return {
      'version': manifestVersion,
      'vault_id': meta.id,
      'epoch': epoch,
      'counter': counter,
      'kdf': meta.kdf,
      'kdf_params_digest': _digestJson(meta.kdfParams.toJson()),
      'encrypted_dek_digest': _digestJson({
        'encrypted_dek_by_master': meta.encryptedDekByMaster,
        'encrypted_dek_by_master_nonce': meta.encryptedDekByMasterNonce,
        'encrypted_dek_by_master_mac': meta.encryptedDekByMasterMac,
        'salt': meta.salt,
      }),
      'active_item_count': activeCount,
      'deleted_item_count': deletedCount,
      'items_digest': _digestJson(
        items.map(_itemDescriptor).toList(growable: false),
      ),
    };
  }

  Map<String, Object?> _itemDescriptor(EncryptedVaultItem item) => {
    'id': item.id,
    'nonce': item.nonce,
    'ciphertext': item.ciphertext,
    'mac': item.mac,
    'created_at': item.createdAt,
    'updated_at': item.updatedAt,
    'deleted_at': item.deletedAt,
  };

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final sorted = <String, Object?>{};
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      for (final key in keys) {
        sorted[key] = _canonicalize(value[key]);
      }
      return sorted;
    }
    if (value is List) {
      final canonicalItems = value.map(_canonicalize).toList(growable: false);
      canonicalItems.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
      return canonicalItems;
    }
    return value;
  }

  String _digestJson(Object? value) {
    final bytes = utf8.encode(jsonEncode(_canonicalize(value)));
    final digest = cryptography.Sha256().hashSync(bytes);
    return b64(Uint8List.fromList(digest.bytes));
  }

  Future<Uint8List> _deriveManifestKey(Uint8List dek) async {
    final hkdf = cryptography.Hkdf(
      hmac: cryptography.Hmac.sha256(),
      outputLength: 32,
    );
    final key = await hkdf.deriveKey(
      secretKey: cryptography.SecretKey(dek),
      info: utf8.encode(_hkdfInfo),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  void _zeroBytes(Uint8List? bytes) {
    if (bytes == null) {
      return;
    }
    bytes.fillRange(0, bytes.length, 0);
  }
}
```

If `cryptography.Sha256().hashSync` is unavailable in the installed version, replace `_digestJson` with the package's async `hash` API and make callers await it. Keep the service API async.

- [ ] **Step 4: Run focused tests**

Run:

```powershell
dart format lib/core/vault/vault_manifest_service.dart test/core/vault/vault_manifest_service_test.dart
flutter test --reporter compact test/core/vault/vault_manifest_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```powershell
git add lib/core/vault/vault_manifest_service.dart test/core/vault/vault_manifest_service_test.dart
git commit -m "feat: add vault manifest service"
```

---

### Task 3: Vault Creation, Unlock Verification, Legacy Upgrade

**Files:**
- Modify: `lib/core/vault/vault_service.dart`
- Modify: test harnesses that construct `VaultService`
- Test: `test/core/vault/vault_service_test.dart`
- Test: `test/core/biometric/biometric_service_test.dart`

- [ ] **Step 1: Write failing vault tests**

Add tests in `test/core/vault/vault_service_test.dart`:

```dart
test('new vault creates a manifest and unlock verifies it', () async {
  final service = await buildService();
  await service.createVault(masterPassword: 'master-passphrase');

  final manifest = await service.repository.manifestDao.get();
  expect(manifest, isNotNull);
  expect(manifest!.counter, 1);

  final session = await service.unlock(masterPassword: 'master-passphrase');
  expect(session.isUnlocked, isTrue);
});

test('unlock fails closed when manifest item digest is invalid', () async {
  final service = await buildService();
  await service.createVault(masterPassword: 'master-passphrase');
  await service.unlock(masterPassword: 'master-passphrase');

  final id = await service.createItem(
    PasswordEntry(
      title: 'GitHub',
      website: 'https://github.com',
      username: 'user@example.com',
      password: 'secret-password',
      notes: 'private note',
      tags: ['dev'],
    ),
  );
  service.lock();

  final item = await service.repository.itemsDao.byId(id);
  await service.repository.itemsDao.upsert(
    EncryptedVaultItem(
      id: item!.id,
      nonce: item.nonce,
      ciphertext: 'tampered-ciphertext',
      mac: item.mac,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      deletedAt: item.deletedAt,
    ),
  );

  expect(
    () => service.unlock(masterPassword: 'master-passphrase'),
    throwsA(isA<VaultIntegrityException>()),
  );
  expect(service.isUnlocked, isFalse);
});

test('legacy vault without manifest upgrades after master password unlock', () async {
  final service = await buildService();
  await _createLegacyVaultWithoutManifest(
    service,
    masterPassword: 'legacy-master',
  );

  expect(await service.repository.manifestDao.get(), isNull);

  final session = await service.unlock(masterPassword: 'legacy-master');
  expect(session.isUnlocked, isTrue);
  expect(await service.repository.manifestDao.get(), isNotNull);
});
```

Add helper using the existing PBKDF2 fixture style already present in `vault_service_test.dart`; save only `vault_meta` and no manifest.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```powershell
flutter test --reporter compact test/core/vault/vault_service_test.dart
```

Expected: FAIL because `VaultService` does not create or verify manifests.

- [ ] **Step 3: Wire manifest service into VaultService**

Modify `VaultService` constructor:

```dart
VaultManifestService? manifestService,
```

and field:

```dart
final VaultManifestService _manifestService;
```

initialize:

```dart
_manifestService = manifestService ?? VaultManifestService(crypto: crypto),
```

In `createVault`, inside the existing transaction, save `meta`, then create manifest:

```dart
final manifest = await _manifestService.createManifest(
  dek: dek,
  meta: meta,
  items: const [],
  previous: null,
  updatedAt: now,
);
await txn.metaDao.save(meta);
await txn.manifestDao.save(manifest);
await txn.settingsDao.setValue('clipboard_clear_seconds', '30');
```

In `unlock`, after decrypting DEK and before `_session.unlock(dek)`:

```dart
await _verifyOrUpgradeManifestAfterMasterUnlock(meta: meta, dek: dek);
```

Add helpers:

```dart
Future<void> _verifyOrUpgradeManifestAfterMasterUnlock({
  required VaultMeta meta,
  required Uint8List dek,
}) async {
  final manifest = await repository.manifestDao.get();
  final items = await repository.itemsDao.allItemsForManifest();
  if (manifest == null) {
    final now = DateTime.now().millisecondsSinceEpoch;
    await repository.transaction((txn) async {
      final freshMeta = await txn.metaDao.get();
      if (freshMeta == null) {
        throw StateError('Vault has not been created');
      }
      final freshItems = await txn.itemsDao.allItemsForManifest();
      final created = await _manifestService.createManifest(
        dek: dek,
        meta: freshMeta,
        items: freshItems,
        previous: null,
        updatedAt: now,
      );
      await txn.manifestDao.save(created);
    });
    return;
  }
  await _manifestService.verifyManifest(
    dek: dek,
    meta: meta,
    items: items,
    manifest: manifest,
  );
}
```

Add `VaultItemsDao.allItemsForManifest()`:

```dart
Future<List<EncryptedVaultItem>> allItemsForManifest() async {
  final rows = await _db.query('vault_items', orderBy: 'id ASC');
  return rows.map(EncryptedVaultItem.fromDb).toList(growable: false);
}
```

Update `unlockWithBiometrics` to fail closed if no manifest exists:

```dart
final manifest = await repository.manifestDao.get();
if (manifest == null) {
  _session.lock();
  return false;
}
await _manifestService.verifyManifest(
  dek: dek,
  meta: meta,
  items: await repository.itemsDao.allItemsForManifest(),
  manifest: manifest,
);
```

- [ ] **Step 4: Run focused tests**

Run:

```powershell
dart format lib/core/vault/vault_service.dart lib/data/db/vault_items_dao.dart test/core/vault/vault_service_test.dart
flutter test --reporter compact test/core/vault/vault_service_test.dart test/core/biometric/biometric_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```powershell
git add lib/core/vault/vault_service.dart lib/data/db/vault_items_dao.dart test/core/vault/vault_service_test.dart test/core/biometric/biometric_service_test.dart
git commit -m "feat: verify vault manifest on unlock"
```

---

### Task 4: Manifest Rewrites for Protected Mutations

**Files:**
- Modify: `lib/core/vault/vault_service.dart`
- Test: `test/core/vault/vault_service_test.dart`

- [ ] **Step 1: Write failing mutation tests**

Add tests:

```dart
test('item create update delete each increment manifest counter once', () async {
  final service = await buildService();
  await service.createVault(masterPassword: 'master-passphrase');
  await service.unlock(masterPassword: 'master-passphrase');

  expect((await service.repository.manifestDao.get())!.counter, 1);

  final id = await service.createItem(_entry(password: 'one'));
  expect((await service.repository.manifestDao.get())!.counter, 2);

  await service.updateItem(id, _entry(password: 'two'));
  expect((await service.repository.manifestDao.get())!.counter, 3);

  await service.deleteItem(id);
  expect((await service.repository.manifestDao.get())!.counter, 4);
});

test('master password change rewrites manifest and keeps items readable', () async {
  final service = await buildService();
  await service.createVault(masterPassword: 'old-master');
  await service.unlock(masterPassword: 'old-master');
  final id = await service.createItem(_entry(password: 'secret-password'));
  final before = await service.repository.manifestDao.get();

  await service.changeMasterPassword(
    oldPassword: 'old-master',
    newPassword: 'new-master',
  );

  final after = await service.repository.manifestDao.get();
  expect(after!.counter, before!.counter + 1);
  service.lock();
  await service.unlock(masterPassword: 'new-master');
  expect((await service.getItem(id)).password, 'secret-password');
});
```

Add `_entry` helper:

```dart
PasswordEntry _entry({required String password}) {
  return PasswordEntry(
    title: 'GitHub',
    website: 'https://github.com',
    username: 'user@example.com',
    password: password,
    notes: 'private note',
    tags: const ['dev'],
  );
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```powershell
flutter test --reporter compact test/core/vault/vault_service_test.dart
```

Expected: FAIL because counters are not rewritten after mutations.

- [ ] **Step 3: Add transaction helper for manifest rewrite**

Add helper in `VaultService`:

```dart
Future<void> _rewriteManifestInTransaction({
  required VaultRepository txn,
  required Uint8List dek,
  required int updatedAt,
}) async {
  final meta = await txn.metaDao.get();
  if (meta == null) {
    throw StateError('Vault has not been created');
  }
  final previous = await txn.manifestDao.get();
  if (previous == null) {
    throw const VaultIntegrityException('Vault manifest is missing');
  }
  final items = await txn.itemsDao.allItemsForManifest();
  final manifest = await _manifestService.createManifest(
    dek: dek,
    meta: meta,
    items: items,
    previous: previous,
    updatedAt: updatedAt,
  );
  await txn.manifestDao.save(manifest);
}
```

Use `_session.copyDekForUse()` if it exists. If it does not exist, add this method to `VaultSession`:

```dart
Uint8List copyDekForUse() {
  ensureUnlocked();
  return Uint8List.fromList(_dek!);
}
```

Use it in protected mutations with `try/finally` zeroing:

```dart
Uint8List? dek;
try {
  dek = _session.copyDekForUse();
  await repository.transaction((txn) async {
    await txn.itemsDao.upsert(encryptedItem);
    await _rewriteManifestInTransaction(
      txn: txn,
      dek: dek!,
      updatedAt: now,
    );
  });
} finally {
  _zeroBytes(dek);
}
```

Apply the same transaction pattern to `updateItem`, `deleteItem`, and `changeMasterPassword` after saving updated metadata.

- [ ] **Step 4: Run focused tests**

Run:

```powershell
dart format lib/core/vault/vault_service.dart lib/core/vault/vault_session.dart test/core/vault/vault_service_test.dart
flutter test --reporter compact test/core/vault/vault_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```powershell
git add lib/core/vault/vault_service.dart lib/core/vault/vault_session.dart test/core/vault/vault_service_test.dart
git commit -m "feat: update manifest on vault mutations"
```

---

### Task 5: Backup Version 2 Manifest Support

**Files:**
- Modify: `lib/core/backup/backup_service.dart`
- Test: `test/core/backup/backup_service_test.dart`

- [ ] **Step 1: Write failing backup tests**

Add tests:

```dart
test('exportBackup writes version 2 magic item count and manifest', () async {
  final source = await _buildHarness();
  await source.vaultService.createVault(masterPassword: 'source-master');
  await source.vaultService.unlock(masterPassword: 'source-master');
  final id = await source.vaultService.createItem(
    PasswordEntry(
      title: 'GitHub',
      website: 'https://github.com',
      username: 'user@example.com',
      password: 'secret-password',
      notes: 'private note',
      tags: ['dev'],
    ),
  );

  final backup = await source.backupService.exportBackup();
  final json = backup.toJson();

  expect(json['version'], 2);
  expect(json['magic'], 'secure-box-backup');
  expect(json['item_count'], 1);
  expect(json['manifest'], isA<Map<String, Object?>>());
  expect(backup.items.map((item) => item.id), [id]);
});

test('version 2 import rejects tampered item before writing data', () async {
  final source = await _buildHarness();
  await source.vaultService.createVault(masterPassword: 'source-master');
  await source.vaultService.unlock(masterPassword: 'source-master');
  await source.vaultService.createItem(_backupEntry(password: 'secret-password'));
  final backupJson = (await source.backupService.exportBackup()).toJson();

  final rawItems = List<Map<String, Object?>>.from(
    backupJson['items']! as List<Object?>,
  );
  rawItems[0] = {
    ...rawItems[0],
    'ciphertext': 'tampered-ciphertext',
  };
  final tampered = {
    ...backupJson,
    'items': rawItems,
  };

  final target = await _buildHarness();
  expect(
    () => target.backupService.importBackup(
      json: tampered,
      masterPassword: 'source-master',
      mode: BackupImportMode.overwrite,
    ),
    throwsA(isA<VaultIntegrityException>()),
  );
  expect(await target.vaultService.repository.metaDao.get(), isNull);
});

test('version 1 import still succeeds and generates a target manifest', () async {
  final target = await _buildHarness();
  final legacyJson = await _buildVersion1BackupJson(masterPassword: 'legacy-master');

  final imported = await target.backupService.importBackup(
    json: legacyJson,
    masterPassword: 'legacy-master',
    mode: BackupImportMode.overwrite,
  );

  expect(imported, 1);
  expect(await target.vaultService.repository.manifestDao.get(), isNotNull);
});
```

Use existing backup test helpers where possible. `_buildVersion1BackupJson` can construct a current `VaultBackup` with `version: 1` and call `toJson()` before Task 5 changes.

- [ ] **Step 2: Run backup tests to verify they fail**

Run:

```powershell
flutter test --reporter compact test/core/backup/backup_service_test.dart
```

Expected: FAIL because export still emits version 1 and no manifest.

- [ ] **Step 3: Extend backup model**

In `backup_service.dart`:

```dart
const int _supportedBackupVersion = 2;
const int _legacyBackupVersion = 1;
const String _backupMagic = 'secure-box-backup';
```

Add `BackupManifest` model mirroring `VaultManifest` fields:

```dart
class BackupManifest {
  const BackupManifest({
    required this.version,
    required this.epoch,
    required this.counter,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.updatedAt,
  });

  factory BackupManifest.fromVaultManifest(VaultManifest manifest) {
    return BackupManifest(
      version: manifest.version,
      epoch: manifest.epoch,
      counter: manifest.counter,
      nonce: manifest.nonce,
      ciphertext: manifest.ciphertext,
      mac: manifest.mac,
      updatedAt: manifest.updatedAt,
    );
  }

  VaultManifest toVaultManifest() => VaultManifest(
    version: version,
    epoch: epoch,
    counter: counter,
    nonce: nonce,
    ciphertext: ciphertext,
    mac: mac,
    updatedAt: updatedAt,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'epoch': epoch,
    'counter': counter,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
    'updated_at': updatedAt,
  };
}
```

Add nullable fields to `VaultBackup`:

```dart
final String? magic;
final int? createdAt;
final int? itemCount;
final BackupManifest? manifest;
```

Version validation:

```dart
if (version != _supportedBackupVersion && version != _legacyBackupVersion) {
  throw BackupFormatException('Unsupported backup version: $version');
}
if (version == _supportedBackupVersion && magic != _backupMagic) {
  throw const BackupFormatException('Invalid backup magic');
}
```

`toJson()` includes v2 fields only when `version == 2`.

- [ ] **Step 4: Verify manifest during export/import**

In `exportBackup`:

```dart
final manifest = await repository.manifestDao.get();
if (manifest == null) {
  throw const VaultIntegrityException('Vault manifest is missing');
}
await vaultService.verifyCurrentManifest();
return VaultBackup(
  version: _supportedBackupVersion,
  magic: _backupMagic,
  createdAt: DateTime.now().millisecondsSinceEpoch,
  itemCount: items.length,
  manifest: BackupManifest.fromVaultManifest(manifest),
  ...
);
```

Add public helper to `VaultService`:

```dart
Future<void> verifyCurrentManifest() async {
  _ensureUnlocked();
  final dek = _session.copyDekForUse();
  try {
    await _verifyExistingManifest(dek: dek);
  } finally {
    _zeroBytes(dek);
  }
}
```

During `importBackup`, after master-password verification and before transaction writes:

```dart
if (backup.version == _supportedBackupVersion) {
  final manifest = backup.manifest;
  if (manifest == null || backup.itemCount != backup.items.length) {
    throw const BackupFormatException('Invalid backup manifest metadata');
  }
  await vaultService.verifyBackupManifest(
    masterPassword: masterPassword,
    meta: backupMeta,
    items: backup.items.map(_buildImportedItemForVerification).toList(growable: false),
    manifest: manifest.toVaultManifest(),
  );
}
```

Implement `verifyBackupManifest` in `VaultService` by decrypting source DEK with the backup meta, calling `_manifestService.verifyManifest`, then zeroing DEK.

For v1 imports, after the target write transaction, create a fresh target manifest using the target DEK. If overwrite import writes backup metadata and locks the session, create the manifest inside the import transaction by decrypting the source DEK from `masterPassword`.

- [ ] **Step 5: Run backup tests**

Run:

```powershell
dart format lib/core/backup/backup_service.dart lib/core/vault/vault_service.dart test/core/backup/backup_service_test.dart
flutter test --reporter compact test/core/backup/backup_service_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```powershell
git add lib/core/backup/backup_service.dart lib/core/vault/vault_service.dart test/core/backup/backup_service_test.dart
git commit -m "feat: add manifest protected backups"
```

---

### Task 6: Full Verification and Security Documentation

**Files:**
- Modify: `docs/security-check.md`

- [ ] **Step 1: Run full test and analyzer**

Run:

```powershell
flutter test --reporter compact
flutter analyze
```

Expected:

- `All tests passed!`
- `No issues found!`

- [ ] **Step 2: Run security scans**

Run:

```powershell
rg -n "MD5|SHA1|sha1|sha256\\(|print\\(|debugPrint\\(|log\\(|password|masterPassword|secret" lib test
rg -n "CREATE TABLE vault_items|CREATE TABLE vault_manifest|username|password|notes|title" lib/data/db lib/data/models
rg -n "android.permission.INTERNET" android
```

Expected:

- No MD5/SHA1 direct password hashing.
- `sha256` appears only in PBKDF2/HKDF/digest code and tests, not direct master-password hashing.
- No logging of sensitive values.
- `vault_items` and `vault_manifest` contain no plaintext sensitive item columns.
- No Android internet permission.

- [ ] **Step 3: Update security document**

Update `docs/security-check.md` Result section with:

```markdown
- Vault manifest integrity is enabled for new vaults and legacy vaults after the first successful master-password unlock.
- `vault_manifest` stores only encrypted manifest payload, nonce, mac, epoch, counter, and timestamps.
- Live vault operations verify or rewrite the manifest so item tampering, item deletion, and metadata envelope replacement fail closed.
- Backup version 2 includes `magic`, `item_count`, and an encrypted manifest; version 1 backup import remains supported as a legacy path that generates a target manifest.
```

- [ ] **Step 4: Commit**

Run:

```powershell
git add docs/security-check.md
git commit -m "docs: update manifest integrity verification"
```

- [ ] **Step 5: Completion review**

Run:

```powershell
git status --short
git log --oneline -8
```

Expected:

- Clean worktree.
- Recent commits correspond to Tasks 1-6.

Then use `superpowers:verification-before-completion` and `superpowers:finishing-a-development-branch`.

---

## Self-Review

- Spec coverage: Tasks 1-4 cover live SQLite manifest creation, verification, mutation rewrites, legacy migration, biometric fail-closed behavior, and non-sensitive errors. Task 5 covers backup v2 and v1 compatibility. Task 6 covers security documentation and final verification.
- Placeholder scan: no unresolved placeholder markers remain. Steps include concrete files, tests, commands, expected results, and implementation shapes.
- Type consistency: `VaultManifest`, `VaultManifestDao`, `VaultManifestService`, `VaultIntegrityException`, and repository `manifestDao` are introduced before later tasks reference them.
