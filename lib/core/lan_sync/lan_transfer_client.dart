import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:secure_box/core/cancellation/cancellation_token.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_crypto.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';

/// Maximum LAN transfer HTTP envelope size accepted from a peer.
///
/// This caps the JSON response body and the declared encrypted package size so
/// a malformed LAN peer cannot force unbounded client memory growth.
const maxLanTransferEnvelopeBytes = 128 * 1024 * 1024;
const defaultLanTransferRequestTimeout = Duration(seconds: 8);
const defaultLanTransferOverallTimeout = Duration(minutes: 2);

class LanTransferException implements Exception {
  const LanTransferException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'LanTransferException: $message';
}

class LanTransferUnavailableException extends LanTransferException {
  const LanTransferUnavailableException(super.message, [super.cause]);
}

class LanTransferExpiredException extends LanTransferException {
  const LanTransferExpiredException(super.message, [super.cause]);
}

class LanTransferUnauthorizedException extends LanTransferException {
  const LanTransferUnauthorizedException(super.message, [super.cause]);
}

class LanTransferMalformedException extends LanTransferException {
  const LanTransferMalformedException(super.message, [super.cause]);
}

class LanTransferIntegrityException extends LanTransferException {
  const LanTransferIntegrityException(super.message, [super.cause]);
}

class LanTransferClient {
  const LanTransferClient({
    required LanTransferCrypto crypto,
    int maxEnvelopeBytes = maxLanTransferEnvelopeBytes,
    Duration requestTimeout = defaultLanTransferRequestTimeout,
    Duration overallTimeout = defaultLanTransferOverallTimeout,
  }) : assert(maxEnvelopeBytes > 0),
       assert(requestTimeout > Duration.zero),
       assert(overallTimeout > Duration.zero),
       _crypto = crypto,
       _maxEnvelopeBytes = maxEnvelopeBytes,
       _requestTimeout = requestTimeout,
       _overallTimeout = overallTimeout;

  final LanTransferCrypto _crypto;
  final int _maxEnvelopeBytes;
  final Duration _requestTimeout;
  final Duration _overallTimeout;

  Future<Uint8List> download(
    LanTransferQrPayload payload, {
    CancellationToken? cancellationToken,
  }) async {
    _validatePayload(payload);
    cancellationToken?.throwIfCancelled();
    return _download(payload, cancellationToken: cancellationToken);
  }

  Future<Uint8List> _download(
    LanTransferQrPayload payload, {
    CancellationToken? cancellationToken,
  }) async {
    Socket? socket;
    var didOverallTimeout = false;
    void abortSocket() {
      socket?.destroy();
    }

    final overallTimer = Timer(_overallTimeout, () {
      didOverallTimeout = true;
      abortSocket();
    });
    cancellationToken?.addListener(abortSocket);
    try {
      socket = await Socket.connect(
        payload.host,
        payload.port,
        timeout: _requestTimeout,
      );
      cancellationToken?.throwIfCancelled();
      _writeHttpRequest(socket, payload);
      await socket.flush().timeout(_requestTimeout);
      cancellationToken?.throwIfCancelled();
      final response = await _readHttpResponse(
        socket,
        cancellationToken: cancellationToken,
        didOverallTimeout: () => didOverallTimeout,
      );

      switch (response.statusCode) {
        case HttpStatus.ok:
          return await _readEnvelope(response.body, payload);
        case HttpStatus.gone:
          throw const LanTransferExpiredException(
            'LAN transfer session has expired',
          );
        case HttpStatus.unauthorized:
          throw const LanTransferUnauthorizedException(
            'LAN transfer authorization failed',
          );
        case HttpStatus.notFound:
          throw const LanTransferUnavailableException(
            'LAN transfer session is unavailable',
          );
        default:
          throw LanTransferUnavailableException(
            'LAN transfer failed with HTTP ${response.statusCode}',
          );
      }
    } on LanTransferException {
      rethrow;
    } on OperationCancelledException {
      rethrow;
    } on SocketException catch (error) {
      if (cancellationToken?.isCancelled == true) {
        throw const OperationCancelledException();
      }
      if (didOverallTimeout) {
        throw LanTransferUnavailableException(
          'LAN transfer request timed out',
          error,
        );
      }
      throw LanTransferUnavailableException(
        'LAN transfer server is unavailable',
        error,
      );
    } on HttpException catch (error) {
      throw LanTransferUnavailableException(
        'LAN transfer request failed',
        error,
      );
    } on TimeoutException catch (error) {
      throw LanTransferUnavailableException(
        'LAN transfer request timed out',
        error,
      );
    } finally {
      overallTimer.cancel();
      cancellationToken?.removeListener(abortSocket);
      socket?.destroy();
    }
  }

