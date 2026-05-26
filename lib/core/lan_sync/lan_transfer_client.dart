import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_crypto.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';

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
  const LanTransferClient({required LanTransferCrypto crypto})
    : _crypto = crypto;

  final LanTransferCrypto _crypto;

  Future<Uint8List> download(LanTransferQrPayload payload) async {
    _validatePayload(payload);

    final client = HttpClient();
    try {
      final request = await client.getUrl(payload.transferUri());
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${payload.token}',
      );
      final response = await request.close();

      switch (response.statusCode) {
        case HttpStatus.ok:
          return await _readEnvelope(response, payload);
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
    } on SocketException catch (error) {
      throw LanTransferUnavailableException(
        'LAN transfer server is unavailable',
        error,
      );
    } on HttpException catch (error) {
      throw LanTransferUnavailableException(
        'LAN transfer request failed',
        error,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _readEnvelope(
    HttpClientResponse response,
    LanTransferQrPayload payload,
  ) async {
    final body = await utf8.decodeStream(response);
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
