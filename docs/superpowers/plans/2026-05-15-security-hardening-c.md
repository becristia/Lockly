# Security Hardening C Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Argon2id the default KDF for new and rotated vaults while preserving PBKDF2 compatibility, and harden Android biometric DEK storage with biometric secure storage options.

**Architecture:** Extend the existing `KdfParams`/`KdfService` dispatch point rather than adding a parallel crypto path. Keep `vault_meta.kdf` and `vault_meta.kdf_params` as the source of truth for decrypting old vaults. Change biometric storage by tightening `SecureStorageDekStore` Android options while preserving master-password fallback.

**Tech Stack:** Flutter 3.41, Dart 3.11, `cryptography` for PBKDF2 and AES-GCM, `hashlib` for Argon2id, `flutter_secure_storage` 10.2 Android biometric options, `local_auth`, SQLite, Flutter tests.

---

## References

- Design spec: `docs/superpowers/specs/2026-05-15-security-hardening-c-design.md`
- `hashlib` Argon2 API: `https://pub.dev/documentation/hashlib/latest/hashlib/Argon2-class.html`
- `flutter_secure_storage` biometric Android options: `https://pub.dev/packages/flutter_secure_storage`

---

## File Map

- Modify `pubspec.yaml`: add `hashlib`.
- Modify `pubspec.lock`: dependency resolution output.
- Modify `lib/core/crypto/kdf_service.dart`: add Argon2id params, validation, and derivation.
- Modify `lib/data/models/vault_meta.dart`: parse KDF params by delegating validation to `KdfParams.fromJson`.
- Modify `lib/core/vault/vault_service.dart`: default new/rotated vaults to Argon2id, keep old PBKDF2 unlock.
- Modify `lib/core/biometric/biometric_service.dart`: use biometric Android secure storage options and store-managed authentication.
- Modify `docs/security-check.md`: document Argon2id default and biometric storage posture.
- Test `test/core/crypto/crypto_service_test.dart`: Argon2id derivation and validation.
- Test `test/data/models/password_entry_test.dart`: Argon2id vault metadata parsing/round-trip.
- Test `test/core/vault/vault_service_test.dart`: new vault metadata and PBKDF2-to-Argon2id migration.
- Test `test/core/biometric/biometric_service_test.dart`: biometric Android options and fallback behavior.

---

### Task 1: Add Argon2id Dependency And KDF Param Model

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `lib/core/crypto/kdf_service.dart`
- Modify: `lib/data/models/vault_meta.dart`
- Test: `test/core/crypto/crypto_service_test.dart`
- Test: `test/data/models/password_entry_test.dart`

- [ ] **Step 1: Add the dependency**

Run:

```powershell
flutter pub add hashlib
```

Expected: `pubspec.yaml` contains `hashlib`, and `pubspec.lock` resolves it.

- [ ] **Step 2: Write failing Argon2id KDF tests**

Append these tests to `test/core/crypto/crypto_service_test.dart`:

```dart
  test('argon2id derives deterministic 256-bit keys', () async {
    final kdf = KdfService();
    final salt = Uint8List.fromList(List<int>.generate(16, (index) => index));
    final params = KdfParams.argon2id(
      memoryKiB: 1024,
      iterations: 2,
      parallelism: 1,
      bits: 256,
    );

    final first = await kdf.deriveKey(
      password: 'correct horse battery staple',
      salt: salt,
      params: params,
    );
    final second = await kdf.deriveKey(
      password: 'correct horse battery staple',
      salt: salt,
      params: params,
    );

    expect(first, hasLength(32));
    expect(second, orderedEquals(first));
  });

  test('rejects invalid argon2id params', () async {
    final kdf = KdfService();
    final salt = Uint8List.fromList(List<int>.filled(16, 1));

    expect(
      () => kdf.deriveKey(
        password: 'master-password',
        salt: salt,
        params: KdfParams.argon2id(memoryKiB: 0),
      ),
      throwsArgumentError,
    );
    expect(
      () => kdf.deriveKey(
        password: 'master-password',
        salt: salt,
        params: KdfParams.argon2id(iterations: 0),
      ),
      throwsArgumentError,
    );
    expect(
      () => kdf.deriveKey(
        password: 'master-password',
        salt: salt,
        params: KdfParams.argon2id(parallelism: 0),
      ),
      throwsArgumentError,
    );
    expect(
      () => kdf.deriveKey(
        password: 'master-password',
        salt: salt,
        params: KdfParams.argon2id(bits: 128),
      ),
      throwsArgumentError,
    );
  });
```

