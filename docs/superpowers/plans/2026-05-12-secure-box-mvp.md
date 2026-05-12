# Secure Box MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Android-first Flutter local password manager MVP with real local encryption, SQLite storage, biometric quick unlock, password generation, clipboard cleanup, auto-lock, encrypted backup import/export, and the required tests.

**Architecture:** Create a Flutter app in the repository root and keep feature UI separate from security and persistence code. Core services own cryptography, vault session state, biometric DEK wrapping, clipboard cleanup, and app locking; feature pages call these services through a lightweight `AppServices` container. SQLite stores only encrypted item payloads and vault metadata.

**Tech Stack:** Flutter 3.41, Dart 3.11, `cryptography` for PBKDF2-HMAC-SHA256 and AES-256-GCM, `sqflite` for SQLite, `local_auth` and `flutter_secure_storage` for Android biometric quick unlock, `file_picker` and `share_plus` for local encrypted backups, Flutter widget/unit tests.

---

## File Map

- Create Flutter project files at repository root with `flutter create --platforms=android .`.
- Modify `pubspec.yaml` to add runtime and test dependencies.
- Create `lib/main.dart`: app bootstrap, service initialization, lifecycle guard.
- Create `lib/app/app.dart`: root widget, routes, theme, lock-state routing.
- Create `lib/app/app_services.dart`: service container used by UI and tests.
- Create `lib/core/crypto/secure_random.dart`: random bytes and nonce generation.
- Create `lib/core/crypto/encoding.dart`: base64 helpers.
- Create `lib/core/crypto/kdf_service.dart`: PBKDF2 parameter model and KEK derivation.
- Create `lib/core/crypto/crypto_service.dart`: AES-256-GCM encrypt/decrypt.
- Create `lib/data/models/password_entry.dart`: decrypted vault item JSON model.
- Create `lib/data/models/encrypted_vault_item.dart`: database record model.
- Create `lib/data/models/vault_meta.dart`: vault metadata model.
- Create `lib/data/db/app_database.dart`: SQLite open, schema, migrations.
- Create `lib/data/db/vault_meta_dao.dart`: metadata reads/writes.
- Create `lib/data/db/vault_items_dao.dart`: encrypted item CRUD.
- Create `lib/data/db/settings_dao.dart`: local settings reads/writes.
- Create `lib/core/vault/vault_session.dart`: in-memory unlocked DEK and lock state.
- Create `lib/core/vault/vault_repository.dart`: DAO composition.
- Create `lib/core/vault/vault_service.dart`: create vault, unlock, rotate password, item CRUD.
- Create `lib/core/password_generator/password_generator.dart`: generation rules and secure random output.
- Create `lib/core/clipboard/clipboard_service.dart`: copy and scheduled password cleanup.
- Create `lib/core/security/auto_lock_service.dart`: inactivity/background lock timer.
- Create `lib/core/security/app_lifecycle_guard.dart`: lifecycle observer and privacy overlay hook.
- Create `lib/core/biometric/biometric_service.dart`: Android biometric auth and DEK copy storage.
- Create `lib/core/backup/backup_service.dart`: encrypted backup export/import.
- Create UI files under `lib/features/setup`, `unlock`, `vault_list`, `vault_detail`, `vault_edit`, `password_generator`, and `settings`.
- Create shared UI files under `lib/shared/widgets` and `lib/shared/theme`.
- Create unit tests under `test/core`, `test/data`, and widget tests under `test/features`.

---

### Task 1: Scaffold Flutter App And Dependencies

**Files:**
- Create: Flutter project files generated in repository root
- Modify: `pubspec.yaml`
- Modify: `.gitignore`

- [ ] **Step 1: Create the Flutter project**

Run:

```powershell
flutter create --platforms=android .
```

Expected: Flutter creates `android/`, `lib/main.dart`, `test/widget_test.dart`, and `pubspec.yaml`.

- [ ] **Step 2: Add dependencies**

Run:

```powershell
flutter pub add cryptography sqflite path path_provider uuid local_auth flutter_secure_storage file_picker share_plus
flutter pub add --dev fake_async
```

Expected: `pubspec.yaml` and `pubspec.lock` update successfully.

- [ ] **Step 3: Replace starter test with a smoke test**

Create `test/app_smoke_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test harness is available', () {
    expect(1 + 1, 2);
  });
}
```

Delete `test/widget_test.dart` because the starter counter app will be replaced.

- [ ] **Step 4: Run tests**

Run:

```powershell
flutter test test/app_smoke_test.dart
```

Expected: one passing test.

- [ ] **Step 5: Commit**

```powershell
git add .
git commit -m "chore: scaffold android flutter app"
```

---

### Task 2: Crypto Primitives

**Files:**
- Create: `lib/core/crypto/secure_random.dart`
- Create: `lib/core/crypto/encoding.dart`
- Create: `lib/core/crypto/kdf_service.dart`
- Create: `lib/core/crypto/crypto_service.dart`
- Test: `test/core/crypto/crypto_service_test.dart`

- [ ] **Step 1: Write failing crypto tests**

