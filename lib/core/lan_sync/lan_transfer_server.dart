import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:secure_box/core/lan_sync/lan_transfer_crypto.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';

const _expiredSessionGrace = Duration(seconds: 30);

typedef LanAdvertisedHostResolver = Future<String?> Function(String bindHost);

class LanTransferServer {
  LanTransferServer({
    required LanTransferCrypto crypto,
    LanAdvertisedHostResolver? advertisedHostResolver,
  }) : _crypto = crypto,
       _advertisedHostResolver =
           advertisedHostResolver ?? resolveLanAdvertisedHost;

  final LanTransferCrypto _crypto;
  final LanAdvertisedHostResolver _advertisedHostResolver;

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
    _validateStartInput(
      packageBytes: packageBytes,
      selectedCount: selectedCount,
      senderName: senderName,
      ttl: ttl,
      bindHost: bindHost,
      advertisedHost: advertisedHost,
    );

    final sessionId = _crypto.randomToken();
    final token = _crypto.randomToken();
    final transferKey = _crypto.randomTransferKey();
    final envelope = await _crypto.encryptPackage(
      plaintext: packageBytes,
      key: transferKey,
    );
    final expiresAt = DateTime.now().toUtc().add(ttl);
    final payloadHost = await _resolvePayloadHost(
      bindHost: bindHost,
      advertisedHost: advertisedHost,
    );

    final server = await HttpServer.bind(bindHost, 0);
    _server = server;
    try {
      final payload = LanTransferQrPayload(
        host: payloadHost,
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
      _expiryTimer = Timer(ttl + _expiredSessionGrace, () {
        unawaited(close());
      });
      unawaited(server.forEach((request) => _handleRequest(request)));

      return LanTransferSession(qrPayload: payload, expiresAt: expiresAt);
    } catch (_) {
      _expiryTimer?.cancel();
      _expiryTimer = null;
      _session = null;
      _server = null;
      await server.close(force: true);
      rethrow;
    }
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

    _session = null;
    final responseBytes = utf8.encode(jsonEncode(session.envelope.toJson()));
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.contentLength = responseBytes.length
      ..add(responseBytes);
    await request.response.close();
    await close();
  }

  Future<void> _sendEmpty(HttpRequest request, int statusCode) async {
    request.response.statusCode = statusCode;
    await request.response.close();
  }

  void _validateStartInput({
    required Uint8List packageBytes,
    required int selectedCount,
    required String senderName,
    required Duration ttl,
    required String bindHost,
    required String? advertisedHost,
  }) {
    if (packageBytes.isEmpty) {
      throw const LanTransferFormatException('Package bytes must not be empty');
    }
    if (selectedCount <= 0) {
      throw const LanTransferFormatException('Selected count must be positive');
    }
    if (senderName.trim().isEmpty) {
      throw const LanTransferFormatException('Sender name must not be blank');
    }
    if (ttl <= Duration.zero) {
      throw const LanTransferFormatException('TTL must be positive');
    }
    if (bindHost.trim().isEmpty) {
      throw const LanTransferFormatException('Bind host must not be blank');
    }
    if (advertisedHost != null && advertisedHost.trim().isEmpty) {
      throw const LanTransferFormatException(
        'Advertised host must not be blank',
      );
    }
  }

  Future<String> _resolvePayloadHost({
    required String bindHost,
    required String? advertisedHost,
  }) async {
    final explicitHost = advertisedHost?.trim();
    if (explicitHost != null && explicitHost.isNotEmpty) {
      return explicitHost;
    }

    final resolvedHost = (await _advertisedHostResolver(bindHost))?.trim();
    if (resolvedHost == null || resolvedHost.isEmpty) {
      throw const LanTransferFormatException(
        'No reachable LAN address is available for this device',
      );
    }
    return resolvedHost;
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

Future<String?> resolveLanAdvertisedHost(String bindHost) async {
  final trimmedBindHost = bindHost.trim();
  if (trimmedBindHost.isNotEmpty &&
      !isLanTransferUnspecifiedHost(trimmedBindHost)) {
    if (!_isAdvertisableLanIpv4(trimmedBindHost)) {
      throw const LanTransferFormatException(
        'Bind host must be a reachable LAN IPv4 address',
      );
    }
    return trimmedBindHost;
  }

  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  String? linkLocalCandidate;
  String? fallbackCandidate;
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      final candidate = address.address.trim();
      if (!_isAdvertisableLanIpv4(candidate)) {
        continue;
      }
      if (_isPreferredInterfaceName(interface.name)) {
        return candidate;
      }
      if (_isLinkLocalIpv4(candidate)) {
        linkLocalCandidate ??= candidate;
        continue;
      }
      fallbackCandidate ??= candidate;
    }
  }
  return fallbackCandidate ?? linkLocalCandidate;
}

bool _isAdvertisableLanIpv4(String address) {
  final octets = lanTransferIpv4Octets(address);
  return octets != null &&
      octets[0] != 127 &&
      octets[0] < 224 &&
      isLanTransferAllowedHost(address);
}

bool _isLinkLocalIpv4(String address) {
  final octets = lanTransferIpv4Octets(address);
  return octets != null && octets[0] == 169 && octets[1] == 254;
}

bool _isPreferredInterfaceName(String name) {
  final normalized = name.toLowerCase();
  if (normalized.contains('virtual') ||
      normalized.contains('vmware') ||
      normalized.contains('vbox') ||
      normalized.contains('hyper-v') ||
      normalized.contains('docker') ||
      normalized.contains('wintun') ||
      normalized.contains('wireguard') ||
      normalized.contains('tailscale') ||
      normalized.contains('loopback')) {
    return false;
  }
  return normalized.contains('wi-fi') ||
      normalized.contains('wifi') ||
      normalized.contains('wlan') ||
      normalized.contains('ethernet') ||
      normalized == 'eth0' ||
      normalized == 'en0';
}