  void _writeHttpRequest(Socket socket, LanTransferQrPayload payload) {
    final requestPath = payload.transferUri().path;
    socket
      ..write('GET $requestPath HTTP/1.1\r\n')
      ..write('Host: ${payload.host}:${payload.port}\r\n')
      ..write('Authorization: Bearer ${payload.token}\r\n')
      ..write('Accept: application/json\r\n')
      ..write('Connection: close\r\n')
      ..write('\r\n');
  }

  Future<Uint8List> _readEnvelope(
    String body,
    LanTransferQrPayload payload,
  ) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw LanTransferMalformedException(
        'LAN transfer response was not valid JSON',
        error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const LanTransferMalformedException(
        'LAN transfer response must be a JSON object',
      );
    }

    final LanTransferEnvelope envelope;
    try {
      envelope = LanTransferEnvelope.fromJson(decoded);
    } on LanTransferFormatException catch (error) {
      throw LanTransferMalformedException(
        'LAN transfer response envelope was malformed',
        error,
      );
    }
    if (envelope.contentLength > _maxEnvelopeBytes ||
        envelope.ciphertext.length > _maxEnvelopeBytes) {
      throw const LanTransferMalformedException(
        'LAN transfer response envelope exceeded size limit',
      );
    }

    if (envelope.packageSha256 != payload.packageSha256) {
      throw const LanTransferIntegrityException(
        'LAN transfer envelope SHA-256 did not match QR payload',
      );
    }