Create `test/core/crypto/crypto_service_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';

void main() {
  test('correct password decrypts encrypted DEK and wrong password fails', () async {
    final random = SecureRandom();
    final kdf = KdfService();
    final crypto = CryptoService(random: random);
    final salt = random.bytes(16);
    final params = KdfParams.pbkdf2(iterations: 120000);
    final dek = random.bytes(32);

    final goodKek = await kdf.deriveKey(
      password: 'correct horse battery staple',
      salt: salt,
      params: params,
    );
    final encryptedDek = await crypto.encryptBytes(key: goodKek, plaintext: dek);

    final unlockedDek = await crypto.decryptBytes(key: goodKek, payload: encryptedDek);
    expect(unlockedDek, dek);

    final badKek = await kdf.deriveKey(
      password: 'wrong password',
      salt: salt,
      params: params,
    );
    expect(
      () => crypto.decryptBytes(key: badKek, payload: encryptedDek),
      throwsA(isA<CryptoException>()),
    );
  });

  test('same plaintext encrypts to different ciphertext with unique nonces', () async {
    final random = SecureRandom();
    final crypto = CryptoService(random: random);
    final key = random.bytes(32);
    final plaintext = utf8.encode('same secret payload');

    final first = await crypto.encryptBytes(key: key, plaintext: plaintext);
    final second = await crypto.encryptBytes(key: key, plaintext: plaintext);

    expect(first.nonce, isNot(second.nonce));
    expect(first.ciphertext, isNot(second.ciphertext));
    expect(await crypto.decryptBytes(key: key, payload: first), plaintext);
    expect(await crypto.decryptBytes(key: key, payload: second), plaintext);
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
flutter test test/core/crypto/crypto_service_test.dart
```

Expected: compile failure because crypto files do not exist.

- [ ] **Step 3: Implement crypto files**

Create `lib/core/crypto/secure_random.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';

class SecureRandom {
  final Random _random = Random.secure();

  Uint8List bytes(int length) {
    return Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));
  }

  Uint8List nonce12() => bytes(12);
}
```

Create `lib/core/crypto/encoding.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

String b64(Uint8List value) => base64Encode(value);

Uint8List fromB64(String value) => Uint8List.fromList(base64Decode(value));
```

Create `lib/core/crypto/kdf_service.dart`:

```dart
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class KdfParams {
  const KdfParams({
    required this.name,
    required this.iterations,
    required this.bits,
  });

  factory KdfParams.pbkdf2({int iterations = 120000, int bits = 256}) {
    return KdfParams(name: 'pbkdf2-hmac-sha256', iterations: iterations, bits: bits);
  }

  final String name;
  final int iterations;
  final int bits;

  Map<String, Object> toJson() => {
        'name': name,
        'iterations': iterations,
        'bits': bits,
      };

  factory KdfParams.fromJson(Map<String, Object?> json) {
    return KdfParams(
      name: json['name'] as String,
      iterations: json['iterations'] as int,
      bits: json['bits'] as int,
    );
  }
}

class KdfService {
  Future<Uint8List> deriveKey({
    required String password,
    required Uint8List salt,
    required KdfParams params,
  }) async {
    if (params.name != 'pbkdf2-hmac-sha256') {
      throw ArgumentError.value(params.name, 'params.name', 'Unsupported KDF');
    }
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: params.iterations,
      bits: params.bits,
    );
    final secretKey = await algorithm.deriveKey(
      secretKey: SecretKey(password.codeUnits),
      nonce: salt,
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }
}
```

Create `lib/core/crypto/crypto_service.dart`:

```dart
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:secure_box/core/crypto/secure_random.dart';

class EncryptedPayload {
  const EncryptedPayload({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;
}

class CryptoException implements Exception {
  const CryptoException(this.message);
  final String message;

  @override
  String toString() => 'CryptoException: $message';
}

class CryptoService {
  CryptoService({required SecureRandom random}) : _random = random;

  final SecureRandom _random;
  final AesGcm _algorithm = AesGcm.with256bits();

  Future<EncryptedPayload> encryptBytes({
    required Uint8List key,
    required List<int> plaintext,
  }) async {
    final nonce = _random.nonce12();
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    return EncryptedPayload(
      nonce: Uint8List.fromList(box.nonce),
      ciphertext: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  Future<Uint8List> decryptBytes({
    required Uint8List key,
    required EncryptedPayload payload,
  }) async {
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(payload.ciphertext, nonce: payload.nonce, mac: Mac(payload.mac)),
        secretKey: SecretKey(key),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const CryptoException('Authentication failed');
    }
  }
}
```

- [ ] **Step 4: Run crypto tests**

Run:

```powershell
flutter test test/core/crypto/crypto_service_test.dart
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/crypto test/core/crypto/crypto_service_test.dart
git commit -m "feat: add vault crypto primitives"
```

---

### Task 3: Models And JSON Serialization

**Files:**
- Create: `lib/data/models/password_entry.dart`
- Create: `lib/data/models/encrypted_vault_item.dart`
- Create: `lib/data/models/vault_meta.dart`
- Test: `test/data/models/password_entry_test.dart`

- [ ] **Step 1: Write model tests**

