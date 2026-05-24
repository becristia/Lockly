import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/sync/sync_api_client.dart';
import 'package:secure_box/core/sync/sync_models.dart';

void main() {
  test(
    'attaches authorization bearer header to authenticated requests',
    () async {
      final transport = _RecordingTransport({
        '/devices': SyncHttpResponse(200, {'items': <Object?>[]}),
      });
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      await client.listDevices(accessToken: 'access-token');

      expect(transport.single.headers['Authorization'], 'Bearer access-token');
    },
  );

  test(
    'register parses backend account response without assuming login',
    () async {
      final transport = _RecordingTransport({
        '/auth/register': SyncHttpResponse(201, {
          'id': 'user-1',
          'email': 'user@example.test',
        }),
      });
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      final account = await client.register(
        email: 'user@example.test',
        password: 'cloud-password',
      );

      expect(account.id, 'user-1');
      expect(account.email, 'user@example.test');
      expect(transport.single.body, {
        'email': 'user@example.test',
        'password': 'cloud-password',
      });
    },
  );

  test('logout sends refresh token body required by backend', () async {
    final transport = _RecordingTransport({
      '/auth/logout': SyncHttpResponse(200, {'ok': true}),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    await client.logout(accessToken: 'access-token', refreshToken: 'refresh');

    expect(transport.single.headers['Authorization'], 'Bearer access-token');
    expect(transport.single.body, {'refresh_token': 'refresh'});
  });

  test('listDevices parses backend items envelope', () async {
    final transport = _RecordingTransport({
      '/devices': SyncHttpResponse(200, {
        'items': [
          {
            'id': 'device-1',
            'device_name': 'Phone',
            'device_type': 'android',
            'trusted': true,
            'last_sync_at': null,
            'created_at': '2026-05-23T10:00:00Z',
            'revoked_at': null,
          },
        ],
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    final devices = await client.listDevices(accessToken: 'access-token');

    expect(devices.single.id, 'device-1');
    expect(devices.single.deviceName, 'Phone');
  });

  test('registerDevice sends optional platform and client version', () async {
    final transport = _RecordingTransport({
      '/devices/register': SyncHttpResponse(200, {
        'device': {
          'id': 'device-1',
          'device_name': 'Phone',
          'device_type': 'mobile',
          'platform': 'android',
          'client_version': '1.4.2',
          'trusted': true,
          'last_sync_at': null,
          'created_at': '2026-05-23T10:00:00Z',
          'revoked_at': null,
        },
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    final device = await client.registerDevice(
      accessToken: 'access-token',
      deviceName: 'Phone',
      deviceType: 'mobile',
      platform: 'android',
      clientVersion: '1.4.2',
    );

    expect(transport.single.method, 'POST');
    expect(transport.single.body, {
      'device_name': 'Phone',
      'device_type': 'mobile',
      'platform': 'android',
      'client_version': '1.4.2',
    });
    expect(device.platform, 'android');
    expect(device.clientVersion, '1.4.2');
  });

  test('getVaultMeta sends active device id as query parameter', () async {
    final transport = _RecordingTransport({
      'GET /vault/meta': SyncHttpResponse(200, {
        'vault': _vaultMetaJson(revision: 12),
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    final meta = await client.getVaultMeta(
      accessToken: 'access-token',
      deviceId: 'device-local',
    );

    expect(transport.single.method, 'GET');
    expect(transport.single.url.queryParameters, {'device_id': 'device-local'});
    expect(meta.revision, 12);
  });

  test('updateVaultMeta sends device id query and revision body', () async {
    final transport = _RecordingTransport({
      'PUT /vault/meta': SyncHttpResponse(200, {
        'vault': _vaultMetaJson(revision: 42),
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );
    final meta = _vaultMetaPayload(revision: 42);

    await client.updateVaultMeta(
      accessToken: 'access-token',
      deviceId: 'device-local',
      meta: meta,
    );

    expect(transport.single.method, 'PUT');
    expect(transport.single.url.queryParameters, {'device_id': 'device-local'});
    expect(transport.single.body?['revision'], 42);
    expect(transport.single.body?['manifest'], isA<Map<String, Object?>>());
  });

  test('initVault omits revision reserved for metadata updates', () async {
    final transport = _RecordingTransport({
      'POST /vault/init': SyncHttpResponse(201, {
        'vault': _vaultMetaJson(revision: 1),
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    await client.initVault(
      accessToken: 'access-token',
      meta: _vaultMetaPayload(revision: 9),
    );

    expect(transport.single.method, 'POST');
    expect(transport.single.body, isNot(containsPair('revision', 9)));
  });

  test(
    'non-item wrapped responses reject unsupported sibling fields',
    () async {
      final transport = _RecordingTransport({
        '/devices/register': SyncHttpResponse(200, {
          'device': {
            'id': 'device-1',
            'device_name': 'Phone',
            'device_type': 'mobile',
            'platform': 'android',
            'client_version': '1.4.2',
            'trusted': true,
            'last_sync_at': null,
            'created_at': '2026-05-23T10:00:00Z',
            'revoked_at': null,
          },
          'password': 'clear-password',
        }),
      });
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      await expectLater(
        () => client.registerDevice(
          accessToken: 'access-token',
          deviceName: 'Phone',
        ),
        throwsFormatException,
      );
    },
  );

  test('listDevices rejects unsupported top-level response fields', () async {
    final transport = _RecordingTransport({
      '/devices': SyncHttpResponse(200, {
        'items': <Object?>[],
        'master_key': 'raw-master-key',
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    await expectLater(
      () => client.listDevices(accessToken: 'access-token'),
      throwsFormatException,
    );
  });

  test('renameDevice patches the backend device name', () async {
    final transport = _RecordingTransport({
      '/devices/device-1': SyncHttpResponse(200, {
        'device': {
          'id': 'device-1',
          'device_name': 'Travel laptop',
          'device_type': 'desktop',
          'platform': 'windows',
          'client_version': '1.4.2',
          'trusted': true,
          'last_sync_at': '2026-05-23T09:00:00Z',
          'created_at': '2026-05-22T09:00:00Z',
          'revoked_at': null,
        },
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    final device = await client.renameDevice(
      accessToken: 'access-token',
      deviceId: 'device-1',
      deviceName: 'Travel laptop',
    );

    expect(transport.single.method, 'PATCH');
    expect(transport.single.url.path, '/devices/device-1');
    expect(transport.single.body, {'device_name': 'Travel laptop'});
    expect(device.deviceName, 'Travel laptop');
  });

  test('pull sends since and device_id query parameters', () async {
    final transport = _RecordingTransport({
      '/sync/pull': SyncHttpResponse(200, {
        'server_time': '2026-05-23T10:00:00Z',
        'items': <Object?>[],
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test/api'),
      transport: transport.call,
    );

    await client.pull(
      accessToken: 'access-token',
      since: '2026-05-23T09:00:00Z',
      deviceId: 'device-1',
    );

    final request = transport.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/api/sync/pull');
    expect(request.url.queryParameters, {
      'since': '2026-05-23T09:00:00Z',
      'device_id': 'device-1',
    });
  });

  test('rejects forbidden push payload before sending a request', () async {
    final transport = _RecordingTransport({});
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    expect(
      () => client.pushRaw(
        accessToken: 'access-token',
        deviceId: 'device-1',
        items: [
          {
            'item_id': 'item-1',
            'ciphertext': 'ciphertext',
            'password': 'clear-text',
          },
        ],
      ),
      throwsStateError,
    );
    expect(transport.requests, isEmpty);
  });

  test('rejects unsafe push aad before sending a request', () async {
    final transport = _RecordingTransport({});
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    await expectLater(
      () => client.pushRaw(
        accessToken: 'access-token',
        deviceId: 'device-1',
        items: [
          {
            'item_id': 'item-1',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
            'aad':
                '{"mac":"password=plaintext-secret","schema":"lockly-item-v1"}',
            'revision': 1,
            'deleted': false,
            'client_updated_at': '2026-05-23T09:00:00Z',
          },
        ],
      ),
      throwsStateError,
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'rejects compound sensitive push fields before sending a request',
    () async {
      final transport = _RecordingTransport({});
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      await expectLater(
        () => client.pushRaw(
          accessToken: 'access-token',
          deviceId: 'device-1',
          items: [
            {
              'item_id': 'item-1',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
              'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
              'revision': 1,
              'deleted': false,
              'client_updated_at': '2026-05-23T09:00:00Z',
              'api_key': 'raw-api-key',
            },
          ],
        ),
        throwsStateError,
      );
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'rejects unsupported raw push fields before sending a request',
    () async {
      final transport = _RecordingTransport({});
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      await expectLater(
        () => client.pushRaw(
          accessToken: 'access-token',
          deviceId: 'device-1',
          items: [
            {
              'item_id': 'item-1',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
              'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
              'revision': 1,
              'deleted': false,
              'client_updated_at': '2026-05-23T09:00:00Z',
              'title': 'Bank',
            },
          ],
        ),
        throwsStateError,
      );
      expect(transport.requests, isEmpty);
    },
  );

  test('rejects unsafe raw push item ids before sending a request', () async {
    final transport = _RecordingTransport({});
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    await expectLater(
      () => client.pushRaw(
        accessToken: 'access-token',
        deviceId: 'device-1',
        items: [
          {
            'item_id': 'username-note-password',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
            'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
            'revision': 1,
            'deleted': false,
            'client_updated_at': '2026-05-23T09:00:00Z',
          },
        ],
      ),
      throwsStateError,
    );
    expect(transport.requests, isEmpty);
  });

  test('push parses applied item list and conflicts', () async {
    final transport = _RecordingTransport({
      '/sync/push': SyncHttpResponse(200, {
        'server_time': '2026-05-23T10:00:00Z',
        'applied': [
          {
            'item_id': 'item-1',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
            'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
            'revision': 2,
            'deleted': false,
            'client_updated_at': '2026-05-23T09:00:00Z',
            'server_updated_at': '2026-05-23T10:00:00Z',
          },
        ],
        'conflicts': [
          {'item_id': 'item-2', 'client_revision': 1, 'server_revision': 3},
        ],
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    final response = await client.push(
      accessToken: 'access-token',
      deviceId: 'device-1',
      items: [
        SyncItem(
          id: 'item-1',
          payload: SyncItemPayload.fromJson({
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
            'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
            'revision': 1,
            'deleted': false,
            'client_updated_at': '2026-05-23T09:00:00Z',
          }),
        ),
      ],
    );

    expect(response.serverTime, '2026-05-23T10:00:00Z');
    expect(response.applied.single.id, 'item-1');
    expect(response.conflicts.single.remoteRevision, 3);
    expect(transport.single.body?['device_id'], 'device-1');
  });

  test('push preserves backend 409 conflict response', () async {
    final transport = _RecordingTransport({
      '/sync/push': SyncHttpResponse(409, {
        'applied': <Object?>[],
        'conflicts': [
          {'item_id': 'item-2', 'client_revision': 1, 'server_revision': 3},
        ],
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    final response = await client.push(
      accessToken: 'access-token',
      deviceId: 'device-1',
      items: [
        SyncItem(
          id: 'item-2',
          payload: SyncItemPayload.fromJson({
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
            'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
            'revision': 1,
            'deleted': false,
            'client_updated_at': '2026-05-23T09:00:00Z',
          }),
        ),
      ],
    );

    expect(response.applied, isEmpty);
    expect(response.conflicts.single.itemId, 'item-2');
    expect(response.conflicts.single.remoteRevision, 3);
  });

  test(
    'pushBlobs sends encrypted blobs and parses metadata-only conflicts',
    () async {
      final transport = _RecordingTransport({
        '/blobs/push': SyncHttpResponse(409, {
          'applied': <Object?>[],
          'conflicts': [
            {'blob_id': 'blob-1', 'client_revision': 1, 'server_revision': 3},
          ],
        }),
      });
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      final response = await client.pushBlobs(
        accessToken: 'access-token',
        deviceId: 'device-1',
        blobs: [SyncBlob.fromJson(_safeBlobJson(revision: 1))],
      );

      expect(transport.single.method, 'POST');
      expect(transport.single.url.path, '/blobs/push');
      expect(transport.single.body?['device_id'], 'device-1');
      expect(response.applied, isEmpty);
      expect(response.conflicts.single.blobId, 'blob-1');
      expect(response.conflicts.single.remoteRevision, 3);
      expect(
        response.conflicts.single.toJson().containsKey('ciphertext'),
        isFalse,
      );
    },
  );

  test('pushRawBlobs rejects unsafe blob fields before sending', () async {
    final transport = _RecordingTransport({});
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    for (final field in [
      'filename',
      'plaintext',
      'file_bytes',
      'raw_key',
      'attachment_plaintext',
    ]) {
      await expectLater(
        () => client.pushRawBlobs(
          accessToken: 'access-token',
          deviceId: 'device-1',
          blobs: [
            {..._safeBlobJson(), field: 'unsafe'},
          ],
        ),
        throwsStateError,
      );
    }
    expect(transport.requests, isEmpty);
  });

  test(
    'pullBlobs sends cursor and rejects plaintext-shaped responses',
    () async {
      final transport = _RecordingTransport({
        '/blobs/pull': SyncHttpResponse(200, {
          'server_time': '2026-05-23T10:00:00Z',
          'blobs': [
            {..._safeBlobJson(), 'file_bytes': 'plain'},
          ],
        }),
      });
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test/api'),
        transport: transport.call,
      );

      await expectLater(
        () => client.pullBlobs(
          accessToken: 'access-token',
          since: '2026-05-23T09:00:00Z',
          deviceId: 'device-1',
        ),
        throwsFormatException,
      );

      final request = transport.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/api/blobs/pull');
      expect(request.url.queryParameters, {
        'since': '2026-05-23T09:00:00Z',
        'device_id': 'device-1',
      });
    },
  );

  test('create and list emergency contacts use backend contract', () async {
    final transport = _RecordingTransport({
      'POST /emergency/contacts': SyncHttpResponse(201, _safeContactJson()),
      'GET /emergency/contacts': SyncHttpResponse(200, {
        'items': [_safeContactJson()],
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test/api'),
      transport: transport.call,
    );

    final created = await client.createEmergencyContact(
      accessToken: 'access-token',
      request: const EmergencyContactCreateRequest(
        recipientEmail: 'trusted@example.test',
        recipientPublicKey: 'recipient-public-key-token',
        recipientKeyFingerprint: 'fingerprint-1',
        recipientLabel: 'Trusted contact',
      ),
    );
    final contacts = await client.listEmergencyContacts(
      accessToken: 'access-token',
    );

    expect(created.id, 'contact-1');
    expect(contacts.single.id, 'contact-1');
    expect(transport.requests[0].method, 'POST');
    expect(transport.requests[0].url.path, '/api/emergency/contacts');
    expect(transport.requests[0].body, {
      'recipient_email': 'trusted@example.test',
      'recipient_public_key': 'recipient-public-key-token',
      'recipient_key_fingerprint': 'fingerprint-1',
      'recipient_label': 'Trusted contact',
    });
    expect(transport.requests[1].method, 'GET');
    expect(transport.requests[1].url.path, '/api/emergency/contacts');
  });

  test(
    'create emergency grant rejects plaintext package before transport',
    () async {
      final transport = _RecordingTransport({});
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      await expectLater(
        () => client.createEmergencyGrant(
          accessToken: 'access-token',
          request: const EmergencyGrantCreateRequest(
            contactId: 'contact-1',
            waitingPeriodHours: 48,
            encryptedRecoveryPackage:
                '{"ciphertext":"cipher","nonce":"nonce","mac":"mac","plaintext":"clear"}',
            packageAad: _safeEmergencyPackageAad,
            packageFingerprint: 'package-fingerprint-1',
          ),
        ),
        throwsStateError,
      );
      expect(transport.requests, isEmpty);
    },
  );

  test('emergency grant metadata rejects package body in responses', () async {
    final transport = _RecordingTransport({
      'POST /emergency/grants': SyncHttpResponse(201, {
        ..._safeEmergencyGrantJson(),
        'encrypted_recovery_package': _safeEmergencyPackageEnvelope,
      }),
      'GET /emergency/grants': SyncHttpResponse(200, {
        'items': [
          {
            ..._safeEmergencyGrantJson(),
            'encrypted_recovery_package': _safeEmergencyPackageEnvelope,
          },
        ],
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    await expectLater(
      () => client.createEmergencyGrant(
        accessToken: 'access-token',
        request: const EmergencyGrantCreateRequest(
          contactId: 'contact-1',
          waitingPeriodHours: 48,
          encryptedRecoveryPackage: _safeEmergencyPackageEnvelope,
          packageAad: _safeEmergencyPackageAad,
          packageFingerprint: 'package-fingerprint-1',
        ),
      ),
      throwsFormatException,
    );
    await expectLater(
      () => client.listEmergencyGrants(accessToken: 'access-token'),
      throwsFormatException,
    );
  });

  test(
    'download emergency package accepts encrypted recovery package',
    () async {
      final transport = _RecordingTransport({
        '/emergency/grants/grant-1/package': SyncHttpResponse(200, {
          'grant_id': 'grant-1',
          'owner_user_id': 'owner-1',
          'recipient_user_id': 'recipient-1',
          'contact_id': 'contact-1',
          'status': 'downloaded',
          'encrypted_recovery_package': _safeEmergencyPackageEnvelope,
          'package_aad': _safeEmergencyPackageAad,
          'package_fingerprint': 'package-fingerprint-1',
          'recipient_key_fingerprint': 'fingerprint-1',
          'downloaded_at': '2026-05-24T10:00:00Z',
        }),
      });
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      final package = await client.downloadEmergencyAccessPackage(
        accessToken: 'access-token',
        grantId: 'grant-1',
      );

      expect(transport.single.method, 'GET');
      expect(transport.single.url.path, '/emergency/grants/grant-1/package');
      expect(package.grantId, 'grant-1');
      expect(package.encryptedRecoveryPackage, _safeEmergencyPackageEnvelope);
    },
  );

  test(
    'download emergency package rejects plaintext recovery fields',
    () async {
      final transport = _RecordingTransport({
        '/emergency/grants/grant-1/package': SyncHttpResponse(200, {
          'grant_id': 'grant-1',
          'owner_user_id': 'owner-1',
          'recipient_user_id': 'recipient-1',
          'contact_id': 'contact-1',
          'status': 'downloaded',
          'encrypted_recovery_package': _safeEmergencyPackageEnvelope,
          'package_aad': _safeEmergencyPackageAad,
          'package_fingerprint': 'package-fingerprint-1',
          'recipient_key_fingerprint': 'fingerprint-1',
          'recovery_plaintext': 'clear recovery material',
        }),
      });
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      await expectLater(
        () => client.downloadEmergencyAccessPackage(
          accessToken: 'access-token',
          grantId: 'grant-1',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'emergency path ids reject unsafe path segments before transport',
    () async {
      Future<void> expectRejects(
        Future<void> Function(SyncApiClient client) call,
      ) async {
        final transport = _RecordingTransport({});
        final client = SyncApiClient(
          baseUrl: Uri.parse('https://sync.example.test'),
          transport: transport.call,
        );

        await expectLater(() => call(client), throwsStateError);
        expect(transport.requests, isEmpty);
      }

      for (final contactId in [
        'contact/1',
        'contact?x=1',
        'contact#fragment',
        '../contact-1',
        'master-password',
      ]) {
        await expectRejects(
          (client) => client.revokeEmergencyContact(
            accessToken: 'access-token',
            contactId: contactId,
          ),
        );
      }

      for (final grantId in [
        'grant/1',
        'grant?x=1',
        'grant#fragment',
        '../grant-1',
        'plaintext-secret',
      ]) {
        await expectRejects(
          (client) => client.downloadEmergencyAccessPackage(
            accessToken: 'access-token',
            grantId: grantId,
          ),
        );
      }
    },
  );

  test('all emergency grant path methods reject unsafe grant ids', () async {
    final calls = <Future<void> Function(SyncApiClient)>[
      (client) => client.acceptEmergencyGrant(
        accessToken: 'access-token',
        grantId: 'grant/../master-password',
        recipientKeyFingerprint: 'fingerprint-1',
      ),
      (client) => client.requestEmergencyGrantAccess(
        accessToken: 'access-token',
        grantId: 'grant/../master-password',
        requestMessageCiphertext: 'message-ciphertext',
        requestMessageAad:
            '{"schema":"lockly-emergency-request-v1","mac":"message-mac"}',
      ),
      (client) => client.cancelEmergencyGrant(
        accessToken: 'access-token',
        grantId: 'grant/../master-password',
      ),
      (client) => client.revokeEmergencyGrant(
        accessToken: 'access-token',
        grantId: 'grant/../master-password',
      ),
      (client) => client.downloadEmergencyAccessPackage(
        accessToken: 'access-token',
        grantId: 'grant/../master-password',
      ),
    ];

    for (final call in calls) {
      final transport = _RecordingTransport({});
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      await expectLater(() => call(client), throwsStateError);
      expect(transport.requests, isEmpty);
    }
  });

  test('emergency grant state changes use expected paths and bodies', () async {
    final transport = _RecordingTransport({
      'POST /emergency/grants/grant-1/accept': SyncHttpResponse(
        200,
        _safeEmergencyGrantJson(status: 'active'),
      ),
      'POST /emergency/grants/grant-1/request-access': SyncHttpResponse(
        200,
        _safeEmergencyGrantJson(status: 'access_requested'),
      ),
      'POST /emergency/grants/grant-1/cancel': SyncHttpResponse(
        200,
        _safeEmergencyGrantJson(status: 'cancelled'),
      ),
      'DELETE /emergency/grants/grant-1': SyncHttpResponse(
        200,
        _safeEmergencyGrantJson(status: 'revoked'),
      ),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    await client.acceptEmergencyGrant(
      accessToken: 'access-token',
      grantId: 'grant-1',
      recipientKeyFingerprint: 'fingerprint-1',
    );
    await client.requestEmergencyGrantAccess(
      accessToken: 'access-token',
      grantId: 'grant-1',
      requestMessageCiphertext: 'message-ciphertext',
      requestMessageAad:
          '{"schema":"lockly-emergency-request-v1","mac":"message-mac"}',
    );
    await client.cancelEmergencyGrant(
      accessToken: 'access-token',
      grantId: 'grant-1',
    );
    await client.revokeEmergencyGrant(
      accessToken: 'access-token',
      grantId: 'grant-1',
    );

    expect(
      transport.requests.map(
        (request) => '${request.method} ${request.url.path}',
      ),
      [
        'POST /emergency/grants/grant-1/accept',
        'POST /emergency/grants/grant-1/request-access',
        'POST /emergency/grants/grant-1/cancel',
        'DELETE /emergency/grants/grant-1',
      ],
    );
    expect(transport.requests[0].body, {
      'recipient_key_fingerprint': 'fingerprint-1',
    });
    expect(transport.requests[1].body, {
      'request_message_ciphertext': 'message-ciphertext',
      'request_message_aad':
          '{"schema":"lockly-emergency-request-v1","mac":"message-mac"}',
    });
    expect(transport.requests[2].body, isNull);
    expect(transport.requests[3].body, isNull);
  });

  test('pull rejects item responses with missing aad', () async {
    final transport = _RecordingTransport({
      '/sync/pull': SyncHttpResponse(200, {
        'server_time': '2026-05-23T10:00:00Z',
        'items': [
          {
            'item_id': 'item-1',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
            'revision': 1,
            'deleted': false,
            'client_updated_at': '2026-05-23T09:00:00Z',
            'server_updated_at': '2026-05-23T10:00:00Z',
          },
        ],
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    await expectLater(
      () => client.pull(
        accessToken: 'access-token',
        since: '2026-05-23T09:00:00Z',
        deviceId: 'device-1',
      ),
      throwsFormatException,
    );
  });

  test('pull rejects item responses with extra plaintext fields', () async {
    final transport = _RecordingTransport({
      '/sync/pull': SyncHttpResponse(200, {
        'server_time': '2026-05-23T10:00:00Z',
        'items': [
          {
            'item_id': 'item-1',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
            'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
            'revision': 1,
            'deleted': false,
            'client_updated_at': '2026-05-23T09:00:00Z',
            'server_updated_at': '2026-05-23T10:00:00Z',
            'password': 'clear-password',
          },
        ],
      }),
    });
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: transport.call,
    );

    await expectLater(
      () => client.pull(
        accessToken: 'access-token',
        since: '2026-05-23T09:00:00Z',
        deviceId: 'device-1',
      ),
      throwsFormatException,
    );
  });

  test(
    'push rejects applied item responses with extra plaintext fields',
    () async {
      final transport = _RecordingTransport({
        '/sync/push': SyncHttpResponse(200, {
          'server_time': '2026-05-23T10:00:00Z',
          'applied': [
            {
              'item_id': 'item-1',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
              'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
              'revision': 2,
              'deleted': false,
              'client_updated_at': '2026-05-23T09:00:00Z',
              'server_updated_at': '2026-05-23T10:00:00Z',
              'master_key': 'raw-master-key',
            },
          ],
          'conflicts': <Object?>[],
        }),
      });
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      await expectLater(
        () => client.push(
          accessToken: 'access-token',
          deviceId: 'device-1',
          items: [
            SyncItem(
              id: 'item-1',
              payload: SyncItemPayload.fromJson({
                'ciphertext': 'ciphertext',
                'nonce': 'nonce',
                'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
                'revision': 1,
                'deleted': false,
                'client_updated_at': '2026-05-23T09:00:00Z',
              }),
            ),
          ],
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'error responses throw exception containing backend error code',
    () async {
      final transport = _RecordingTransport({
        '/vault/meta': SyncHttpResponse(401, {
          'error': {'code': 'TOKEN_EXPIRED', 'message': 'Token expired'},
        }),
      });
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: transport.call,
      );

      expect(
        () => client.getVaultMeta(
          accessToken: 'expired-token',
          deviceId: 'device-local',
        ),
        throwsA(
          isA<SyncApiException>().having(
            (error) => error.toString(),
            'message',
            contains('TOKEN_EXPIRED'),
          ),
        ),
      );
    },
  );

  test(
    'non-json error responses throw structured sync api exception',
    () async {
      final client = SyncApiClient(
        baseUrl: Uri.parse('https://sync.example.test'),
        transport: (_) async =>
            const SyncHttpResponse.raw(502, '<html>bad gateway</html>'),
      );

      await expectLater(
        client.login(email: 'user@example.test', password: 'account-password'),
        throwsA(
          isA<SyncApiException>()
              .having((error) => error.statusCode, 'statusCode', 502)
              .having((error) => error.code, 'code', 'HTTP_502'),
        ),
      );
    },
  );

  test('non-json push conflict responses throw sync api exception', () async {
    final client = SyncApiClient(
      baseUrl: Uri.parse('https://sync.example.test'),
      transport: (_) async =>
          const SyncHttpResponse.raw(409, '<html>conflict</html>'),
    );

    await expectLater(
      client.pushRaw(
        accessToken: 'access-token',
        deviceId: 'device-1',
        items: [
          {
            'item_id': 'item-1',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
            'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
            'revision': 0,
            'deleted': false,
            'client_updated_at': '2026-05-23T00:00:00Z',
          },
        ],
      ),
      throwsA(
        isA<SyncApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.code, 'code', 'HTTP_409'),
      ),
    );
  });
}

class _RecordingTransport {
  _RecordingTransport(this.responses);

  final Map<String, SyncHttpResponse> responses;
  final List<SyncHttpRequest> requests = [];

  SyncHttpRequest get single => requests.single;

  Future<SyncHttpResponse> call(SyncHttpRequest request) async {
    requests.add(request);
    final normalizedPath = request.url.path.replaceFirst('/api', '');
    return responses['${request.method} $normalizedPath'] ??
        responses[normalizedPath] ??
        SyncHttpResponse(404, {
          'error': {'code': 'NOT_FOUND'},
        });
  }
}

SyncVaultMetaPayload _vaultMetaPayload({int revision = 7}) {
  return SyncVaultMetaPayload.fromJson(_vaultMetaJson(revision: revision));
}

Map<String, Object?> _vaultMetaJson({int revision = 7}) {
  return {
    'id': 'vault-1',
    'kdf': 'argon2id',
    'kdf_params': {
      'name': 'argon2id',
      'memoryKiB': 65536,
      'iterations': 3,
      'parallelism': 1,
      'bits': 256,
    },
    'salt': 'salt-b64',
    'encrypted_dek_by_master':
        '{"ciphertext":"dek-ciphertext","nonce":"dek-nonce","mac":"dek-mac"}',
    'manifest': {
      'version': 1,
      'epoch': 1,
      'counter': 5,
      'nonce': 'manifest-nonce',
      'ciphertext': 'manifest-ciphertext',
      'mac': 'manifest-mac',
      'updated_at': 1715552222,
    },
    'revision': revision,
    'created_at': '2026-05-13T10:00:00Z',
    'updated_at': '2026-05-13T10:05:00Z',
  };
}

Map<String, Object?> _safeBlobJson({int revision = 1}) {
  return {
    'blob_id': 'blob-1',
    'item_id': 'item-1',
    'metadata_ciphertext': 'meta-ciphertext',
    'metadata_nonce': 'meta-nonce',
    'metadata_aad': '{"mac":"meta-mac","schema":"lockly-blob-meta-v1"}',
    'ciphertext': 'content-ciphertext',
    'nonce': 'content-nonce',
    'aad': '{"mac":"content-mac","schema":"lockly-blob-v1"}',
    'ciphertext_sha256':
        '32e09955ad05411c67617336e6a7026bd1828b3453f15f427b87667a61960d6e',
    'ciphertext_size': 18,
    'revision': revision,
    'deleted': false,
    'client_updated_at': '2026-05-23T09:00:00Z',
    'server_updated_at': '2026-05-23T10:00:00Z',
  };
}

const String _safeEmergencyPackageEnvelope =
    '{"ciphertext":"emergency-ciphertext","nonce":"emergency-nonce","mac":"emergency-mac"}';

const String _safeEmergencyPackageAad =
    '{"schema":"lockly-emergency-package-v1","mac":"emergency-mac","grant_id":"grant-1","recipient_key_fingerprint":"fingerprint-1"}';

Map<String, Object?> _safeContactJson() {
  return {
    'id': 'contact-1',
    'owner_user_id': 'owner-1',
    'recipient_user_id': 'recipient-1',
    'recipient_email': 'trusted@example.test',
    'recipient_public_key': 'recipient-public-key-token',
    'recipient_key_fingerprint': 'fingerprint-1',
    'recipient_label': 'Trusted contact',
    'status': 'active',
    'created_at': '2026-05-24T08:00:00Z',
    'updated_at': '2026-05-24T08:00:00Z',
    'revoked_at': null,
  };
}

Map<String, Object?> _safeEmergencyGrantJson({
  String status = 'pending_acceptance',
}) {
  return {
    'id': 'grant-1',
    'owner_user_id': 'owner-1',
    'recipient_user_id': 'recipient-1',
    'contact_id': 'contact-1',
    'vault_id': 'vault-1',
    'status': status,
    'waiting_period_hours': 48,
    'package_aad': _safeEmergencyPackageAad,
    'package_fingerprint': 'package-fingerprint-1',
    'recipient_key_fingerprint': 'fingerprint-1',
    'requested_at': null,
    'ready_at': null,
    'downloaded_at': null,
    'cancelled_at': null,
    'revoked_at': null,
    'expires_at': null,
    'created_at': '2026-05-24T08:00:00Z',
    'updated_at': '2026-05-24T08:00:00Z',
  };
}
