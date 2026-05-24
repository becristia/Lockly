import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/sync_service_factory.dart';
import 'package:secure_box/core/sync/sync_api_client.dart';
import 'package:secure_box/core/sync/sync_credential_store.dart';

void main() {
  test('production sync service wiring sends device platform and client version', () async {
    final storage = _MemorySyncSecureStorage();
    final requests = <SyncHttpRequest>[];
    final service = buildProductionSyncService(
      syncBaseUrl: 'https://sync.example.test',
      credentials: SyncCredentialStore(storage),
      deviceName: () => 'Work laptop',
      transport: (request) async {
        requests.add(request);
        if (request.url.path == '/auth/login') {
          return const SyncHttpResponse(200, {
            'access_token': 'access-token',
            'refresh_token': 'refresh-token',
            'token_type': 'bearer',
          });
        }
        if (request.url.path == '/devices/register') {
          return SyncHttpResponse(201, {
            'id': 'device-1',
            'device_name': 'Work laptop',
            'device_type': Platform.operatingSystem,
            'platform': Platform.operatingSystem,
            'client_version': locklyClientVersion,
            'trusted': true,
            'created_at': '2026-05-23T10:00:00Z',
          });
        }
        return const SyncHttpResponse(404, {
          'error': {'code': 'NOT_FOUND'},
        });
      },
    )!;

    await service.login(email: 'user@example.test', password: 'sync-password');

    final registerRequest = requests.singleWhere(
      (request) => request.url.path == '/devices/register',
    );
    expect(
      registerRequest.body,
      containsPair('device_type', Platform.operatingSystem),
    );
    expect(
      registerRequest.body,
      containsPair('platform', Platform.operatingSystem),
    );
    expect(
      registerRequest.body,
      containsPair('client_version', locklyClientVersion),
    );
  });
}

class _MemorySyncSecureStorage implements SyncSecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }
}
