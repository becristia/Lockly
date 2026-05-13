import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:secure_box/core/crypto/encoding.dart';

enum BiometricUnlockResult { unlocked, fallbackToMasterPassword }

abstract class BiometricAuthenticator {
  Future<bool> canAuthenticate();

  Future<bool> authenticate();
}

abstract class SecureDekStore {
  Future<void> writeDek(Uint8List dek);

  Future<Uint8List?> readDek();

  Future<void> deleteDek();
}

class BiometricService {
  BiometricService({required this.authenticator, required this.store});

  final BiometricAuthenticator authenticator;
  final SecureDekStore store;

  Future<void> enable(Uint8List dek) async {
    if (!await _canAuthenticate()) {
      throw StateError('Biometric authentication is unavailable');
    }

    await store.writeDek(Uint8List.fromList(dek));
  }

  Future<void> disable() {
    return store.deleteDek();
  }

  Future<BiometricUnlockResult> unlock() async {
    if (!await _canAuthenticate()) {
      return BiometricUnlockResult.fallbackToMasterPassword;
    }
    if (!await _authenticate()) {
      return BiometricUnlockResult.fallbackToMasterPassword;
    }

    try {
      final dek = await store.readDek();
      if (dek == null) {
        return BiometricUnlockResult.fallbackToMasterPassword;
      }
    } catch (_) {
      return BiometricUnlockResult.fallbackToMasterPassword;
    }

    return BiometricUnlockResult.unlocked;
  }

  Future<bool> _canAuthenticate() async {
    try {
      return await authenticator.canAuthenticate();
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

class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator({
    LocalAuthentication? localAuth,
    this.localizedReason = 'Authenticate to unlock Secure Box',
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
    String key = _defaultDekKey,
  }) : _storage =
           storage ?? const FlutterSecureStorage(aOptions: _androidOptions),
       _key = key;

  static const _defaultDekKey = 'biometric_dek';
  static const _androidOptions = AndroidOptions.biometric(
    enforceBiometrics: true,
    storageNamespace: 'secure_box_biometric',
    biometricPromptTitle: 'Unlock Secure Box',
    biometricPromptSubtitle: 'Authenticate to unlock your local vault',
  );

  final FlutterSecureStorage _storage;
  final String _key;

  @override
  Future<void> writeDek(Uint8List dek) {
    return _storage.write(key: _key, value: b64(Uint8List.fromList(dek)));
  }

  @override
  Future<Uint8List?> readDek() async {
    final storedValue = await _storage.read(key: _key);
    if (storedValue == null) {
      return null;
    }

    return fromB64(storedValue);
  }

  @override
  Future<void> deleteDek() {
    return _storage.delete(key: _key);
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
