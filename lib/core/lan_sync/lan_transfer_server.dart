import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:secure_box/core/lan_sync/lan_transfer_crypto.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';

class LanTransferServer {
  LanTransferServer({required LanTransferCrypto crypto}) : _crypto = crypto;

  final LanTransferCrypto _crypto;

  HttpServer? _server;
  Timer? _expiryTimer;
  _LanTransferServerSession? _session;
  bool _closing = false;

  Future<LanTransferSession> start({
    required Uint8List packageBytes,
    required int selectedCount,
    required String senderName,
    Duration ttl = const Duration(minutes: 5),
    String bindHost = '0.0.0.0',
    String? advertisedHost,
  }) async {
    await close();
    _closing = false;

    final sessionId = _crypto.randomToken();
    final token = _crypto.randomToken();
    final transferKey = _crypto.randomTransferKey();
    final envelope = await _crypto.encryptPackage(
      plaintext: packageBytes,
      key: transferKey,
    );
    final expiresAt = DateTime.now().toUtc().add(ttl);

    final server = await HttpServer.bind(bindHost, 0);
    _server = server;

    final payload = LanTransferQrPayload(
      host: advertisedHost ?? server.address.address,
      port: server.port,
      sessionId: sessionId,
      token: token,
      transferKey: _crypto.encodeTransferKey(transferKey),
      packageSha256: envelope.packageSha256,
      selectedCount: selectedCount,
      expiresAt: expiresAt,
      senderName: senderName,
    );
    payload.validate(now: DateTime.now().toUtc());

    _session = _LanTransferServerSession(
      payload: payload,
      envelope: envelope,
      expiresAt: expiresAt,
    );
    _expiryTimer = Timer(ttl, () {
      unawaited(close());
    });
    unawaited(server.forEach((request) => _handleRequest(request)));

    return LanTransferSession(qrPayload: payload, expiresAt: expiresAt);
  }

  Future<void> close() async {
    if (_closing) {
      return;
    }
    _closing = true;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _session = null;

    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
    _closing = false;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final session = _session;
    if (session == null ||
        request.method != 'GET' ||
        request.uri.pathSegments.length != 3 ||
        request.uri.pathSegments[0] != 'v1' ||
        request.uri.pathSegments[1] != 'transfer' ||
        request.uri.pathSegments[2] != session.payload.sessionId) {
      await _sendEmpty(request, HttpStatus.notFound);
      return;
    }

    if (!DateTime.now().toUtc().isBefore(session.expiresAt)) {
      await _sendEmpty(request, HttpStatus.gone);
      await close();
      return;
    }

    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    const bearerPrefix = 'Bearer ';
    if (authorization == null ||
        !authorization.startsWith(bearerPrefix) ||
        !_crypto.tokenMatches(
          session.payload.token,
          authorization.substring(bearerPrefix.length),
        )) {
      await _sendEmpty(request, HttpStatus.unauthorized);
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(session.envelope.toJson()));
    await request.response.close();
    _session = null;
    await close();
  }

  Future<void> _sendEmpty(HttpRequest request, int statusCode) async {
    request.response.statusCode = statusCode;
    await request.response.close();
  }
}

class LanTransferSession {
  const LanTransferSession({required this.qrPayload, required this.expiresAt});

  final LanTransferQrPayload qrPayload;
  final DateTime expiresAt;
}

class _LanTransferServerSession {
  const _LanTransferServerSession({
    required this.payload,
    required this.envelope,
    required this.expiresAt,
  });

  final LanTransferQrPayload payload;
  final LanTransferEnvelope envelope;
  final DateTime expiresAt;
}
