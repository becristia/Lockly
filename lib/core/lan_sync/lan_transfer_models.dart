import 'dart:convert';
import 'dart:typed_data';

import 'package:secure_box/core/crypto/encoding.dart';

const lanTransferSchema = 'lockly-lan-transfer-v1';

class LanTransferFormatException extends FormatException {
  const LanTransferFormatException(super.message, [super.source, super.offset]);
}

enum LanTransferConflictReason { existingLocalEntry, duplicateIncomingEntry }

class LanTransferQrPayload {
  const LanTransferQrPayload({
    required this.host,
    required this.port,
    required this.sessionId,
    required this.token,
    required this.transferKey,
    required this.packageSha256,
    required this.selectedCount,
    required this.expiresAt,
    required this.senderName,
  });

  final String host;
  final int port;
  final String sessionId;
  final String token;
  final String transferKey;
  final String packageSha256;
  final int selectedCount;
  final DateTime expiresAt;
  final String senderName;

  String encode() {
    validate();
    return jsonEncode({
      'schema': lanTransferSchema,
      'host': host,
      'port': port,
      'sessionId': sessionId,
      'token': token,
      'transferKey': transferKey,
      'packageSha256': packageSha256,
      'selectedCount': selectedCount,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'senderName': senderName,
    });
  }

  static LanTransferQrPayload decode(String value) {
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException catch (error) {
      throw LanTransferFormatException(
        'Invalid QR payload JSON',
        value,
        error.offset,
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw const LanTransferFormatException(
        'QR payload must be a JSON object',
      );
    }
    if (decoded['schema'] != lanTransferSchema) {
      throw const LanTransferFormatException('Unsupported LAN transfer schema');
    }

    final payload = LanTransferQrPayload(
      host: _requiredString(decoded, 'host'),
      port: _requiredInt(decoded, 'port'),
      sessionId: _requiredString(decoded, 'sessionId'),
      token: _requiredString(decoded, 'token'),
      transferKey: _requiredString(decoded, 'transferKey'),
      packageSha256: _requiredString(decoded, 'packageSha256'),
      selectedCount: _requiredInt(decoded, 'selectedCount'),
      expiresAt: _requiredDateTime(decoded, 'expiresAt'),
      senderName: _requiredString(decoded, 'senderName'),
    );
    payload.validate();
    return payload;
  }

  void validate({DateTime? now}) {
    if (host.trim().isEmpty) {
      throw const LanTransferFormatException('Host must not be blank');
    }
    if (port < 1 || port > 65535) {
      throw const LanTransferFormatException(
        'Port must be between 1 and 65535',
      );
    }
    if (sessionId.trim().isEmpty) {
      throw const LanTransferFormatException('Session id must not be blank');
    }
    if (token.trim().isEmpty) {
      throw const LanTransferFormatException('Token must not be blank');
    }
    if (transferKey.trim().isEmpty) {
      throw const LanTransferFormatException('Transfer key must not be blank');
    }
    if (!_sha256HexPattern.hasMatch(packageSha256)) {
      throw const LanTransferFormatException(
        'Package SHA-256 must be 64 lowercase hex characters',
      );
    }
    if (selectedCount <= 0) {
      throw const LanTransferFormatException('Selected count must be positive');
    }
    if (!expiresAt.toUtc().isAfter((now ?? DateTime.now().toUtc()).toUtc())) {
      throw const LanTransferFormatException('QR payload has expired');
    }
    if (senderName.trim().isEmpty) {
      throw const LanTransferFormatException('Sender name must not be blank');
    }
  }

  Uri transferUri() {
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      pathSegments: ['lan-transfer', sessionId],
    );
  }
}

class LanTransferEnvelope {
  const LanTransferEnvelope({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.contentLength,
    required this.packageSha256,
  });

  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;
  final int contentLength;
  final String packageSha256;

  Map<String, Object?> toJson() {
    _validateEnvelopeValues(
      nonce: nonce,
      ciphertext: ciphertext,
      mac: mac,
      contentLength: contentLength,
      packageSha256: packageSha256,
    );
    return {
      'nonce': b64(nonce),
      'ciphertext': b64(ciphertext),
      'mac': b64(mac),
      'contentLength': contentLength,
      'packageSha256': packageSha256,
    };
  }

  static LanTransferEnvelope fromJson(Map<String, Object?> json) {
    final envelope = LanTransferEnvelope(
      nonce: _requiredBase64(json, 'nonce'),
      ciphertext: _requiredBase64(json, 'ciphertext'),
      mac: _requiredBase64(json, 'mac'),
      contentLength: _requiredInt(json, 'contentLength'),
      packageSha256: _requiredString(json, 'packageSha256'),
    );
    _validateEnvelopeValues(
      nonce: envelope.nonce,
      ciphertext: envelope.ciphertext,
      mac: envelope.mac,
      contentLength: envelope.contentLength,
      packageSha256: envelope.packageSha256,
    );
    return envelope;
  }
}

class LanTransferConflict {
  const LanTransferConflict({
    required this.title,
    required this.website,
    required this.username,
    required this.reason,
  });

  final String title;
  final String website;
  final String username;
  final LanTransferConflictReason reason;

  @override
  String toString() {
    return 'LanTransferConflict(title: $title, website: $website, '
        'username: $username, reason: ${reason.name})';
  }
}

class LanTransferImportResult {
  const LanTransferImportResult({
    required this.importedCount,
    required this.skippedCount,
    required this.conflicts,
  });

  final int importedCount;
  final int skippedCount;
  final List<LanTransferConflict> conflicts;
}

final _sha256HexPattern = RegExp(r'^[0-9a-f]{64}$');

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw LanTransferFormatException('$key must be a string');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw LanTransferFormatException('$key must be an integer');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw LanTransferFormatException('$key must be an ISO-8601 timestamp');
  }
  return parsed.toUtc();
}

Uint8List _requiredBase64(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  try {
    return fromB64(value);
  } on FormatException {
    throw LanTransferFormatException('$key must be base64 encoded');
  }
}

void _validateEnvelopeValues({
  required Uint8List nonce,
  required Uint8List ciphertext,
  required Uint8List mac,
  required int contentLength,
  required String packageSha256,
}) {
  if (nonce.isEmpty) {
    throw const LanTransferFormatException('Nonce must not be empty');
  }
  if (ciphertext.isEmpty && contentLength > 0) {
    throw const LanTransferFormatException('Ciphertext must not be empty');
  }
  if (mac.isEmpty) {
    throw const LanTransferFormatException('MAC must not be empty');
  }
  if (contentLength < 0) {
    throw const LanTransferFormatException(
      'Content length must not be negative',
    );
  }
  if (!_sha256HexPattern.hasMatch(packageSha256)) {
    throw const LanTransferFormatException(
      'Package SHA-256 must be 64 lowercase hex characters',
    );
  }
}
