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

    test('only one concurrent authorized request receives package', () async {
      final crypto = transferCrypto();
      final server = LanTransferServer(crypto: crypto);
      final largePackage = Uint8List(8 * 1024 * 1024);
      final session = await server.start(
        packageBytes: largePackage,
        selectedCount: 1,
        senderName: 'Sender',
        ttl: const Duration(minutes: 5),
        bindHost: '127.0.0.1',
        advertisedHost: '127.0.0.1',
      );
      addTearDown(() => server.close());

      const requestCount = 8;
      final statusCodes = await Future.wait(
        List.generate(
          requestCount,
          (_) => _withheldAuthorizedGetStatus(session.qrPayload),
        ),
      );

      expect(statusCodes.where((code) => code == HttpStatus.ok), hasLength(1));
      final unavailableCount = statusCodes.where((code) => code == null).length;
      final nonOkCount = statusCodes
          .where((code) => code != null && code != HttpStatus.ok)
          .length;
      expect(nonOkCount + unavailableCount, requestCount - 1);
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

    test('expired session returns gone over raw HTTP', () async {
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

      final statusCode = await _authorizedGetStatus(
        session.qrPayload.transferUri(),
        session.qrPayload.token,
      );

      expect(statusCode, HttpStatus.gone);
    });

    test('package integrity mismatch fails before decrypting', () async {
      final serverCrypto = transferCrypto();
      final clientCrypto = _DecryptSpyLanTransferCrypto();
      final server = LanTransferServer(crypto: serverCrypto);
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
        LanTransferClient(crypto: clientCrypto).download(mismatchPayload),
        throwsA(isA<LanTransferIntegrityException>()),
      );
      expect(clientCrypto.decryptPackageCalls, isZero);
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

    test('huge Content-Length response is rejected before body read', () async {
      final crypto = transferCrypto();
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(() => server.close());
      unawaited(
        server.forEach((socket) async {
          socket.write(
            'HTTP/1.1 200 OK\r\n'
            'Content-Type: application/json\r\n'
            'Content-Length: 65\r\n'
            'Connection: keep-alive\r\n'
            '\r\n',
          );
          await socket.flush();
        }),
      );

      await expectLater(
        LanTransferClient(
          crypto: crypto,
          maxEnvelopeBytes: 64,
        ).download(_validPayloadForServer(crypto, server.port)),
        throwsA(isA<LanTransferMalformedException>()),
      ).timeout(const Duration(seconds: 2));
    });

    test(
      'streaming response exceeding cap is rejected while reading',
      () async {
        final crypto = transferCrypto();
        final server = await HttpServer.bind('127.0.0.1', 0);
        addTearDown(() => server.close(force: true));
        unawaited(
          server.forEach((request) async {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write('x' * 65);
            await request.response.close();
          }),
        );

        await expectLater(
          LanTransferClient(
            crypto: crypto,
            maxEnvelopeBytes: 64,
          ).download(_validPayloadForServer(crypto, server.port)),
          throwsA(isA<LanTransferMalformedException>()),
        );
      },
    );

    test('invalid UTF-8 response throws malformed exception', () async {
      final crypto = transferCrypto();
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..add(<int>[0xff]);
          await request.response.close();
        }),
      );

      await expectLater(
        LanTransferClient(
          crypto: crypto,
        ).download(_validPayloadForServer(crypto, server.port)),
        throwsA(isA<LanTransferMalformedException>()),
      );
    });

    test('server validates start input before preparing listener', () async {
      final crypto = _EncryptSpyLanTransferCrypto();
      final server = LanTransferServer(crypto: crypto);
      addTearDown(() => server.close());

      await expectLater(
        server.start(
          packageBytes: packageBytes('{"items":["one"]}'),
          selectedCount: 0,
          senderName: 'Sender',
          bindHost: '127.0.0.1',
          advertisedHost: '127.0.0.1',
        ),
        throwsA(isA<LanTransferFormatException>()),
      );
      expect(crypto.encryptPackageCalls, isZero);

      final validSession = await server.start(
        packageBytes: packageBytes('{"items":["two"]}'),
        selectedCount: 1,
        senderName: 'Sender',
        bindHost: '127.0.0.1',
        advertisedHost: '127.0.0.1',
      );

      final statusCode = await _authorizedGetStatus(
        validSession.qrPayload.transferUri(),
        validSession.qrPayload.token,
      );
      expect(statusCode, HttpStatus.ok);
    });
  });
}

LanTransferQrPayload _validPayloadForServer(
  LanTransferCrypto crypto,
  int port,
) {
  final key = crypto.randomTransferKey();
  return LanTransferQrPayload(
    host: '127.0.0.1',
    port: port,
    sessionId: 'session-1',
    token: crypto.randomToken(),
    transferKey: crypto.encodeTransferKey(key),
    packageSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    selectedCount: 1,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    senderName: 'Sender',
  );
}

class _DecryptSpyLanTransferCrypto extends LanTransferCrypto {
  _DecryptSpyLanTransferCrypto()
    : super(
        crypto: CryptoService(random: SecureRandom()),
        random: SecureRandom(),
      );

  int decryptPackageCalls = 0;

  @override
  Future<Uint8List> decryptPackage({
    required LanTransferEnvelope envelope,
    required Uint8List key,
  }) {
    decryptPackageCalls++;
    return super.decryptPackage(envelope: envelope, key: key);
  }
}

class _EncryptSpyLanTransferCrypto extends LanTransferCrypto {
  _EncryptSpyLanTransferCrypto()
    : super(
        crypto: CryptoService(random: SecureRandom()),
        random: SecureRandom(),
      );

  int encryptPackageCalls = 0;

  @override
  Future<LanTransferEnvelope> encryptPackage({
    required Uint8List plaintext,
    required Uint8List key,
  }) {
    encryptPackageCalls++;
    return super.encryptPackage(plaintext: plaintext, key: key);
  }
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

Future<int> _authorizedGetStatus(Uri uri, String token) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<int?> _withheldAuthorizedGetStatus(LanTransferQrPayload payload) async {
  Socket? socket;
  try {
    socket = await Socket.connect(payload.host, payload.port);
    final requestPath = payload.transferUri().path;
    socket
      ..write('GET $requestPath HTTP/1.1\r\n')
      ..write('Host: ${payload.host}:${payload.port}\r\n')
      ..write('Authorization: Bearer ${payload.token}\r\n')
      ..write('Connection: close\r\n')
      ..write('\r\n');
    await socket.flush();

    await Future<void>.delayed(const Duration(milliseconds: 100));

    final responseBytes = <int>[];
    await for (final chunk in socket.timeout(
      const Duration(seconds: 5),
      onTimeout: (sink) => sink.close(),
    )) {
      responseBytes.addAll(chunk);
    }

    final responseText = latin1.decode(responseBytes, allowInvalid: true);
    final match = RegExp(r'HTTP/1\.[01] (\d{3}) ').firstMatch(responseText);
    return match == null ? null : int.parse(match.group(1)!);
  } on HttpException {
    return null;
  } on SocketException {
    return null;
  } finally {
    socket?.destroy();
  }
}