Create `test/data/models/password_entry_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/data/models/password_entry.dart';

void main() {
  test('password entry serializes all sensitive fields inside one JSON payload', () {
    final entry = PasswordEntry(
      title: 'GitHub',
      website: 'https://github.com',
      username: 'user@example.com',
      password: 'secret-password',
      notes: 'recovery codes stored offline',
      tags: const ['dev', 'important'],
    );

    final encoded = jsonEncode(entry.toJson());
    final decoded = PasswordEntry.fromJson(jsonDecode(encoded) as Map<String, Object?>);

    expect(decoded.title, 'GitHub');
    expect(decoded.website, 'https://github.com');
    expect(decoded.username, 'user@example.com');
    expect(decoded.password, 'secret-password');
    expect(decoded.notes, 'recovery codes stored offline');
    expect(decoded.tags, ['dev', 'important']);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/data/models/password_entry_test.dart
```

Expected: compile failure because model files do not exist.

- [ ] **Step 3: Implement models**

Create `lib/data/models/password_entry.dart`:

```dart
class PasswordEntry {
  const PasswordEntry({
    required this.title,
    required this.website,
    required this.username,
    required this.password,
    required this.notes,
    required this.tags,
  });

  final String title;
  final String website;
  final String username;
  final String password;
  final String notes;
  final List<String> tags;

  Map<String, Object?> toJson() => {
        'title': title,
        'website': website,
        'username': username,
        'password': password,
        'notes': notes,
        'tags': tags,
      };

  factory PasswordEntry.fromJson(Map<String, Object?> json) {
    return PasswordEntry(
      title: json['title'] as String? ?? '',
      website: json['website'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }
}
```

Create `lib/data/models/encrypted_vault_item.dart`:

```dart
class EncryptedVaultItem {
  const EncryptedVaultItem({
    required this.id,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String nonce;
  final String ciphertext;
  final String mac;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  Map<String, Object?> toDb() => {
        'id': id,
        'nonce': nonce,
        'ciphertext': ciphertext,
        'mac': mac,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  factory EncryptedVaultItem.fromDb(Map<String, Object?> row) {
    return EncryptedVaultItem(
      id: row['id'] as String,
      nonce: row['nonce'] as String,
      ciphertext: row['ciphertext'] as String,
      mac: row['mac'] as String,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      deletedAt: row['deleted_at'] as int?,
    );
  }
}
```

Create `lib/data/models/vault_meta.dart`:

```dart
class VaultMeta {
  const VaultMeta({
    required this.id,
    required this.version,
    required this.kdf,
    required this.kdfParams,
    required this.salt,
    required this.encryptedDekByMaster,
    required this.encryptedDekByMasterNonce,
    required this.encryptedDekByMasterMac,
    required this.biometricEnabled,
    required this.createdAt,
    required this.updatedAt,
    this.encryptedDekByBiometric,
    this.encryptedDekByBiometricNonce,
    this.encryptedDekByBiometricMac,
  });

  final String id;
  final int version;
  final String kdf;
  final String kdfParams;
  final String salt;
  final String encryptedDekByMaster;
  final String encryptedDekByMasterNonce;
  final String encryptedDekByMasterMac;
  final bool biometricEnabled;
  final int createdAt;
  final int updatedAt;
  final String? encryptedDekByBiometric;
  final String? encryptedDekByBiometricNonce;
  final String? encryptedDekByBiometricMac;

  Map<String, Object?> toDb() => {
        'id': id,
        'version': version,
        'kdf': kdf,
        'kdf_params': kdfParams,
        'salt': salt,
        'encrypted_dek_by_master': encryptedDekByMaster,
        'encrypted_dek_by_master_nonce': encryptedDekByMasterNonce,
        'encrypted_dek_by_master_mac': encryptedDekByMasterMac,
        'encrypted_dek_by_biometric': encryptedDekByBiometric,
        'encrypted_dek_by_biometric_nonce': encryptedDekByBiometricNonce,
        'encrypted_dek_by_biometric_mac': encryptedDekByBiometricMac,
        'biometric_enabled': biometricEnabled ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory VaultMeta.fromDb(Map<String, Object?> row) {
    return VaultMeta(
      id: row['id'] as String,
      version: row['version'] as int,
      kdf: row['kdf'] as String,
      kdfParams: row['kdf_params'] as String,
      salt: row['salt'] as String,
      encryptedDekByMaster: row['encrypted_dek_by_master'] as String,
      encryptedDekByMasterNonce: row['encrypted_dek_by_master_nonce'] as String,
      encryptedDekByMasterMac: row['encrypted_dek_by_master_mac'] as String,
      encryptedDekByBiometric: row['encrypted_dek_by_biometric'] as String?,
      encryptedDekByBiometricNonce: row['encrypted_dek_by_biometric_nonce'] as String?,
      encryptedDekByBiometricMac: row['encrypted_dek_by_biometric_mac'] as String?,
      biometricEnabled: row['biometric_enabled'] == 1,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }
}
```

- [ ] **Step 4: Run model tests**

Run:

```powershell
flutter test test/data/models/password_entry_test.dart
```