Expected now: compile failure because `KdfParams.argon2id` does not exist.

- [ ] **Step 3: Write failing metadata parse tests**

Append these tests to `test/data/models/password_entry_test.dart` near the existing vault meta tests:

```dart
  test('vault meta round-trips argon2id kdf params', () {
    final meta = VaultMeta(
      id: 'vault-1',
      version: 1,
      kdf: 'argon2id',
      kdfParams: KdfParams.argon2id(
        memoryKiB: 65536,
        iterations: 3,
        parallelism: 1,
        bits: 256,
      ),
      salt: 'salt',
      encryptedDekByMaster: 'dek',
      encryptedDekByMasterNonce: 'nonce',
      encryptedDekByMasterMac: 'mac',
      biometricEnabled: false,
      createdAt: 1,
      updatedAt: 2,
    );

    final row = meta.toDb();
    expect(row['kdf'], 'argon2id');
    expect(row['kdf_params'], contains('"memoryKiB":65536'));
    expect(row['kdf_params'], contains('"parallelism":1'));

    final decoded = VaultMeta.fromDb(row);
    expect(decoded.kdf, 'argon2id');
    expect(decoded.kdfParams.name, 'argon2id');
    expect(decoded.kdfParams.memoryKiB, 65536);
    expect(decoded.kdfParams.parallelism, 1);
  });
```

Expected now: compile failure because `memoryKiB` and `parallelism` do not exist.

- [ ] **Step 4: Implement `KdfParams` Argon2id support**

Replace `KdfParams` in `lib/core/crypto/kdf_service.dart` with this shape while preserving the existing imports:

```dart
class KdfParams {
  const KdfParams({
    required this.name,
    required this.iterations,
    required this.bits,
    this.memoryKiB,
    this.parallelism,
  });

  factory KdfParams.pbkdf2({int iterations = 120000, int bits = 256}) {
    return KdfParams(
      name: 'pbkdf2-hmac-sha256',
      iterations: iterations,
      bits: bits,
    );
  }

  factory KdfParams.argon2id({
    int memoryKiB = 65536,
    int iterations = 3,
    int parallelism = 1,
    int bits = 256,
  }) {
    return KdfParams(
      name: 'argon2id',
      iterations: iterations,
      bits: bits,
      memoryKiB: memoryKiB,
      parallelism: parallelism,
    );
  }

  final String name;
  final int iterations;
  final int bits;
  final int? memoryKiB;
  final int? parallelism;

  Map<String, Object> toJson() {
    final json = <String, Object>{
      'name': name,
      'iterations': iterations,
      'bits': bits,
    };
    if (name == 'argon2id') {
      json['memoryKiB'] = memoryKiB ?? 65536;
      json['parallelism'] = parallelism ?? 1;
    }
    return json;
  }

  factory KdfParams.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final iterations = json['iterations'];
    final bits = json['bits'];
    if (name is! String || iterations is! int || bits is! int) {
      throw const FormatException(
        'Invalid kdf_params JSON object: expected string name and integer iterations/bits',
      );
    }
    if (name == 'pbkdf2-hmac-sha256') {
      return KdfParams.pbkdf2(iterations: iterations, bits: bits);
    }
    if (name == 'argon2id') {
      final memoryKiB = json['memoryKiB'];
      final parallelism = json['parallelism'];
      if (memoryKiB is! int || parallelism is! int) {
        throw const FormatException(
          'Invalid argon2id kdf_params JSON object: expected integer memoryKiB/parallelism',
        );
      }
      return KdfParams.argon2id(
        memoryKiB: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
        bits: bits,
      );
    }
    throw FormatException('Unsupported KDF: $name');
  }
}
```

