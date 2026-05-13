import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';

void main() {
  test('enable stores 32-byte DEK copy and disable removes it', () async {
    final auth = _RecordingBiometricAuthenticator();
    final store = _TestSecureDekStore();
    final service = BiometricService(authenticator: auth, store: store);
    final dek = Uint8List.fromList(List<int>.generate(32, (index) => index));

    await service.enable(dek);
    expect(await store.readDek(), orderedEquals(dek));

    await service.disable();
    expect(await store.readDek(), isNull);
  });

  test('enable rejects DEKs that are not 32 bytes', () async {
    final service = BiometricService(
      authenticator: _RecordingBiometricAuthenticator(),
      store: _TestSecureDekStore(),
    );

    expect(
      () => service.enable(Uint8List.fromList([1, 2, 3, 4])),
      throwsArgumentError,
    );
  });

  test(
    'enable rejects biometric setup when secure store protection is unavailable',
    () async {
      final auth = _RecordingBiometricAuthenticator();
      final store = _TestSecureDekStore(canUseBiometricProtectionResult: false);
      final service = BiometricService(authenticator: auth, store: store);
      final dek = Uint8List.fromList(List<int>.filled(32, 7));

      await expectLater(service.enable(dek), throwsStateError);
      expect(store.writeCalls, 0);
    },
  );

  test('failed biometric returns fallback result with no DEK', () async {
    final service = BiometricService(
      authenticator: _RecordingBiometricAuthenticator(
        authenticateResult: false,
      ),
      store: _TestSecureDekStore(
        initialDek: Uint8List.fromList(List<int>.filled(32, 9)),
      ),
    );

    final result = await service.unlock();
    expect(result.status, BiometricUnlockStatus.fallbackToMasterPassword);
    expect(result.dek, isNull);
  });

  test('missing stored DEK returns fallback result', () async {
    final service = BiometricService(
      authenticator: _RecordingBiometricAuthenticator(),
      store: _TestSecureDekStore(),
    );

    final result = await service.unlock();
    expect(result.status, BiometricUnlockStatus.fallbackToMasterPassword);
    expect(result.dek, isNull);
  });

  test('invalid stored DEK length returns fallback result', () async {
    final service = BiometricService(
      authenticator: _RecordingBiometricAuthenticator(),
      store: _TestSecureDekStore(
        initialDek: Uint8List.fromList(List<int>.filled(31, 7)),
      ),
    );

    final result = await service.unlock();
    expect(result.status, BiometricUnlockStatus.fallbackToMasterPassword);
    expect(result.dek, isNull);
  });

  test('successful biometric returns unlocked result with DEK', () async {
    final dek = Uint8List.fromList(List<int>.generate(32, (index) => index));
    final auth = _RecordingBiometricAuthenticator();
    final service = BiometricService(
      authenticator: auth,
      store: _TestSecureDekStore(initialDek: dek),
    );

    final result = await service.unlock();
    expect(result.status, BiometricUnlockStatus.unlocked);
    expect(result.dek, orderedEquals(dek));
    expect(auth.authenticateCalls, 1);
  });

  test(
    'successful biometric unlock skips explicit authenticate when store protects the read',
    () async {
      final dek = Uint8List.fromList(
        List<int>.generate(32, (index) => 255 - index),
      );
      final auth = _RecordingBiometricAuthenticator(
        authenticateError: StateError('authenticate should not be called'),
      );
      final store = _TestSecureDekStore(
        readRequirement: SecureDekReadRequirement.storeManagedAuthentication,
        initialDek: dek,
      );
      final service = BiometricService(authenticator: auth, store: store);

      final result = await service.unlock();

      expect(result.status, BiometricUnlockStatus.unlocked);
      expect(result.dek, orderedEquals(dek));
      expect(auth.authenticateCalls, 0);
      expect(store.readCalls, 1);
    },
  );

  test('thrown canAuthenticate returns fallback result', () async {
    final auth = _RecordingBiometricAuthenticator(
      canAuthenticateError: StateError('hardware query failed'),
    );
    final store = _TestSecureDekStore(
      initialDek: Uint8List.fromList(List<int>.filled(32, 3)),
    );
    final service = BiometricService(authenticator: auth, store: store);

    final result = await service.unlock();

    expect(result.status, BiometricUnlockStatus.fallbackToMasterPassword);
    expect(result.dek, isNull);
    expect(auth.authenticateCalls, 0);
    expect(store.readCalls, 0);
  });

  test('thrown authenticate returns fallback result', () async {
    final auth = _RecordingBiometricAuthenticator(
      authenticateError: StateError('prompt failed'),
    );
    final store = _TestSecureDekStore(
      initialDek: Uint8List.fromList(List<int>.filled(32, 4)),
    );
    final service = BiometricService(authenticator: auth, store: store);

    final result = await service.unlock();

    expect(result.status, BiometricUnlockStatus.fallbackToMasterPassword);
    expect(result.dek, isNull);
    expect(store.readCalls, 0);
  });

  test('thrown readDek returns fallback result', () async {
    final service = BiometricService(
      authenticator: _RecordingBiometricAuthenticator(),
      store: _TestSecureDekStore(readError: StateError('read failed')),
    );

    final result = await service.unlock();

    expect(result.status, BiometricUnlockStatus.fallbackToMasterPassword);
    expect(result.dek, isNull);
  });

  test(
    'thrown secure store capability check returns fallback result',
    () async {
      final auth = _RecordingBiometricAuthenticator();
      final store = _TestSecureDekStore(
        capabilityError: StateError('capability probe failed'),
        initialDek: Uint8List.fromList(List<int>.filled(32, 5)),
      );
      final service = BiometricService(authenticator: auth, store: store);

      final result = await service.unlock();

      expect(result.status, BiometricUnlockStatus.fallbackToMasterPassword);
      expect(result.dek, isNull);
      expect(auth.authenticateCalls, 0);
      expect(store.readCalls, 0);
    },
  );

  test('store capability unavailable returns fallback result', () async {
    final auth = _RecordingBiometricAuthenticator();
    final store = _TestSecureDekStore(
      canUseBiometricProtectionResult: false,
      initialDek: Uint8List.fromList(List<int>.filled(32, 1)),
    );
    final service = BiometricService(authenticator: auth, store: store);

    final result = await service.unlock();

    expect(result.status, BiometricUnlockStatus.fallbackToMasterPassword);
    expect(result.dek, isNull);
    expect(auth.authenticateCalls, 0);
    expect(store.readCalls, 0);
  });

  test(
    'secure storage store requires explicit local auth prompt on Android and iOS',
    () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        SecureStorageDekStore().readRequirement,
        SecureDekReadRequirement.explicitBiometricAuthentication,
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        SecureStorageDekStore().readRequirement,
        SecureDekReadRequirement.explicitBiometricAuthentication,
      );
    },
  );

  test(
    'secure storage capability gate is conservative off Android and skips the storage probe',
    () async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final storage = _RecordingFlutterSecureStorage(containsKeyResult: true);
      final store = SecureStorageDekStore(storage: storage);

      expect(await store.canUseBiometricProtection(), isFalse);
      expect(storage.containsKeyCalls, 0);
    },
  );

  test(
    'secure storage capability gate probes Android storage support',
    () async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final storage = _RecordingFlutterSecureStorage(containsKeyResult: true);
      final store = SecureStorageDekStore(storage: storage);

      expect(await store.canUseBiometricProtection(), isTrue);
      expect(storage.containsKeyCalls, 1);
    },
  );

  test(
    'secure storage capability gate falls back when Android storage probe throws',
    () async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final storage = _RecordingFlutterSecureStorage(
        containsKeyError: StateError('storage unsupported'),
      );
      final store = SecureStorageDekStore(storage: storage);

      expect(await store.canUseBiometricProtection(), isFalse);
      expect(storage.containsKeyCalls, 1);
    },
  );
}