Expected: test passes.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/models test/data/models/password_entry_test.dart
git commit -m "feat: add vault data models"
```

---

### Task 4: SQLite Schema And DAOs

**Files:**
- Create: `lib/data/db/app_database.dart`
- Create: `lib/data/db/vault_meta_dao.dart`
- Create: `lib/data/db/vault_items_dao.dart`
- Create: `lib/data/db/settings_dao.dart`
- Test: `test/data/db/vault_database_test.dart`

- [ ] **Step 1: Write database tests**

Create `test/data/db/vault_database_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('vault items store only encrypted fields', () async {
    final db = await AppDatabase.openInMemory();
    final dao = VaultItemsDao(db);
    final now = DateTime.utc(2026, 5, 12).millisecondsSinceEpoch;

    await dao.upsert(
      EncryptedVaultItem(
        id: 'item-1',
        nonce: 'nonce-value',
        ciphertext: 'ciphertext-value',
        mac: 'mac-value',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final rows = await db.query('vault_items');
    expect(rows.single.keys, containsAll(['id', 'nonce', 'ciphertext', 'mac']));
    expect(rows.single.keys, isNot(contains('password')));
    expect(rows.single.keys, isNot(contains('username')));
    expect(rows.single.keys, isNot(contains('notes')));
    expect(rows.single['ciphertext'], 'ciphertext-value');
  });

  test('settings can be saved and read', () async {
    final db = await AppDatabase.openInMemory();
    final dao = SettingsDao(db);

    await dao.setValue('clipboard_clear_seconds', '30');

    expect(await dao.getValue('clipboard_clear_seconds'), '30');
  });
}
```

- [ ] **Step 2: Add test dependency for SQLite FFI**

Run:

```powershell
flutter pub add --dev sqflite_common_ffi
```

Expected: test dependency added.

- [ ] **Step 3: Run tests to verify failure**

Run:

```powershell
flutter test test/data/db/vault_database_test.dart
```

Expected: compile failure because database files do not exist.

- [ ] **Step 4: Implement database and DAOs**

Create `lib/data/db/app_database.dart` with schema version 1 and columns matching the models.

Create `lib/data/db/vault_items_dao.dart` with methods:

```dart
Future<void> upsert(EncryptedVaultItem item);
Future<List<EncryptedVaultItem>> activeItems();
Future<EncryptedVaultItem?> byId(String id);
Future<void> softDelete(String id, int deletedAt);
```

Create `lib/data/db/settings_dao.dart` with methods:

```dart
Future<void> setValue(String key, String value);
Future<String?> getValue(String key);
```

Create `lib/data/db/vault_meta_dao.dart` with methods:

```dart
Future<void> save(VaultMeta meta);
Future<VaultMeta?> get();
Future<void> clearBiometricDek(int updatedAt);
```

- [ ] **Step 5: Run database tests**

Run:

```powershell
flutter test test/data/db/vault_database_test.dart
```

Expected: both tests pass.

- [ ] **Step 6: Commit**

```powershell
git add pubspec.yaml pubspec.lock lib/data/db test/data/db/vault_database_test.dart
git commit -m "feat: add sqlite vault storage"
```

---

### Task 5: Vault Session And Vault Service

**Files:**
- Create: `lib/core/vault/vault_session.dart`
- Create: `lib/core/vault/vault_repository.dart`
- Create: `lib/core/vault/vault_service.dart`
- Test: `test/core/vault/vault_service_test.dart`

- [ ] **Step 1: Write vault service tests**

Create `test/core/vault/vault_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<VaultService> buildService() async {
    final db = await AppDatabase.openInMemory();
    return VaultService(
      repository: VaultRepository(
        metaDao: VaultMetaDao(db),
        itemsDao: VaultItemsDao(db),
        settingsDao: SettingsDao(db),
      ),
      random: SecureRandom(),
      kdf: KdfService(),
      crypto: CryptoService(random: SecureRandom()),
    );
  }

  test('creates vault and unlocks with correct password only', () async {
    final service = await buildService();
    await service.createVault(masterPassword: 'master-passphrase');

    final unlocked = await service.unlock(masterPassword: 'master-passphrase');
    expect(unlocked.isUnlocked, isTrue);

    expect(
      () => service.unlock(masterPassword: 'wrong-passphrase'),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test('item CRUD decrypts to original entry and database excludes plaintext', () async {
    final service = await buildService();
    await service.createVault(masterPassword: 'master-passphrase');
    await service.unlock(masterPassword: 'master-passphrase');

    final id = await service.createItem(
      const PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: 'private note',
        tags: ['dev'],
      ),
    );

    final entry = await service.getItem(id);
    expect(entry.title, 'GitHub');
    expect(entry.password, 'secret-password');

    final rawRows = await service.repository.itemsDao.rawRowsForTest();
    final rawText = rawRows.toString();
    expect(rawText, isNot(contains('secret-password')));
    expect(rawText, isNot(contains('user@example.com')));
    expect(rawText, isNot(contains('private note')));
  });

  test('master password rotation invalidates old password', () async {
    final service = await buildService();
    await service.createVault(masterPassword: 'old-master');
    await service.unlock(masterPassword: 'old-master');

    await service.changeMasterPassword(
      oldPassword: 'old-master',
      newPassword: 'new-master',
    );

    expect(() => service.unlock(masterPassword: 'old-master'), throwsA(isA<VaultUnlockException>()));
    expect((await service.unlock(masterPassword: 'new-master')).isUnlocked, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/core/vault/vault_service_test.dart
```

Expected: compile failure because vault service files do not exist.

- [ ] **Step 3: Implement session, repository, and service**

Implement `VaultSession` with:

```dart
bool get isUnlocked;
Uint8List get dek;
void unlock(Uint8List dek);
void lock();
```

Implement `VaultService` methods:

```dart
Future<void> createVault({required String masterPassword});
Future<VaultSession> unlock({required String masterPassword});
Future<void> changeMasterPassword({required String oldPassword, required String newPassword});
Future<String> createItem(PasswordEntry entry);
Future<PasswordEntry> getItem(String id);
Future<List<VaultListItem>> listItems({String query = ''});
Future<void> updateItem(String id, PasswordEntry entry);
Future<void> deleteItem(String id);
```

The service must encrypt item JSON with the in-memory DEK and store only `nonce`, `ciphertext`, and `mac`. `listItems` decrypts active items in memory and filters the query against title, website, username, notes, and tags.

- [ ] **Step 4: Run vault tests**

Run:

```powershell
flutter test test/core/vault/vault_service_test.dart
```

Expected: all vault tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/vault test/core/vault/vault_service_test.dart
git commit -m "feat: add encrypted vault service"
```

---

### Task 6: Password Generator

**Files:**
- Create: `lib/core/password_generator/password_generator.dart`
- Test: `test/core/password_generator/password_generator_test.dart`

- [ ] **Step 1: Write generator tests**

Create `test/core/password_generator/password_generator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/password_generator/password_generator.dart';

void main() {
  test('generated password has exact length and required classes', () {
    final generator = PasswordGenerator();
    final password = generator.generate(
      const PasswordGeneratorOptions(
        length: 24,
        lowercase: true,
        uppercase: true,
        numbers: true,
        symbols: true,
        excludeConfusing: true,
        requireEverySelectedClass: true,
      ),
    );

    expect(password.length, 24);
    expect(password, matches(RegExp(r'[a-z]')));
    expect(password, matches(RegExp(r'[A-Z]')));
    expect(password, matches(RegExp(r'[2-9]')));
    expect(password, matches(RegExp(r'[@#\$%\^&*()\-_=+\[\]{};:,.<>?]')));
    expect(password.contains(RegExp(r'[Oo1lI]')), isFalse);
  });

  test('throws when no character classes are selected', () {
    final generator = PasswordGenerator();
    expect(
      () => generator.generate(const PasswordGeneratorOptions(
        length: 16,
        lowercase: false,
        uppercase: false,
        numbers: false,
        symbols: false,
        excludeConfusing: false,
        requireEverySelectedClass: false,
      )),
      throwsA(isA<PasswordGeneratorException>()),
    );
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/core/password_generator/password_generator_test.dart
```

Expected: compile failure because generator does not exist.

- [ ] **Step 3: Implement generator**

Create `PasswordGeneratorOptions`, `PasswordGeneratorException`, and `PasswordGenerator`. Use `Random.secure()`, allowed sets from `prompt.md`, remove `O`, `o`, `1`, `l`, and `I` when requested, and place one character from each selected set before filling the remaining length.

- [ ] **Step 4: Run generator tests**

Run:

```powershell
flutter test test/core/password_generator/password_generator_test.dart
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/password_generator test/core/password_generator/password_generator_test.dart
git commit -m "feat: add password generator"
```

---

### Task 7: Clipboard Cleanup And Auto-Lock

**Files:**
- Create: `lib/core/clipboard/clipboard_service.dart`
- Create: `lib/core/security/auto_lock_service.dart`
- Create: `lib/core/security/app_lifecycle_guard.dart`
- Test: `test/core/security/clipboard_and_lock_test.dart`

- [ ] **Step 1: Write behavior tests**

Create `test/core/security/clipboard_and_lock_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/clipboard/clipboard_service.dart';
import 'package:secure_box/core/security/auto_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('password clipboard clears after timeout', () async {
    fakeAsync((async) {
      final service = ClipboardService(clearPasswordAfter: const Duration(seconds: 30));
      service.copyPassword('secret-password');
      async.flushMicrotasks();

      Clipboard.getData('text/plain').then((data) {
        expect(data?.text, 'secret-password');
      });
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();

      Clipboard.getData('text/plain').then((data) {
        expect(data?.text ?? '', isNot('secret-password'));
      });
    });
  });

  test('auto lock calls lock after inactivity timeout', () {
    fakeAsync((async) {
      var locked = false;
      final service = AutoLockService(
        timeout: const Duration(minutes: 5),
        onLock: () => locked = true,
      );

      service.recordActivity();
      async.elapse(const Duration(minutes: 4));
      expect(locked, isFalse);
      async.elapse(const Duration(minutes: 1));
      expect(locked, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
flutter test test/core/security/clipboard_and_lock_test.dart
```

Expected: compile failure because services do not exist.

- [ ] **Step 3: Implement clipboard and lock services**

Implement `ClipboardService.copyUsername`, `ClipboardService.copyPassword`, and a timer that clears the clipboard only when it still contains the copied password. Implement `AutoLockService.recordActivity`, `AutoLockService.lockNow`, `AutoLockService.dispose`, and `AppLifecycleGuard.didChangeAppLifecycleState` to lock on paused, inactive, hidden, and detached states.

- [ ] **Step 4: Run behavior tests**

Run:

```powershell
flutter test test/core/security/clipboard_and_lock_test.dart
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/clipboard lib/core/security test/core/security/clipboard_and_lock_test.dart
git commit -m "feat: add clipboard cleanup and auto lock"
```

---

### Task 8: Biometric Quick Unlock

**Files:**
- Create: `lib/core/biometric/biometric_service.dart`
- Test: `test/core/biometric/biometric_service_test.dart`

- [ ] **Step 1: Write biometric service tests with fakes**

Create `test/core/biometric/biometric_service_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';

void main() {
  test('enable stores DEK copy and disable removes it', () async {
    final auth = FakeBiometricAuthenticator(canAuthenticate: true, succeeds: true);
    final store = MemorySecureDekStore();
    final service = BiometricService(authenticator: auth, store: store);

    await service.enable(Uint8List.fromList([1, 2, 3, 4]));
    expect(await store.readDek(), [1, 2, 3, 4]);

    await service.disable();
    expect(await store.readDek(), isNull);
  });

  test('failed biometric returns fallback result', () async {
    final service = BiometricService(
      authenticator: FakeBiometricAuthenticator(canAuthenticate: true, succeeds: false),
      store: MemorySecureDekStore()..writeDek(Uint8List.fromList([9, 9])),
    );

    final result = await service.unlock();
    expect(result, BiometricUnlockResult.fallbackToMasterPassword);
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
flutter test test/core/biometric/biometric_service_test.dart
```

Expected: compile failure because biometric service does not exist.

- [ ] **Step 3: Implement biometric abstractions**

Create interfaces:

```dart
abstract class BiometricAuthenticator {
  Future<bool> canAuthenticate();
  Future<bool> authenticate();
}

abstract class SecureDekStore {
  Future<void> writeDek(Uint8List dek);
  Future<Uint8List?> readDek();
  Future<void> deleteDek();
}
```

Implement fakes for tests and Android-backed classes using `local_auth` and `flutter_secure_storage`. Store only the DEK copy bytes encoded as base64 through secure storage; do not store the master password.

- [ ] **Step 4: Run biometric tests**

Run:

```powershell
flutter test test/core/biometric/biometric_service_test.dart
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/biometric test/core/biometric/biometric_service_test.dart
git commit -m "feat: add biometric quick unlock service"
```

---

### Task 9: Backup Export And Import

**Files:**
- Create: `lib/core/backup/backup_service.dart`
- Test: `test/core/backup/backup_service_test.dart`

- [ ] **Step 1: Write backup tests**

Create `test/core/backup/backup_service_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/backup/backup_service.dart';

void main() {
  test('backup JSON contains encrypted item fields only', () {
    final backup = VaultBackup(
      version: 1,
      kdf: 'pbkdf2-hmac-sha256',
      kdfParams: {'iterations': 120000, 'bits': 256},
      salt: 'salt',
      encryptedDekByMaster: 'encrypted-dek',
      encryptedDekByMasterNonce: 'nonce',
      encryptedDekByMasterMac: 'mac',
      items: const [
        BackupItem(id: '1', nonce: 'item-nonce', ciphertext: 'item-ciphertext', mac: 'item-mac'),
      ],
    );

    final jsonText = jsonEncode(backup.toJson());
    expect(jsonText, contains('item-ciphertext'));
    expect(jsonText, isNot(contains('secret-password')));
    expect(jsonText, isNot(contains('user@example.com')));
  });

  test('unsupported backup version is rejected', () {
    expect(
      () => VaultBackup.fromJson({'version': 99}),
      throwsA(isA<BackupFormatException>()),
    );
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
flutter test test/core/backup/backup_service_test.dart
```

Expected: compile failure because backup service does not exist.

- [ ] **Step 3: Implement backup models and service**

Implement `VaultBackup`, `BackupItem`, `BackupFormatException`, `BackupImportMode.overwrite/skip/merge`, and `BackupService.exportBackup()` / `BackupService.importBackup()`. Import must validate version 1, parse required string fields, ask `VaultService` to verify the master password by decrypting the exported DEK, then insert encrypted item records using the selected duplicate strategy.

- [ ] **Step 4: Run backup tests**

Run:

```powershell
flutter test test/core/backup/backup_service_test.dart
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/backup test/core/backup/backup_service_test.dart
git commit -m "feat: add encrypted backup service"
```

---

### Task 10: App Wiring, Theme, And Navigation

**Files:**
- Create: `lib/app/app.dart`
- Create: `lib/app/app_services.dart`
- Modify: `lib/main.dart`
- Create: `lib/shared/theme/app_theme.dart`
- Create: `lib/shared/widgets/secure_scaffold.dart`
- Test: `test/app/app_routing_test.dart`

- [ ] **Step 1: Write routing test**

Create `test/app/app_routing_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';

void main() {
  testWidgets('fresh app shows setup page', (tester) async {
    final services = AppServices.fake(hasVault: false);
    await tester.pumpWidget(SecureBoxApp(services: services));

    expect(find.text('创建主密码'), findsOneWidget);
    expect(find.textContaining('无法找回'), findsOneWidget);
  });

  testWidgets('existing locked vault shows unlock page', (tester) async {
    final services = AppServices.fake(hasVault: true);
    await tester.pumpWidget(SecureBoxApp(services: services));

    expect(find.text('解锁密码库'), findsOneWidget);
    expect(find.text('主密码'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/app/app_routing_test.dart
```

Expected: compile failure because app files do not exist.

- [ ] **Step 3: Implement root app and theme**

Implement `SecureBoxApp` with Material 3, Chinese text labels, approved palette, named routes, and a service container. `main.dart` opens SQLite, constructs services, and passes them into `SecureBoxApp`.

- [ ] **Step 4: Run routing tests**

Run:

```powershell
flutter test test/app/app_routing_test.dart
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/app lib/shared lib/main.dart test/app/app_routing_test.dart
git commit -m "feat: wire secure box app shell"
```

---

### Task 11: Setup And Unlock Pages

**Files:**
- Create: `lib/features/setup/setup_page.dart`
- Create: `lib/features/unlock/unlock_page.dart`
- Test: `test/features/setup_unlock_test.dart`

- [ ] **Step 1: Write widget tests**

Create `test/features/setup_unlock_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';

void main() {
  testWidgets('setup validates matching master passwords', (tester) async {
    final services = AppServices.fake(hasVault: false);
    await tester.pumpWidget(SecureBoxApp(services: services));

    await tester.enterText(find.bySemanticsLabel('主密码'), 'long-master-password');
    await tester.enterText(find.bySemanticsLabel('确认主密码'), 'different-password');
    await tester.tap(find.text('创建密码库'));
    await tester.pump();

    expect(find.text('两次输入的主密码不一致'), findsOneWidget);
  });

  testWidgets('unlock shows error for wrong master password', (tester) async {
    final services = AppServices.fake(hasVault: true, unlockSucceeds: false);
    await tester.pumpWidget(SecureBoxApp(services: services));

    await tester.enterText(find.bySemanticsLabel('主密码'), 'wrong-password');
    await tester.tap(find.text('解锁'));
    await tester.pump();

    expect(find.text('主密码不正确'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
flutter test test/features/setup_unlock_test.dart
```

Expected: compile failure or widget lookup failure because pages are not implemented.

- [ ] **Step 3: Implement setup and unlock pages**

Use `Form` and `GlobalKey<FormState>`. Setup requires password length of at least 12, matching confirmation, visible warning text `主密码不会上传，也无法找回。请务必牢记。`, and optional biometric toggle. Unlock supports master password, biometric button when enabled, generic error `主密码不正确`, and increasing delay after repeated failures.

- [ ] **Step 4: Run widget tests**

Run:

```powershell
flutter test test/features/setup_unlock_test.dart
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/setup lib/features/unlock test/features/setup_unlock_test.dart
git commit -m "feat: add setup and unlock flows"
```

---

### Task 12: Vault List, Detail, And Edit Pages

**Files:**
- Create: `lib/features/vault_list/vault_list_page.dart`
- Create: `lib/features/vault_detail/vault_detail_page.dart`
- Create: `lib/features/vault_edit/vault_edit_page.dart`
- Test: `test/features/vault_item_flow_test.dart`

- [ ] **Step 1: Write item flow widget tests**

Create `test/features/vault_item_flow_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';

void main() {
  testWidgets('user can add item and password is hidden in detail by default', (tester) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);
    await tester.pumpWidget(SecureBoxApp(services: services));

    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('标题'), 'GitHub');
    await tester.enterText(find.bySemanticsLabel('网站'), 'https://github.com');
    await tester.enterText(find.bySemanticsLabel('用户名'), 'user@example.com');
    await tester.enterText(find.bySemanticsLabel('密码'), 'secret-password');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);
    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();

    expect(find.text('secret-password'), findsNothing);
    expect(find.textContaining('••••'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/features/vault_item_flow_test.dart
```

Expected: widget lookup failure because pages are not complete.

- [ ] **Step 3: Implement vault pages**

Implement list search, add button, detail navigation, default hidden password, show/hide button, copy username, copy password, edit, save, soft delete, and delete confirmation text `删除后此条记录将无法在列表中显示。确认删除？`.

- [ ] **Step 4: Run item flow tests**

Run:

```powershell
flutter test test/features/vault_item_flow_test.dart
```

Expected: test passes.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/vault_list lib/features/vault_detail lib/features/vault_edit test/features/vault_item_flow_test.dart
git commit -m "feat: add vault item screens"
```

---

### Task 13: Generator And Settings Pages

**Files:**
- Create: `lib/features/password_generator/password_generator_page.dart`
- Create: `lib/features/settings/settings_page.dart`
- Test: `test/features/generator_settings_test.dart`

- [ ] **Step 1: Write widget tests**

Create `test/features/generator_settings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';

void main() {
  testWidgets('generator can save selected password into edit page', (tester) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);
    await tester.pumpWidget(SecureBoxApp(services: services));

    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24'));
    await tester.tap(find.text('生成密码'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存此密码').first);
    await tester.pumpAndSettle();

    expect(find.text('新增密码'), findsOneWidget);
    expect(find.bySemanticsLabel('密码'), findsOneWidget);
  });

  testWidgets('settings exposes required security controls', (tester) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);
    await tester.pumpWidget(SecureBoxApp(services: services));

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('修改主密码'), findsOneWidget);
    expect(find.text('生物识别'), findsOneWidget);
    expect(find.text('自动锁定'), findsOneWidget);
    expect(find.text('剪贴板清理'), findsOneWidget);
    expect(find.text('导出加密备份'), findsOneWidget);
    expect(find.text('导入加密备份'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
flutter test test/features/generator_settings_test.dart
```

Expected: widget lookup failure because pages are missing.

- [ ] **Step 3: Implement generator and settings pages**

Generator page uses length choices `8 / 12 / 16 / 24 / 32 / 64`, toggles for lowercase, uppercase, numbers, symbols, exclude confusing characters, and require every selected class. Settings page supports master password change dialog, biometric enable/disable, auto-lock timeout, clipboard cleanup timeout, backup export/import, and clear local vault confirmation.

- [ ] **Step 4: Run widget tests**

Run:

```powershell
flutter test test/features/generator_settings_test.dart
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/password_generator lib/features/settings test/features/generator_settings_test.dart
git commit -m "feat: add generator and settings screens"
```

---

### Task 14: Android Integration And Manifest Hardening

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/build.gradle.kts` or `android/app/build.gradle`
- Modify: `lib/main.dart`
- Test: `flutter test`

- [ ] **Step 1: Configure Android biometric and secure-window behavior**

Add required `local_auth` Android settings and permissions. Set secure-window/task-preview masking through platform channel or Flutter lifecycle overlay. The Android manifest must not add internet permission because MVP has no network feature.

- [ ] **Step 2: Verify no internet permission**

Run:

```powershell
rg -n "android.permission.INTERNET" android
```

Expected: no matches.

- [ ] **Step 3: Run all tests**

Run:

```powershell
flutter test
```

Expected: all unit and widget tests pass.

- [ ] **Step 4: Analyze code**

Run:

```powershell
flutter analyze
```

Expected: no analyzer errors.

- [ ] **Step 5: Commit**

```powershell
git add android lib/main.dart
git commit -m "chore: harden android integration"
```

---

### Task 15: Final Security Verification

**Files:**
- Modify: tests if regressions reveal missing assertions
- Create: `docs/security-check.md`

- [ ] **Step 1: Run full verification**

Run:

```powershell
flutter test
flutter analyze
```

Expected: tests pass and analyzer reports no errors.

- [ ] **Step 2: Search for forbidden crypto and logging patterns**

Run:

```powershell
rg -n "MD5|SHA1|sha1|sha256\\(|print\\(|debugPrint\\(|log\\(|password|masterPassword|secret" lib test
```

Expected: inspect matches manually. Allowed matches are type names, test fixture strings, labels, and controlled variables. No sensitive values are logged.

- [ ] **Step 3: Search for plaintext storage columns**

Run:

```powershell
rg -n "CREATE TABLE vault_items|username|password|notes|title" lib/data/db lib/data/models
```

Expected: `vault_items` schema contains `id`, `nonce`, `ciphertext`, `mac`, timestamps, and delete marker only. Plaintext field names appear only in decrypted model code, not in SQLite item columns.

- [ ] **Step 4: Document security check**

Create `docs/security-check.md`:

```markdown
# Secure Box Security Check

Date: 2026-05-12

## Commands

- `flutter test`
- `flutter analyze`
- `rg -n "MD5|SHA1|sha1|sha256\\(|print\\(|debugPrint\\(|log\\(|password|masterPassword|secret" lib test`
- `rg -n "CREATE TABLE vault_items|username|password|notes|title" lib/data/db lib/data/models`

## Result

- Tests passed.
- Analyzer passed.
- No MD5 or SHA1 usage.
- No direct SHA256 master-password processing.
- No sensitive-value logging.
- `vault_items` stores only nonce, ciphertext, MAC, timestamps, and deletion state.
- Sensitive item fields are serialized into encrypted JSON before persistence.
```

- [ ] **Step 5: Commit**

```powershell
git add docs/security-check.md
git commit -m "docs: record mvp security verification"
```

---

## Self-Review

Spec coverage:

- Local Android-first Flutter app: Tasks 1, 10, 14.
- Master password setup, unlock, and rotation: Tasks 5, 11, 13.
- KEK/DEK hierarchy and AES-GCM item encryption: Tasks 2, 5.
- SQLite metadata, items, and settings: Task 4.
- No plaintext sensitive fields in SQLite: Tasks 4, 5, 15.
- Biometric DEK copy and fallback: Task 8.
- Password generator rules and save handoff: Tasks 6, 13.
- View, copy, edit, delete, and search items: Tasks 5, 12.
- Clipboard cleanup: Task 7.
- Auto-lock and background lock: Tasks 7, 14.
- Backup export/import: Task 9.
- UI/UX constraints from `ui-ux-pro-max`: Tasks 10 through 13.
- Required tests and final verification: Tasks 2 through 15.

Placeholder scan:

- The plan contains no unresolved placeholder tokens or unresolved file paths.
- Code-facing steps name concrete classes, methods, commands, and expected results.

Type consistency:

- `KdfParams`, `CryptoService`, `EncryptedPayload`, `PasswordEntry`, `EncryptedVaultItem`, `VaultMeta`, `VaultSession`, `VaultRepository`, `VaultService`, `PasswordGenerator`, `ClipboardService`, `AutoLockService`, `BiometricService`, and `BackupService` are introduced before downstream tasks reference them.
