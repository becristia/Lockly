import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';

void main() {
  const packageHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const validToken = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
  const validTransferKey = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA';
  const validPackagePassword = 'AgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICE';

  LanTransferQrPayload validPayload({
    DateTime? expiresAt,
    String host = '192.168.1.20',
    int port = 48721,
    String sessionId = 'session-123',
    String token = validToken,
    String transferKey = validTransferKey,
    String packagePassword = validPackagePassword,
    String senderName = 'Alice Laptop',
    int selectedCount = 3,
    String packageSha256 = packageHash,
  }) {
    return LanTransferQrPayload(
      host: host,
      port: port,
      sessionId: sessionId,
      token: token,
      transferKey: transferKey,
      packagePassword: packagePassword,
      packageSha256: packageSha256,
      selectedCount: selectedCount,
      expiresAt: expiresAt ?? DateTime.utc(2099, 5, 25, 12, 30),
      senderName: senderName,
    );
  }

  group('LanTransferQrPayload', () {
    test('encodes stable schema JSON and decodes a validated roundtrip', () {
      final payload = validPayload();

      final encoded = payload.encode();
      final decoded = LanTransferQrPayload.decode(encoded);

      expect(decoded.host, payload.host);
      expect(decoded.port, payload.port);
      expect(decoded.sessionId, payload.sessionId);
      expect(decoded.token, payload.token);
      expect(decoded.transferKey, payload.transferKey);
      expect(decoded.packagePassword, payload.packagePassword);
      expect(decoded.packageSha256, payload.packageSha256);
      expect(decoded.selectedCount, payload.selectedCount);
      expect(decoded.expiresAt, payload.expiresAt);
      expect(decoded.senderName, payload.senderName);
      expect(
        () => decoded.validate(now: DateTime.utc(2026, 5, 25, 12)),
        returnsNormally,
      );

      final json = jsonDecode(encoded) as Map<String, Object?>;
      expect(json['schema'], lanTransferSchema);
      expect(json['host'], payload.host);
      expect(json['port'], payload.port);
      expect(json['sessionId'], payload.sessionId);
      expect(json['token'], payload.token);
      expect(json['transferKey'], payload.transferKey);
      expect(json['packagePassword'], payload.packagePassword);
      expect(json['packageSha256'], payload.packageSha256);
      expect(json['selectedCount'], payload.selectedCount);
      expect(json['expiresAt'], payload.expiresAt.toUtc().toIso8601String());
      expect(json['senderName'], payload.senderName);
    });

    test('rejects expired QR payloads', () {
      final payload = validPayload(expiresAt: DateTime.utc(2026, 5, 25, 12));

      expect(
        () => payload.validate(now: DateTime.utc(2026, 5, 25, 12, 0, 1)),
        throwsA(isA<LanTransferFormatException>()),
      );
    });

    test('rejects malformed JSON, unsupported schemas, and wrong shapes', () {
      expect(
        () => LanTransferQrPayload.decode('not-json'),
        throwsA(isA<LanTransferFormatException>()),
      );
      expect(
        () => LanTransferQrPayload.decode(jsonEncode(['not', 'an', 'object'])),
        throwsA(isA<LanTransferFormatException>()),
      );
      expect(
        () => LanTransferQrPayload.decode(
          jsonEncode({
            'schema': 'lockly-lan-transfer-v0',
            'host': '192.168.1.20',
          }),
        ),
        throwsA(isA<LanTransferFormatException>()),
      );

      final wrongType =
          jsonDecode(validPayload().encode()) as Map<String, Object?>;
      wrongType['port'] = '48721';
      expect(
        () => LanTransferQrPayload.decode(jsonEncode(wrongType)),
        throwsA(isA<LanTransferFormatException>()),
      );
    });

    test('validates required boundaries and value formats', () {
      final cases = <LanTransferQrPayload>[
        validPayload(host: ''),
        validPayload(host: '0.0.0.0'),
        validPayload(host: '8.8.8.8'),
        validPayload(host: '100.64.0.1'),
        validPayload(host: 'example.com'),
        validPayload(port: 0),
        validPayload(port: 65536),
        validPayload(sessionId: ''),
        validPayload(token: ''),
        validPayload(transferKey: ''),
        validPayload(senderName: ''),
        validPayload(selectedCount: 0),
        validPayload(packageSha256: 'A' * 64),
        validPayload(packageSha256: 'a' * 63),
      ];

      for (final payload in cases) {
        expect(
          () => payload.validate(now: DateTime.utc(2026, 5, 25, 12)),
          throwsA(isA<LanTransferFormatException>()),
        );
      }
    });

    test('rejects QR tokens that are not 32-byte unpadded base64url', () {
      final cases = <String>[
        '$validToken=',
        '${validToken.substring(0, 42)}/',
        '${validToken.substring(0, 42)}+',
        validToken.substring(0, 42),
      ];

      for (final token in cases) {
        expect(
          () => validPayload(
            token: token,
          ).validate(now: DateTime.utc(2026, 5, 25, 12)),
          throwsA(isA<LanTransferFormatException>()),
        );
      }
    });

    test(
      'rejects QR transfer keys with invalid wire format or byte length',
      () {
        final cases = <String>[
          '$validTransferKey=',
          '${validTransferKey.substring(0, 42)}/',
          '${validTransferKey.substring(0, 42)}+',
          base64UrlEncode(List<int>.filled(31, 1)).replaceAll('=', ''),
        ];

        for (final transferKey in cases) {
          expect(
            () => validPayload(
              transferKey: transferKey,
            ).validate(now: DateTime.utc(2026, 5, 25, 12)),
            throwsA(isA<LanTransferFormatException>()),
          );
        }
      },
    );

    test('rejects QR payload JSON with unknown fields', () {
      final unsafeFields = ['unexpected', 'plaintext', 'password', 'notes'];

      for (final field in unsafeFields) {
        final json =
            jsonDecode(validPayload().encode()) as Map<String, Object?>;
        json[field] = 'must not be ignored';

        expect(
          () => LanTransferQrPayload.decode(jsonEncode(json)),
          throwsA(isA<LanTransferFormatException>()),
        );
      }
    });

    test('rejects oversized QR payload JSON before decoding', () {
      final oversized =
          '{"schema":"$lanTransferSchema","padding":"'
          '${'x' * maxLanTransferQrPayloadChars}" }';

      expect(
        () => LanTransferQrPayload.decode(oversized),
        throwsA(isA<LanTransferFormatException>()),
      );
    });

    test('rejects excessive QR string field lengths', () {
      final cases = <LanTransferQrPayload>[
        validPayload(sessionId: 's' * (maxLanTransferSessionIdLength + 1)),
        validPayload(senderName: 'S' * (maxLanTransferSenderNameLength + 1)),
      ];

      for (final payload in cases) {
        expect(
          () => payload.validate(now: DateTime.utc(2026, 5, 25, 12)),
          throwsA(isA<LanTransferFormatException>()),
        );
      }
    });

    test('builds a transfer URI without embedding token or transfer key', () {
      final payload = validPayload();

      final uri = payload.transferUri();

      expect(uri.scheme, 'http');
      expect(uri.host, payload.host);
      expect(uri.port, payload.port);
      expect(uri.path, '/v1/transfer/${payload.sessionId}');
      expect(uri.toString(), isNot(contains(payload.token)));
      expect(uri.toString(), isNot(contains(payload.transferKey)));
      expect(uri.query, isEmpty);
    });
  });

  group('LanTransferEnvelope', () {
    test('roundtrips JSON and validates encoded payload fields', () {
      final envelope = LanTransferEnvelope(
        nonce: Uint8List.fromList(List<int>.generate(12, (index) => index)),
        ciphertext: Uint8List.fromList([1, 2, 3, 4]),
        mac: Uint8List.fromList(List<int>.filled(16, 5)),
        contentLength: 4,
        packageSha256: packageHash,
      );

      final json = envelope.toJson();
      final decoded = LanTransferEnvelope.fromJson(json);

      expect(decoded.nonce, envelope.nonce);
      expect(decoded.ciphertext, envelope.ciphertext);
      expect(decoded.mac, envelope.mac);
      expect(decoded.contentLength, envelope.contentLength);
      expect(decoded.packageSha256, envelope.packageSha256);
      expect(json.keys, containsAll(['nonce', 'ciphertext', 'mac']));
    });

    test('rejects malformed envelope JSON', () {
      expect(
        () => LanTransferEnvelope.fromJson({'nonce': 'not-base64'}),
        throwsA(isA<LanTransferFormatException>()),
      );
      expect(
        () => LanTransferEnvelope.fromJson({
          'nonce': base64Encode(List<int>.filled(12, 1)),
          'ciphertext': base64Encode([1]),
          'mac': base64Encode(List<int>.filled(16, 2)),
          'contentLength': -1,
          'packageSha256': packageHash,
        }),
        throwsA(isA<LanTransferFormatException>()),
      );
    });

    test('rejects invalid AES-GCM envelope field lengths', () {
      expect(
        () => LanTransferEnvelope.fromJson({
          'nonce': base64Encode(List<int>.filled(11, 1)),
          'ciphertext': base64Encode([1, 2, 3]),
          'mac': base64Encode(List<int>.filled(16, 2)),
          'contentLength': 3,
          'packageSha256': packageHash,
        }),
        throwsA(isA<LanTransferFormatException>()),
      );
      expect(
        () => LanTransferEnvelope.fromJson({
          'nonce': base64Encode(List<int>.filled(12, 1)),
          'ciphertext': base64Encode([1, 2, 3]),
          'mac': base64Encode(List<int>.filled(15, 2)),
          'contentLength': 3,
          'packageSha256': packageHash,
        }),
        throwsA(isA<LanTransferFormatException>()),
      );
    });

    test(
      'rejects envelopes when ciphertext length differs from contentLength',
      () {
        expect(
          () => LanTransferEnvelope.fromJson({
            'nonce': base64Encode(List<int>.filled(12, 1)),
            'ciphertext': base64Encode([1, 2, 3]),
            'mac': base64Encode(List<int>.filled(16, 2)),
            'contentLength': 4,
            'packageSha256': packageHash,
          }),
          throwsA(isA<LanTransferFormatException>()),
        );
      },
    );

    test('rejects envelope JSON with unknown fields', () {
      final envelope = LanTransferEnvelope(
        nonce: Uint8List.fromList(List<int>.filled(12, 1)),
        ciphertext: Uint8List.fromList([1, 2, 3, 4]),
        mac: Uint8List.fromList(List<int>.filled(16, 2)),
        contentLength: 4,
        packageSha256: packageHash,
      );
      final unsafeFields = ['unexpected', 'plaintext', 'password', 'notes'];

      for (final field in unsafeFields) {
        final json = Map<String, Object?>.from(envelope.toJson());
        json[field] = 'must not be ignored';

        expect(
          () => LanTransferEnvelope.fromJson(json),
          throwsA(isA<LanTransferFormatException>()),
        );
      }
    });
  });

  test('conflict and import result models expose safe values only', () {
    const conflict = LanTransferConflict(
      title: 'Email',
      website: 'https://example.com',
      username: 'alice',
      reason: LanTransferConflictReason.existingLocalEntry,
    );
    const result = LanTransferImportResult(
      importedCount: 2,
      skippedCount: 1,
      conflicts: [conflict],
    );

    expect(result.importedCount, 2);
    expect(result.skippedCount, 1);
    expect(result.conflicts, [conflict]);
    expect(conflict.toString(), contains('Email'));
    expect(conflict.toString(), contains('existingLocalEntry'));
    expect(conflict.toString(), isNot(contains('password')));
    expect(conflict.toString(), isNot(contains('token')));
  });
}