class _RecordingBiometricAuthenticator implements BiometricAuthenticator {
  _RecordingBiometricAuthenticator({
    this.authenticateResult = true,
    this.canAuthenticateError,
    this.authenticateError,
  });

  final bool authenticateResult;
  final Object? canAuthenticateError;
  final Object? authenticateError;

  int canAuthenticateCalls = 0;
  int authenticateCalls = 0;

  @override
  Future<bool> canAuthenticate() async {
    canAuthenticateCalls += 1;
    if (canAuthenticateError != null) {
      throw canAuthenticateError!;
    }

    return true;
  }

  @override
  Future<bool> authenticate() async {
    authenticateCalls += 1;
    if (authenticateError != null) {
      throw authenticateError!;
    }

    return authenticateResult;
  }
}

class _TestSecureDekStore implements SecureDekStore {
  _TestSecureDekStore({
    this.canUseBiometricProtectionResult = true,
    this.readRequirement =
        SecureDekReadRequirement.explicitBiometricAuthentication,
    Uint8List? initialDek,
    this.capabilityError,
    this.readError,
  }) : _dek = initialDek == null ? null : Uint8List.fromList(initialDek);

  final bool canUseBiometricProtectionResult;
  @override
  final SecureDekReadRequirement readRequirement;
  final Object? capabilityError;
  final Object? readError;

  Uint8List? _dek;
  int capabilityCalls = 0;
  int writeCalls = 0;
  int readCalls = 0;
  int deleteCalls = 0;

  @override
  Future<bool> canUseBiometricProtection() async {
    capabilityCalls += 1;
    if (capabilityError != null) {
      throw capabilityError!;
    }

    return canUseBiometricProtectionResult;
  }

  @override
  Future<void> writeDek(Uint8List dek) async {
    writeCalls += 1;
    _dek = Uint8List.fromList(dek);
  }

  @override
  Future<Uint8List?> readDek() async {
    readCalls += 1;
    if (readError != null) {
      throw readError!;
    }

    final dek = _dek;
    if (dek == null) {
      return null;
    }

    return Uint8List.fromList(dek);
  }

  @override
  Future<void> deleteDek() async {
    deleteCalls += 1;
    _dek = null;
  }
}

class _RecordingFlutterSecureStorage extends FlutterSecureStorage {
  _RecordingFlutterSecureStorage({
    this.containsKeyResult = false,
    this.containsKeyError,
  });

  final bool containsKeyResult;
  final Object? containsKeyError;

  int containsKeyCalls = 0;

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    containsKeyCalls += 1;
    if (containsKeyError != null) {
      throw containsKeyError!;
    }

    return containsKeyResult;
  }
}
