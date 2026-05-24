import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:secure_box/core/sync/sync_models.dart';

abstract class SyncSecureStorage {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSyncSecureStorage implements SyncSecureStorage {
  FlutterSyncSecureStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }
}

class SyncCredentialStore {
  SyncCredentialStore(this._storage);

  static const authTokensKey = 'sync.auth_tokens';
  static const deviceIdKey = 'sync.device_id';
  static const deviceAccountEmailKey = 'sync.device_account_email';

  final SyncSecureStorage _storage;

  Future<SyncAuthTokens?> readTokens() async {
    final raw = await _storage.read(key: authTokensKey);
    if (raw == null) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid sync auth token payload');
    }
    return SyncAuthTokens.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<void> saveTokens(SyncAuthTokens tokens) {
    return _storage.write(
      key: authTokensKey,
      value: jsonEncode(tokens.toJson()),
    );
  }

  Future<String?> readDeviceId() => _storage.read(key: deviceIdKey);

  Future<void> saveDeviceId(String deviceId) {
    return _storage.write(key: deviceIdKey, value: deviceId);
  }

  Future<String?> readDeviceAccountEmail() {
    return _storage.read(key: deviceAccountEmailKey);
  }

  Future<void> saveDeviceAccountEmail(String email) {
    return _storage.write(key: deviceAccountEmailKey, value: email);
  }

  Future<void> deleteDeviceId() => _storage.delete(key: deviceIdKey);

  Future<void> clearDeviceRegistration() async {
    await _storage.delete(key: deviceIdKey);
    await _storage.delete(key: deviceAccountEmailKey);
  }

  Future<void> clear() async {
    await _storage.delete(key: authTokensKey);
    await _storage.delete(key: deviceIdKey);
    await _storage.delete(key: deviceAccountEmailKey);
  }
}
