import 'dart:convert';
import 'dart:typed_data';

import 'package:secure_box/core/crypto/encoding.dart';

const lanTransferSchema = 'lockly-lan-transfer-v1';
const lanTransferSecretByteLength = 32;
const lanTransferSecretEncodedLength = 43;
const maxLanTransferQrPayloadChars = 4096;
const maxLanTransferHostLength = 64;
const maxLanTransferSessionIdLength = 128;
const maxLanTransferSenderNameLength = 64;

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
    required this.packagePassword,
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
  final String packagePassword;
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
      'packagePassword': packagePassword,
      'packageSha256': packageSha256,
      'selectedCount': selectedCount,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'senderName': senderName,
    });
  }

  static LanTransferQrPayload decode(String value) {
    if (value.length > maxLanTransferQrPayloadChars) {
      throw const LanTransferFormatException('QR payload is too large');
    }

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
    _rejectUnknownKeys(decoded, _qrPayloadKeys, 'QR payload');

    final payload = LanTransferQrPayload(
      host: _requiredString(decoded, 'host'),
      port: _requiredInt(decoded, 'port'),
      sessionId: _requiredString(decoded, 'sessionId'),
      token: _requiredString(decoded, 'token'),
      transferKey: _requiredString(decoded, 'transferKey'),
      packagePassword: _requiredString(decoded, 'packagePassword'),
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
    _validateStringLength(host, 'Host', maxLanTransferHostLength);
    if (!isLanTransferAllowedHost(host)) {
      throw const LanTransferFormatException(
        'Host must be a local or private network address',
      );
    }
    if (port < 1 || port > 65535) {
      throw const LanTransferFormatException(
        'Port must be between 1 and 65535',
      );
    }
    if (sessionId.trim().isEmpty) {
      throw const LanTransferFormatException('Session id must not be blank');
    }
    _validateStringLength(
      sessionId,
      'Session id',
      maxLanTransferSessionIdLength,
    );
    if (token.trim().isEmpty) {
      throw const LanTransferFormatException('Token must not be blank');
    }
    decodeLanTransferBase64UrlNoPadding(
      token,
      fieldName: 'Token',
      expectedEncodedLength: lanTransferSecretEncodedLength,
      expectedByteLength: lanTransferSecretByteLength,
    );
    if (transferKey.trim().isEmpty) {
      throw const LanTransferFormatException('Transfer key must not be blank');
    }
    decodeLanTransferBase64UrlNoPadding(
      transferKey,
      fieldName: 'Transfer key',
      expectedEncodedLength: lanTransferSecretEncodedLength,
      expectedByteLength: lanTransferSecretByteLength,
    );
    if (packagePassword.trim().isEmpty) {
      throw const LanTransferFormatException(
        'Package password must not be blank',
      );
    }
    decodeLanTransferBase64UrlNoPadding(
      packagePassword,
      fieldName: 'Package password',
      expectedEncodedLength: lanTransferSecretEncodedLength,
      expectedByteLength: lanTransferSecretByteLength,
    );
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
    _validateStringLength(
      senderName,
      'Sender name',
      maxLanTransferSenderNameLength,
    );
  }

  Uri transferUri() {
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      pathSegments: ['v1', 'transfer', sessionId],
    );
  }
}

void _validateStringLength(String value, String fieldName, int maxLength) {
  if (value.trim().length > maxLength) {
    throw LanTransferFormatException(
      '$fieldName must be at most $maxLength characters',
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
    _rejectUnknownKeys(json, _envelopeKeys, 'Envelope');
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
final _base64UrlNoPaddingPattern = RegExp(r'^[A-Za-z0-9_-]+$');

bool isLanTransferAllowedHost(String host) {
  final octets = lanTransferIpv4Octets(host);
  if (octets == null) {
    return false;
  }
  return _isLoopbackIpv4(octets) ||
      _isPrivateIpv4(octets) ||
      _isLinkLocalIpv4(octets);
}

bool isLanTransferUnspecifiedHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == '0.0.0.0' || normalized == '::' || normalized == '[::]';
}

List<int>? lanTransferIpv4Octets(String address) {
  final parts = address.trim().split('.');
  if (parts.length != 4) {
    return null;
  }
  final octets = <int>[];
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) {
      return null;
    }
    octets.add(octet);
  }
  return octets;
}

bool _isLoopbackIpv4(List<int> octets) => octets[0] == 127;

bool _isPrivateIpv4(List<int> octets) {
  return octets[0] == 10 ||
      (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
      (octets[0] == 192 && octets[1] == 168);
}

bool _isLinkLocalIpv4(List<int> octets) {
  return octets[0] == 169 && octets[1] == 254;
}

const _qrPayloadKeys = <String>{
  'schema',
  'host',
  'port',
  'sessionId',
  'token',
  'transferKey',
  'packagePassword',
  'packageSha256',
  'selectedCount',
  'expiresAt',
  'senderName',
};

const _envelopeKeys = <String>{
  'nonce',
  'ciphertext',
  'mac',
  'contentLength',
  'packageSha256',
};

String encodeLanTransferBase64UrlNoPadding(Uint8List bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Uint8List decodeLanTransferBase64UrlNoPadding(
  String value, {
  required String fieldName,
  int? expectedEncodedLength,
  int? expectedByteLength,
}) {
  if (expectedEncodedLength != null && value.length != expectedEncodedLength) {
    throw LanTransferFormatException(
      '$fieldName must be unpadded base64url encoded'
      '${expectedByteLength == null ? '' : ' $expectedByteLength bytes'}',
    );
  }
  if (value.isEmpty || !_base64UrlNoPaddingPattern.hasMatch(value)) {
    throw LanTransferFormatException(
      '$fieldName must be unpadded base64url encoded',
    );
  }

  final padding = (4 - value.length % 4) % 4;
  final Uint8List decoded;
  try {
    decoded = Uint8List.fromList(base64Url.decode(value + ('=' * padding)));
  } on FormatException {
    throw LanTransferFormatException(
      '$fieldName must be unpadded base64url encoded',
    );
  }
  if (expectedByteLength != null && decoded.length != expectedByteLength) {
    throw LanTransferFormatException(
      '$fieldName must decode to $expectedByteLength bytes',
    );
  }
  return decoded;
}

void _rejectUnknownKeys(
  Map<String, Object?> json,
  Set<String> allowedKeys,
  String objectName,
) {
  for (final key in json.keys) {
    if (!allowedKeys.contains(key)) {
      throw LanTransferFormatException('$objectName contains unknown field');
    }
  }
}

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
  if (nonce.length != 12) {
    throw const LanTransferFormatException('Nonce must be 12 bytes');
  }
  if (mac.length != 16) {
    throw const LanTransferFormatException('MAC must be 16 bytes');
  }
  if (contentLength < 0) {
    throw const LanTransferFormatException(
      'Content length must not be negative',
    );
  }
  if (ciphertext.length != contentLength) {
    throw const LanTransferFormatException(
      'Ciphertext length must match content length',
    );
  }
  if (!_sha256HexPattern.hasMatch(packageSha256)) {
    throw const LanTransferFormatException(
      'Package SHA-256 must be 64 lowercase hex characters',
    );
  }
}
