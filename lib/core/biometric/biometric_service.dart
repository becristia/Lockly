import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:secure_box/core/crypto/encoding.dart';

const _dekLength = 32;

enum BiometricUnlockStatus { unlocked, fallbackToMasterPassword }

class BiometricUnlockResult {
  const BiometricUnlockResult._({required this.status, this.dek});

  factory BiometricUnlockResult.unlocked(Uint8List dek) {
    _requireValidDek(dek);
    return BiometricUnlockResult._(
      status: BiometricUnlockStatus.unlocked,
      dek: Uint8List.fromList(dek),
    );
  }

  const BiometricUnlockResult.fallbackToMasterPassword()
    : status = BiometricUnlockStatus.fallbackToMasterPassword,
      dek = null;

  final BiometricUnlockStatus status;
  final Uint8List? dek;
}

abstract class BiometricAuthenticator {
  Future<bool> canAuthenticate();

  Future<bool> authenticate();
}

enum SecureDekReadRequirement {
  explicitBiometricAuthentication,
  storeManagedAuthentication,
}

abstract class SecureDekStore {
  SecureDekReadRequirement get readRequirement;

  Future<bool> canUseBiometricProtection();

  Future<void> writeDek(Uint8List dek);

  Future<Uint8List?> readDek();

  Future<void> deleteDek();
}

class BiometricService {
  BiometricService({required this.authenticator, required this.store});

  final BiometricAuthenticator authenticator;
  final SecureDekStore store;

  Future<void> enable(Uint8List dek) async {
    _requireValidDek(dek);

    if (!await _canAuthenticate()) {
      throw StateError('Biometric authentication is unavailable');
    }

    final copy = Uint8List.fromList(dek);
    try {
      await store.writeDek(copy);
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  }

  Future<void> disable() {
    return store.deleteDek();
  }

  Future<BiometricUnlockResult> unlock() async {
    if (!await _canAuthenticate()) {
      return const BiometricUnlockResult.fallbackToMasterPassword();
    }
    if (store.readRequirement ==
            SecureDekReadRequirement.explicitBiometricAuthentication &&
        !await _authenticate()) {
      return const BiometricUnlockResult.fallbackToMasterPassword();
    }

    try {
      final dek = await store.readDek();
      if (dek == null) {
        return const BiometricUnlockResult.fallbackToMasterPassword();
      }

      try {
        if (dek.length != _dekLength) {
          return const BiometricUnlockResult.fallbackToMasterPassword();
        }

        return BiometricUnlockResult.unlocked(dek);
      } finally {
        dek.fillRange(0, dek.length, 0);
      }
    } catch (_) {
      return const BiometricUnlockResult.fallbackToMasterPassword();
    }
  }

  Future<bool> _canAuthenticate() async {
    try {
      if (!await authenticator.canAuthenticate()) {
        return false;
      }
    } catch (_) {
      return false;
    }

    try {
      return await store.canUseBiometricProtection();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authenticate() async {
    try {
      return await authenticator.authenticate();
    } catch (_) {
      return false;
    }
  }
}

bool _isValidDek(Uint8List? dek) {
  return dek != null && dek.length == _dekLength;
}

void _requireValidDek(Uint8List dek) {
  if (_isValidDek(dek)) {
    return;
  }

  throw ArgumentError.value(
    dek.length,
    'dek',
    'DEK must be exactly $_dekLength bytes',
  );
}

class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator({
    LocalAuthentication? localAuth,
    this.localizedReason = 'Authenticate to unlock Lockly',
  }) : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;
  final String localizedReason;

  @override
  Future<bool> canAuthenticate() async {
    final canCheckBiometrics = await _localAuth.canCheckBiometrics;
    if (!canCheckBiometrics) {
      return false;
    }

    final biometrics = await _localAuth.getAvailableBiometrics();
    return biometrics.isNotEmpty;
  }

  @override
  Future<bool> authenticate() {
    return _localAuth.authenticate(
      localizedReason: localizedReason,
      biometricOnly: true,
      persistAcrossBackgrounding: true,
    );
  }
}

class SecureStorageDekStore implements SecureDekStore {
  SecureStorageDekStore({
    FlutterSecureStorage? storage,
    AndroidOptions androidOptions = _defaultAndroidOptions,
    String key = _defaultDekKey,
  }) : _storage = storage ?? FlutterSecureStorage(aOptions: androidOptions),
       _options = androidOptions,
       _key = key;

  static const _defaultDekKey = 'biometric_dek';
  static const _defaultAndroidOptions = AndroidOptions.biometric(
    storageNamespace: 'secure_box_biometric',
    enforceBiometrics: true,
    biometricPromptTitle: 'Unlock Lockly',
    biometricPromptSubtitle: 'Authenticate to unlock your local vault',
    migrateWithBackup: false,
  );
  @visibleForTesting
  static const defaultAndroidOptionsForTest = _defaultAndroidOptions;

  final FlutterSecureStorage _storage;
  final AndroidOptions _options;
  final String _key;

  @override
  SecureDekReadRequirement get readRequirement =>
      SecureDekReadRequirement.explicitBiometricAuthentication;

  @override
  Future<bool> canUseBiometricProtection() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      await _storage.containsKey(key: _key, aOptions: _options);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> writeDek(Uint8List dek) {
    return _storage.write(
      key: _key,
      value: b64(Uint8List.fromList(dek)),
      aOptions: _options,
    );
  }

  @override
  Future<Uint8List?> readDek() async {
    final storedValue = await _storage.read(key: _key, aOptions: _options);
    if (storedValue == null) {
      return null;
    }

    return fromB64(storedValue);
  }

  @override
  Future<void> deleteDek() {
    return _storage.delete(key: _key, aOptions: _options);
  }
}

class FakeBiometricAuthenticator implements BiometricAuthenticator {
  FakeBiometricAuthenticator({
    required bool canAuthenticate,
    required this.succeeds,
  }) : _canAuthenticate = canAuthenticate;

  final bool _canAuthenticate;
  final bool succeeds;

  @override
  Future<bool> canAuthenticate() async {
    return _canAuthenticate;
  }

  @override
  Future<bool> authenticate() async {
    return succeeds;
  }
}

class MemorySecureDekStore implements SecureDekStore {
  Uint8List? _dek;

  @override
  SecureDekReadRequirement get readRequirement =>
      SecureDekReadRequirement.explicitBiometricAuthentication;

  @override
  Future<bool> canUseBiometricProtection() async {
    return true;
  }

  @override
  Future<void> writeDek(Uint8List dek) async {
    _dek = Uint8List.fromList(dek);
  }

  @override
  Future<Uint8List?> readDek() async {
    final dek = _dek;
    if (dek == null) {
      return null;
    }

    return Uint8List.fromList(dek);
  }

  @override
  Future<void> deleteDek() async {
    _dek = null;
  }
}
