import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/sync/sync_credential_store.dart';
import 'package:secure_box/core/sync/sync_models.dart';

void main() {
  test('stores and reads auth tokens and device id', () async {
    final storage = InMemorySyncSecureStorage();
    final store = SyncCredentialStore(storage);
    const tokens = SyncAuthTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      tokenType: 'bearer',
    );

    await store.saveTokens(tokens);
    await store.saveDeviceId('device-1');

    expect((await store.readTokens())?.accessToken, 'access');
    expect((await store.readTokens())?.refreshToken, 'refresh');
    expect(await store.readDeviceId(), 'device-1');
  });

  test('clear deletes token and device credentials', () async {
    final storage = InMemorySyncSecureStorage();
    final store = SyncCredentialStore(storage);
    const tokens = SyncAuthTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      tokenType: 'bearer',
    );

    await store.saveTokens(tokens);
    await store.saveDeviceId('device-1');
    await store.clear();

    expect(await store.readTokens(), isNull);
    expect(await store.readDeviceId(), isNull);
    expect(
      storage.deletedKeys,
      containsAll(['sync.auth_tokens', 'sync.device_id']),
    );
  });
}

class InMemorySyncSecureStorage implements SyncSecureStorage {
  final Map<String, String> values = {};
  final List<String> deletedKeys = [];

  @override
  Future<void> delete({required String key}) async {
    deletedKeys.add(key);
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