    final plaintext = await _decryptEnvelope(envelope, payload.transferKey);
    if (_crypto.sha256Hex(plaintext) != payload.packageSha256) {
      throw const LanTransferIntegrityException(
        'LAN transfer package SHA-256 did not match QR payload',
      );
    }
    return plaintext;
  }

  Future<_LanHttpResponse> _readHttpResponse(
    Socket socket, {
    CancellationToken? cancellationToken,
    required bool Function() didOverallTimeout,
  }) async {
    const maxHeaderBytes = 64 * 1024;
    final headerBuffer = <int>[];
    final bodyBuilder = BytesBuilder(copy: false);
    var headerEnd = -1;
    int? contentLength;
    int? statusCode;
    var bodyLength = 0;

    await for (final chunk in socket.timeout(_requestTimeout)) {
      cancellationToken?.throwIfCancelled();
      if (didOverallTimeout()) {
        throw TimeoutException('LAN transfer request timed out');
      }
      if (headerEnd < 0) {
        headerBuffer.addAll(chunk);
        headerEnd = _findHeaderEnd(headerBuffer);
        if (headerEnd < 0 && headerBuffer.length > maxHeaderBytes) {
          throw const LanTransferMalformedException(
            'LAN transfer response headers exceeded size limit',
          );
        }
        if (headerEnd >= 0) {
          final headers = latin1.decode(headerBuffer.sublist(0, headerEnd));
          contentLength = _parseContentLength(headers);
          if (contentLength != null && contentLength > _maxEnvelopeBytes) {
            throw const LanTransferMalformedException(
              'LAN transfer response exceeded size limit',
            );
          }
          statusCode = _parseStatusCode(headers);
          final bodyStart = headerEnd + 4;
          if (headerBuffer.length > bodyStart) {
            bodyLength = _appendBodyChunk(
              bodyBuilder: bodyBuilder,
              chunk: headerBuffer.sublist(bodyStart),
              currentLength: bodyLength,
              contentLength: contentLength,
            );
          }
          headerBuffer.clear();
        }
      } else {
        bodyLength = _appendBodyChunk(
          bodyBuilder: bodyBuilder,
          chunk: chunk,
          currentLength: bodyLength,
          contentLength: contentLength,
        );
      }

      if (headerEnd >= 0) {
        if (bodyLength > _maxEnvelopeBytes) {
          throw const LanTransferMalformedException(
            'LAN transfer response exceeded size limit',
          );
        }
        if (contentLength != null && bodyLength >= contentLength) {
          return _LanHttpResponse(
            statusCode: statusCode!,
            body: _decodeUtf8Body(bodyBuilder.takeBytes()),
          );
        }
      }
    }

    cancellationToken?.throwIfCancelled();
    if (didOverallTimeout()) {
      throw TimeoutException('LAN transfer request timed out');
    }
    if (headerEnd < 0) {
      throw const LanTransferMalformedException(
        'LAN transfer response headers were incomplete',
      );
    }
    return _LanHttpResponse(
      statusCode: statusCode!,
      body: _decodeUtf8Body(bodyBuilder.takeBytes()),
    );
  }

  int _findHeaderEnd(List<int> bytes) {
    for (var i = 3; i < bytes.length; i++) {
      if (bytes[i - 3] == 13 &&
          bytes[i - 2] == 10 &&
          bytes[i - 1] == 13 &&
          bytes[i] == 10) {
        return i - 3;
      }
    }
    return -1;
  }

  int? _parseContentLength(String headers) {
    for (final line in headers.split('\r\n').skip(1)) {
      final separator = line.indexOf(':');
      if (separator < 0) {
        continue;
      }
      final name = line.substring(0, separator).trim().toLowerCase();
      if (name != 'content-length') {
        continue;
      }
      final length = int.tryParse(line.substring(separator + 1).trim());
      if (length == null || length < 0) {
        throw const LanTransferMalformedException(
          'LAN transfer response Content-Length was malformed',
        );
      }
      return length;
    }
    return null;
  }

  int _parseStatusCode(String headers) {
    final statusLine = headers.split('\r\n').first;
    final statusMatch = RegExp(
      r'^HTTP/1\.[01] (\d{3})(?: |$)',
    ).firstMatch(statusLine);
    if (statusMatch == null) {
      throw const LanTransferMalformedException(
        'LAN transfer response status was malformed',
      );
    }
    return int.parse(statusMatch.group(1)!);
  }

  int _appendBodyChunk({
    required BytesBuilder bodyBuilder,
    required List<int> chunk,
    required int currentLength,
    required int? contentLength,
  }) {
    final remaining = contentLength == null
        ? chunk.length
        : contentLength - currentLength;
    if (remaining <= 0) {
      return currentLength;
    }
    final bytesToAdd = remaining < chunk.length ? remaining : chunk.length;
    if (currentLength + bytesToAdd > _maxEnvelopeBytes) {
      throw const LanTransferMalformedException(
        'LAN transfer response exceeded size limit',
      );
    }
    bodyBuilder.add(
      bytesToAdd == chunk.length
          ? chunk
          : chunk.take(bytesToAdd).toList(growable: false),
    );
    return currentLength + bytesToAdd;
  }

  String _decodeUtf8Body(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException catch (error) {
      throw LanTransferMalformedException(
        'LAN transfer response was not valid UTF-8',
        error,
      );
    }
  }

  Future<Uint8List> _decryptEnvelope(
    LanTransferEnvelope envelope,
    String encodedTransferKey,
  ) async {
    final Uint8List transferKey;
    try {
      transferKey = _crypto.decodeTransferKey(encodedTransferKey);
    } on Object catch (error) {
      throw LanTransferMalformedException(
        'LAN transfer key was malformed',
        error,
      );
    }

    try {
      return await _crypto.decryptPackage(envelope: envelope, key: transferKey);
    } on CryptoException catch (error) {
      throw LanTransferIntegrityException(
        'LAN transfer package could not be decrypted',
        error,
      );
    }
  }

  void _validatePayload(LanTransferQrPayload payload) {
    try {
      payload.validate();
    } on LanTransferFormatException catch (error) {
      if (!payload.expiresAt.toUtc().isAfter(DateTime.now().toUtc())) {
        throw LanTransferExpiredException(
          'LAN transfer QR payload has expired',
          error,
        );
      }
      throw LanTransferMalformedException(
        'LAN transfer QR payload was malformed',
        error,
      );
    }
  }
}

class _LanHttpResponse {
  const _LanHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