- [ ] **Step 5: Relax `VaultMeta._parseKdfParams` pre-validation**

In `lib/data/models/vault_meta.dart`, replace the strict `json['name']` / `json['iterations']` / `json['bits']` block with:

```dart
    final json = Map<String, Object?>.from(decodedValue);
    try {
      return KdfParams.fromJson(json);
    } on FormatException catch (error) {
      throw FormatException(error.message, rawValue, error.offset);
    }
```

Expected: `VaultMeta` delegates algorithm-specific parameter validation to `KdfParams`.

- [ ] **Step 6: Run focused tests to confirm model work**

Run:

```powershell
flutter test --reporter compact test/core/crypto/crypto_service_test.dart test/data/models/password_entry_test.dart
```

Expected before Task 2 implementation: metadata tests compile after the model change, but Argon2id derivation still fails until `KdfService` supports it.

- [ ] **Step 7: Commit**

```powershell
git add pubspec.yaml pubspec.lock lib/core/crypto/kdf_service.dart lib/data/models/vault_meta.dart test/core/crypto/crypto_service_test.dart test/data/models/password_entry_test.dart
git commit -m "feat: add argon2id kdf params"
```

---

### Task 2: Implement Argon2id Derivation

**Files:**
- Modify: `lib/core/crypto/kdf_service.dart`
- Test: `test/core/crypto/crypto_service_test.dart`

- [ ] **Step 1: Add the hashlib import**

Add to `lib/core/crypto/kdf_service.dart`:

```dart
import 'package:hashlib/hashlib.dart' as hashlib;
```

- [ ] **Step 2: Add Argon2id validation constants**

Near the existing constants, add:

```dart
const int _minimumArgon2MemoryKiB = 1024;
const int _minimumArgon2Iterations = 1;
const int _minimumArgon2Parallelism = 1;
```

- [ ] **Step 3: Split KDF derivation by algorithm**

Replace the body of `KdfService.deriveKey` with:

```dart
    if (params.name == 'pbkdf2-hmac-sha256') {
      return _derivePbkdf2(password: password, salt: salt, params: params);
    }
    if (params.name == 'argon2id') {
      return _deriveArgon2id(password: password, salt: salt, params: params);
    }
    throw ArgumentError.value(params.name, 'params.name', 'Unsupported KDF');
```

- [ ] **Step 4: Move the existing PBKDF2 code into a helper**

Add inside `KdfService`:

```dart
  Future<Uint8List> _derivePbkdf2({
    required String password,
    required Uint8List salt,
    required KdfParams params,
  }) async {
    if (params.iterations <= 0) {
      throw ArgumentError.value(
        params.iterations,
        'params.iterations',
        'PBKDF2 iterations must be greater than zero',
      );
    }
    if (params.iterations < _minimumPbkdf2Iterations) {
      throw ArgumentError.value(
        params.iterations,
        'params.iterations',
        'PBKDF2 iterations must be at least $_minimumPbkdf2Iterations for this MVP',
      );
    }
    _validateCommonSaltAndBits(salt: salt, bits: params.bits);
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: params.iterations,
      bits: params.bits,
    );
    final secretKey = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }
```

- [ ] **Step 5: Add Argon2id derivation**

Add inside `KdfService`:

```dart
  Future<Uint8List> _deriveArgon2id({
    required String password,
    required Uint8List salt,
    required KdfParams params,
  }) async {
    _validateCommonSaltAndBits(salt: salt, bits: params.bits);
    final memoryKiB = params.memoryKiB;
    final parallelism = params.parallelism;
    if (memoryKiB == null || memoryKiB < _minimumArgon2MemoryKiB) {
      throw ArgumentError.value(
        memoryKiB,
        'params.memoryKiB',
        'Argon2id memoryKiB must be at least $_minimumArgon2MemoryKiB',
      );
    }
    if (params.iterations < _minimumArgon2Iterations) {
      throw ArgumentError.value(
        params.iterations,
        'params.iterations',
        'Argon2id iterations must be at least $_minimumArgon2Iterations',
      );
    }
    if (parallelism == null || parallelism < _minimumArgon2Parallelism) {
      throw ArgumentError.value(
        parallelism,
        'params.parallelism',
        'Argon2id parallelism must be at least $_minimumArgon2Parallelism',
      );
    }

    final algorithm = hashlib.Argon2(
      type: hashlib.Argon2Type.argon2id,
      version: hashlib.Argon2Version.v13,
      parallelism: parallelism,
      memorySizeKB: memoryKiB,
      iterations: params.iterations,
      hashLength: params.bits ~/ 8,
      salt: salt,
    );
    final digest = algorithm.convert(utf8.encode(password));
    return Uint8List.fromList(digest.bytes);
  }
```

- [ ] **Step 6: Add common validation helper**

Add inside `KdfService`:

```dart
  void _validateCommonSaltAndBits({
    required Uint8List salt,
    required int bits,
  }) {
    if (salt.length < _minimumSaltLength) {
      throw ArgumentError.value(
        salt.length,
        'salt',
        'Salt must be at least $_minimumSaltLength bytes',
      );
    }
    if (bits != _requiredDerivedKeyBits) {
      throw ArgumentError.value(
        bits,
        'params.bits',
        'Only $_requiredDerivedKeyBits-bit KDF output is supported',
      );
    }
  }
```

- [ ] **Step 7: Run focused crypto tests**

Run:

```powershell
flutter test --reporter compact test/core/crypto/crypto_service_test.dart
```

Expected: all crypto tests pass, including Argon2id.

- [ ] **Step 8: Format and commit**

Run:

```powershell
dart format lib/core/crypto/kdf_service.dart test/core/crypto/crypto_service_test.dart
git add lib/core/crypto/kdf_service.dart test/core/crypto/crypto_service_test.dart
git commit -m "feat: derive vault keys with argon2id"
```

---

### Task 3: Default New And Rotated Vaults To Argon2id

**Files:**
- Modify: `lib/core/vault/vault_service.dart`
- Test: `test/core/vault/vault_service_test.dart`

- [ ] **Step 1: Write failing new-vault metadata test**

Add to `test/core/vault/vault_service_test.dart`:

```dart
  test('new vaults use argon2id metadata by default', () async {
    final service = await buildService();

    await service.createVault(masterPassword: 'master-passphrase');

    final meta = await service.repository.metaDao.get();
    expect(meta, isNotNull);
    expect(meta!.kdf, 'argon2id');
    expect(meta.kdfParams.name, 'argon2id');
    expect(meta.kdfParams.memoryKiB, 65536);
    expect(meta.kdfParams.iterations, 3);
    expect(meta.kdfParams.parallelism, 1);
    expect(meta.kdfParams.bits, 256);
  });
```

Expected now: fails because `createVault()` uses PBKDF2.

- [ ] **Step 2: Write failing PBKDF2 rotation migration test**

Add helper imports if needed:

```dart
import 'package:secure_box/core/crypto/encoding.dart';
import 'package:secure_box/data/models/vault_meta.dart';
```

Add this test to `test/core/vault/vault_service_test.dart`:

```dart
  test('changing a pbkdf2 vault password migrates metadata to argon2id', () async {
    final service = await buildService();
    final now = DateTime.utc(2026, 5, 15).millisecondsSinceEpoch;
    final salt = SecureRandom().bytes(16);
    final dek = SecureRandom().bytes(32);
    final oldParams = KdfParams.pbkdf2(iterations: 120000, bits: 256);
    final oldKek = await KdfService().deriveKey(
      password: 'old-master',
      salt: salt,
      params: oldParams,
    );
    final wrappedDek = await CryptoService(
      random: SecureRandom(),
    ).encryptBytes(key: oldKek, plaintext: dek);

    await service.repository.metaDao.save(
      VaultMeta(
        id: 'legacy-vault',
        version: 1,
        kdf: oldParams.name,
        kdfParams: oldParams,
        salt: b64(salt),
        encryptedDekByMaster: b64(wrappedDek.ciphertext),
        encryptedDekByMasterNonce: b64(wrappedDek.nonce),
        encryptedDekByMasterMac: b64(wrappedDek.mac),
        biometricEnabled: false,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await service.unlock(masterPassword: 'old-master');
    await service.changeMasterPassword(
      oldPassword: 'old-master',
      newPassword: 'new-master',
    );

    final meta = await service.repository.metaDao.get();
    expect(meta!.kdf, 'argon2id');
    expect(meta.kdfParams.name, 'argon2id');
    expect(
      () => service.unlock(masterPassword: 'old-master'),
      throwsA(isA<VaultUnlockException>()),
    );
    expect(
      (await service.unlock(masterPassword: 'new-master')).isUnlocked,
      isTrue,
    );
  });
```

Expected now: fails because rotation reuses old `meta.kdfParams`.

- [ ] **Step 3: Change create vault default params**

In `lib/core/vault/vault_service.dart`, change:

```dart
    final kdfParams = KdfParams.pbkdf2();
```

to:

```dart
    final kdfParams = KdfParams.argon2id();
```

- [ ] **Step 4: Change password rotation to use new Argon2id params**

In `changeMasterPassword`, before deriving `newKek`, add:

```dart
      final newKdfParams = KdfParams.argon2id();
```

Then change the derive call to:

```dart
      newKek = await _kdf.deriveKey(
        password: newPassword,
        salt: newSalt,
        params: newKdfParams,
      );
```

And in `updatedMeta`, change:

```dart
        kdf: meta.kdf,
        kdfParams: meta.kdfParams,
```

to:

```dart
        kdf: newKdfParams.name,
        kdfParams: newKdfParams,
```

- [ ] **Step 5: Run vault tests**

Run:

```powershell
flutter test --reporter compact test/core/vault/vault_service_test.dart
```

Expected: vault tests pass. If tests are slow because default Argon2id uses 64 MiB, keep the default as specified and do not reduce production parameters just to speed tests; instead use targeted tests where possible.

- [ ] **Step 6: Format and commit**

Run:

```powershell
dart format lib/core/vault/vault_service.dart test/core/vault/vault_service_test.dart
git add lib/core/vault/vault_service.dart test/core/vault/vault_service_test.dart
git commit -m "feat: default vault metadata to argon2id"
```

---

### Task 4: Harden Android Biometric Secure Storage Options

**Files:**
- Modify: `lib/core/biometric/biometric_service.dart`
- Test: `test/core/biometric/biometric_service_test.dart`

- [ ] **Step 1: Write failing Android options test**

Add to `test/core/biometric/biometric_service_test.dart`:

```dart
  test('secure storage store uses biometric Android options', () {
    final options = SecureStorageDekStore.defaultAndroidOptionsForTest;
    final params = options.toMap();

    expect(params['storageNamespace'], 'secure_box_biometric');
    expect(params['enforceBiometrics'], 'true');
    expect(params['biometricPromptTitle'], 'Unlock Secure Box');
  });
```

Expected now: compile failure because `defaultAndroidOptionsForTest` does not exist, or failure because options are generic.

- [ ] **Step 2: Update read requirement expectation**

Change the existing test named `secure storage store requires explicit local auth prompt on Android and iOS` so Android expects store-managed auth:

```dart
      expect(
        SecureStorageDekStore().readRequirement,
        SecureDekReadRequirement.storeManagedAuthentication,
      );
```

Expected now: fails because production store still reports explicit auth.

- [ ] **Step 3: Expose default Android options for testing**

In `lib/core/biometric/biometric_service.dart`, change the private static options to a public test-visible constant:

```dart
  @visibleForTesting
  static const defaultAndroidOptionsForTest = _defaultAndroidOptions;
```

- [ ] **Step 4: Replace generic Android options with biometric options**

Change `_defaultAndroidOptions` to:

```dart
  static const _defaultAndroidOptions = AndroidOptions.biometric(
    storageNamespace: 'secure_box_biometric',
    enforceBiometrics: true,
    biometricPromptTitle: 'Unlock Secure Box',
    biometricPromptSubtitle: 'Authenticate to unlock your local vault',
    migrateWithBackup: true,
  );
```

This uses `flutter_secure_storage` 10.x biometric Android storage with strict biometric/device-security enforcement. On unsupported devices, store operations may throw; the existing `canUseBiometricProtection()` and `unlock()` paths catch that and fall back to the master password.

- [ ] **Step 5: Change production read requirement**

In `SecureStorageDekStore`, change:

```dart
  SecureDekReadRequirement get readRequirement =>
      SecureDekReadRequirement.explicitBiometricAuthentication;
```

to:

```dart
  SecureDekReadRequirement get readRequirement =>
      SecureDekReadRequirement.storeManagedAuthentication;
```

Expected: `BiometricService.unlock()` lets secure storage perform the biometric/device prompt while reading the DEK.

- [ ] **Step 6: Run biometric tests**

Run:

```powershell
flutter test --reporter compact test/core/biometric/biometric_service_test.dart
```

Expected: biometric tests pass.

- [ ] **Step 7: Format and commit**

Run:

```powershell
dart format lib/core/biometric/biometric_service.dart test/core/biometric/biometric_service_test.dart
git add lib/core/biometric/biometric_service.dart test/core/biometric/biometric_service_test.dart
git commit -m "fix: require biometric secure storage for dek copy"
```

---

### Task 5: Update Documentation And Run Final Verification

**Files:**
- Modify: `docs/security-check.md`

- [ ] **Step 1: Update security documentation**

Edit `docs/security-check.md`:

- Replace the residual note that says Argon2id is deferred.
- Add that Argon2id is now the default KDF for new and rotated vaults.
- Add that PBKDF2-HMAC-SHA256 remains supported only for existing vault metadata and imported legacy backups.
- Add that Android biometric storage uses `AndroidOptions.biometric(enforceBiometrics: true)` for the DEK copy and falls back to master password on failure.

- [ ] **Step 2: Run full tests**

Run:

```powershell
flutter test --reporter compact
```

Expected: all tests pass.

- [ ] **Step 3: Run analyzer**

Run:

```powershell
flutter analyze
```

Expected: no issues found.

- [ ] **Step 4: Run security scans**

Run:

```powershell
rg -n "MD5|SHA1|sha1|sha256\(|print\(|debugPrint\(|log\(|password|masterPassword|secret" lib test
rg -n "CREATE TABLE vault_items|username|password|notes|title" lib/data/db lib/data/models
rg -n "android.permission.INTERNET" android
```

Expected:

- `sha256` appears only in PBKDF2-HMAC-SHA256 configuration/tests, not direct master-password hashing.
- Sensitive names appear only as parameter names, UI labels/controllers, decrypted model fields, and tests.
- No sensitive logging calls are present.
- `vault_items` still contains only encrypted columns plus metadata.
- No Android INTERNET permission is present.

- [ ] **Step 5: Commit**

```powershell
git add docs/security-check.md
git commit -m "docs: update security hardening verification"
```

---

## Self-Review

Spec coverage:

- Argon2id support: Tasks 1 and 2.
- Argon2id default for new vaults: Task 3.
- PBKDF2 compatibility: Task 3 retains metadata-driven unlock and adds a PBKDF2 fixture test.
- PBKDF2-to-Argon2id migration on password change: Task 3.
- Biometric secure storage hardening: Task 4.
- Master-password fallback: Task 4 keeps existing fallback behavior and tests store/auth failure paths.
- Documentation and verification: Task 5.

Placeholder scan:

- The plan contains no TBD/TODO placeholders.
- Every task has exact files, commands, and expected results.

Type consistency:

- `KdfParams.memoryKiB` and `KdfParams.parallelism` are introduced before tests and vault metadata reference them.
- `SecureStorageDekStore.defaultAndroidOptionsForTest` is introduced before the test uses it.
- `SecureDekReadRequirement.storeManagedAuthentication` already exists and is reused.
