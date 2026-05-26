import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_client.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_crypto.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_server.dart';

void main() {
  LanTransferCrypto transferCrypto() {
    final random = SecureRandom();
    return LanTransferCrypto(
      crypto: CryptoService(random: random),
      random: random,
    );
  }

  Uint8List packageBytes(String value) =>
      Uint8List.fromList(utf8.encode(value));

  group('LAN transfer transport', () {
    test('server serves one authenticated encrypted package', () async {
      final crypto = transferCrypto();
      final server = LanTransferServer(crypto: crypto);
      final plaintext = packageBytes('{"version":2,"items":[]}');

      final session = await server.start(
        packageBytes: plaintext,
        selectedCount: 1,
        senderName: 'Sender',
        ttl: const Duration(minutes: 5),
        bindHost: '127.0.0.1',
        advertisedHost: '127.0.0.1',
      );
      addTearDown(() => server.close());

      expect(session.qrPayload.host, '127.0.0.1');
      expect(session.qrPayload.port, greaterThan(0));
      expect(session.qrPayload.transferUri().path, startsWith('/v1/transfer/'));
      expect(
        session.qrPayload.transferUri().toString(),
        isNot(contains(session.qrPayload.token)),
      );
      expect(
        session.qrPayload.transferUri().toString(),
        isNot(contains(session.qrPayload.transferKey)),
      );

      final client = LanTransferClient(crypto: crypto);
      final downloaded = await client.download(session.qrPayload);
      expect(downloaded, plaintext);

      await expectLater(
        client.download(session.qrPayload),
        throwsA(isA<LanTransferUnavailableException>()),
      );
    });

    test('wrong token fails with unauthorized exception', () async {
      final crypto = transferCrypto();
      final server = LanTransferServer(crypto: crypto);
      final session = await server.start(
        packageBytes: packageBytes('{"items":["secret"]}'),
        selectedCount: 1,
        senderName: 'Sender',
        bindHost: '127.0.0.1',
        advertisedHost: '127.0.0.1',
      );
      addTearDown(() => server.close());

      final wrongTokenPayload = LanTransferQrPayload(
        host: session.qrPayload.host,
        port: session.qrPayload.port,
        sessionId: session.qrPayload.sessionId,
        token: crypto.randomToken(),
        transferKey: session.qrPayload.transferKey,
        packageSha256: session.qrPayload.packageSha256,
        selectedCount: session.qrPayload.selectedCount,
        expiresAt: session.qrPayload.expiresAt,
        senderName: session.qrPayload.senderName,
      );

      await expectLater(
        LanTransferClient(crypto: crypto).download(wrongTokenPayload),
        throwsA(isA<LanTransferUnauthorizedException>()),
      );
    });

    test('expired session fails with expired exception', () async {
      final crypto = transferCrypto();
      final server = LanTransferServer(crypto: crypto);
      final session = await server.start(
        packageBytes: packageBytes('{"items":[]}'),
        selectedCount: 1,
        senderName: 'Sender',
        ttl: const Duration(milliseconds: 25),
        bindHost: '127.0.0.1',
        advertisedHost: '127.0.0.1',
      );
      addTearDown(() => server.close());

      await _waitUntil(() => DateTime.now().toUtc().isAfter(session.expiresAt));

      await expectLater(
        LanTransferClient(crypto: crypto).download(session.qrPayload),
        throwsA(isA<LanTransferExpiredException>()),
      );
    });

    test('package integrity mismatch fails before decrypting', () async {
      final crypto = transferCrypto();
      final server = LanTransferServer(crypto: crypto);
      final session = await server.start(
        packageBytes: packageBytes('{"items":["one"]}'),
        selectedCount: 1,
        senderName: 'Sender',
        bindHost: '127.0.0.1',
        advertisedHost: '127.0.0.1',
      );
      addTearDown(() => server.close());

      final mismatchPayload = LanTransferQrPayload(
        host: session.qrPayload.host,
        port: session.qrPayload.port,
        sessionId: session.qrPayload.sessionId,
        token: session.qrPayload.token,
        transferKey: session.qrPayload.transferKey,
        packageSha256:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        selectedCount: session.qrPayload.selectedCount,
        expiresAt: session.qrPayload.expiresAt,
        senderName: session.qrPayload.senderName,
      );

      await expectLater(
        LanTransferClient(crypto: crypto).download(mismatchPayload),
        throwsA(isA<LanTransferIntegrityException>()),
      );
    });

    test('client rejects malformed envelope responses', () async {
      final crypto = transferCrypto();
      final key = crypto.randomTransferKey();
      final token = crypto.randomToken();
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write('not-json');
          await request.response.close();
        }),
      );

      final payload = LanTransferQrPayload(
        host: '127.0.0.1',
        port: server.port,
        sessionId: 'session-1',
        token: token,
        transferKey: crypto.encodeTransferKey(key),
        packageSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        selectedCount: 1,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        senderName: 'Sender',
      );

      await expectLater(
        LanTransferClient(crypto: crypto).download(payload),
        throwsA(isA<LanTransferMalformedException>()),
      );
    });
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
