import 'dart:convert';

const Set<String> forbiddenSyncFieldNames = {
  'master_password',
  'master',
  'masterPassword',
  'master_key',
  'masterKey',
  'password_plaintext',
  'plaintext_password',
  'plaintext',
  'password',
  'username',
  'key',
  'secret',
  'note',
  'notes',
  'totp',
  'totpSecret',
  'totp_secret',
  'passkey',
  'passkey_private_key',
  'attachment',
  'attachment_plaintext',
  'filename',
  'file_name',
  'file_bytes',
  'file_path',
  'mime',
  'mime_type',
  'media_type',
  'raw_key',
  'password_history',
  'oldPassword',
  'newPassword',
  'kek',
  'dek',
  'raw_dek',
  'rawDek',
  'decrypted',
  'private_key',
};
final Set<String> _normalizedForbiddenSyncFieldNames = forbiddenSyncFieldNames
    .map(_normalizeSyncFieldName)
    .toSet();
const Set<String> _forbiddenSyncFieldTokens = {
  'master',
  'password',
  'plaintext',
  'username',
  'key',
  'secret',
  'note',
  'notes',
  'totp',
  'passkey',
  'attachment',
  'kek',
  'dek',
  'decrypted',
};
final Set<String> _safeProtocolSyncFieldNames = {
  _normalizeSyncFieldName('encrypted_dek_by_master'),
};
const Set<String> _forbiddenSyncFieldFragments = {
  'apikey',
  'attachmentdata',
  'attachmentname',
  'filebytes',
  'filename',
  'filepath',
  'masterkey',
  'masterpassword',
  'mediatype',
  'mimetype',
  'notetext',
  'passkeycredential',
  'plaintextpassword',
  'privatekey',
  'rawdek',
  'rawkek',
  'rawkey',
  'secretvalue',
  'totpsecret',
  'totpuri',
  'wrappedkek',
};
const Set<String> _allowedSyncAadFields = {'mac', 'schema'};
final RegExp _safeSyncAadValuePattern = RegExp(r'^[A-Za-z0-9._~+/=:-]{1,512}$');
final RegExp _safeSyncItemIdPattern = RegExp(r'^[A-Za-z0-9._~+/=:-]{1,255}$');
final RegExp _safeSyncEncryptedValuePattern = RegExp(r'^[A-Za-z0-9._~+/=:-]+$');
final RegExp _plaintextAssignmentPattern = RegExp(
  r'(master|password|plaintext|secret|totp|passkey|raw[_-]?key|raw[_-]?dek|private[_-]?key)\s*[:=]',
  caseSensitive: false,
);
const Set<String> _forbiddenSyncAadValueTerms = {
  'master',
  'password',
  'plaintext',
  'secret',
  'username',
  'note',
  'notes',
  'totp',
  'key',
  'kek',
  'dek',
  'passkey',
  'attachment',
  'decrypted',
  'privatekey',
  'rawdek',
};
const Set<String> _forbiddenSyncItemIdValueTerms = {
  'master',
  'masterkey',
  'password',
  'plaintext',
  'privatekey',
  'rawdek',
  'rawkey',
  'rawkek',
  'secret',
  'secretkey',
  'username',
  'note',
  'notes',
  'totp',
  'totpsecret',
  'key',
  'kek',
  'dek',
  'passkey',
  'attachment',
  'decrypted',
};
const Set<String> _forbiddenSyncEncryptedValueTerms = {
  'masterkey',
  'password',
  'plaintext',
  'privatekey',
  'rawdek',
  'rawkey',
  'rawkek',
  'secret',
  'secretkey',
  'totp',
  'totpsecret',
  'passkey',
  'attachment',
  'decrypted',
};

List<String> findForbiddenSyncFields(Object? payload) {
  final findings = <String>[];
  _scanForbiddenSyncFields(payload, r'$', findings);
  return findings
      .map((path) => path.startsWith(r'$.') ? path.substring(2) : path)
      .toList();
}

void assertNoForbiddenSyncFields(Object? payload) {
  final findings = findForbiddenSyncFields(payload);
  if (findings.isEmpty) {
    return;
  }

  throw StateError('Forbidden sync field(s): ${findings.join(', ')}');
}

void assertSafeSyncItemAad(String aad) {
  try {
    parseSafeSyncItemAad(aad);
  } on FormatException catch (error) {
    throw StateError('Unsafe sync aad: ${error.message}');
  }
}

void assertSafeSyncItemId(String itemId) {
  if (!_safeSyncItemIdPattern.hasMatch(itemId) ||
      _hasForbiddenSyncItemIdValue(itemId)) {
    throw const FormatException('Invalid "item_id": unsafe value');
  }
}

void assertSafeSyncEncryptedValue(String value, String label) {
  if (!_safeSyncEncryptedValuePattern.hasMatch(value) ||
      _hasForbiddenSyncEncryptedValue(value)) {
    throw FormatException('Invalid "$label": unsafe value');
  }
}

void assertSafeSyncOpaqueEncryptedValue(String value, String label) {
  if (!_safeSyncEncryptedValuePattern.hasMatch(value) ||
      _looksLikePlaintextSecretValue(value)) {
    throw FormatException('Invalid "$label": unsafe value');
  }
}

void assertSafeSyncItemsAad(Iterable<Map<String, Object?>> items) {
  for (final item in items) {
    final aad = item['aad'];
    if (aad is! String) {
      throw StateError('Unsafe sync aad: expected a string');
    }
    assertSafeSyncItemAad(aad);
  }
}

Map<String, Object?> parseSafeSyncItemAad(String encoded) {
  final Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on FormatException catch (error) {
    throw FormatException('Invalid "aad" JSON: ${error.message}');
  }
  if (decoded is! Map) {
    throw const FormatException('Invalid "aad": expected an object');
  }
  final aad = Map<String, Object?>.from(decoded);
  final unsupported = aad.keys.toSet().difference(_allowedSyncAadFields);
  if (unsupported.isNotEmpty) {
    throw const FormatException('Invalid "aad": unsupported field');
  }
  if (!aad.containsKey('mac')) {
    throw const FormatException('Invalid "aad": missing mac');
  }
  final forbidden = findForbiddenSyncFields(aad);
  if (forbidden.isNotEmpty) {
    throw const FormatException('Invalid "aad": forbidden field');
  }
  for (final value in aad.values) {
    if (value is! String ||
        !_safeSyncAadValuePattern.hasMatch(value) ||
        _hasForbiddenSyncAadValue(value)) {
      throw const FormatException('Invalid "aad": unsafe value');
    }
  }
  return aad;
}

void _scanForbiddenSyncFields(
  Object? value,
  String path,
  List<String> findings,
) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key;
      final childPath = key is String
          ? '$path.$key'
          : '$path.${key.toString()}';
      if (key is String && _isForbiddenSyncFieldName(key)) {
        findings.add(childPath);
      }
      _scanForbiddenSyncFields(entry.value, childPath, findings);
    }
    return;
  }

  if (value is Iterable) {
    var index = 0;
    for (final element in value) {
      _scanForbiddenSyncFields(element, '$path[$index]', findings);
      index++;
    }
  }
}

String _normalizeSyncFieldName(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

bool _isForbiddenSyncFieldName(String value) {
  final normalized = _normalizeSyncFieldName(value);
  if (_safeProtocolSyncFieldNames.contains(normalized)) {
    return false;
  }
  if (_normalizedForbiddenSyncFieldNames.contains(normalized)) {
    return true;
  }
  if (_forbiddenSyncFieldFragments.any(normalized.contains)) {
    return true;
  }
  return _splitSyncFieldName(value).any(_forbiddenSyncFieldTokens.contains);
}

List<String> _splitSyncFieldName(String value) {
  return value
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((chunk) => chunk.isNotEmpty)
      .expand(
        (chunk) => RegExp(
          r'[A-Z]?[a-z]+|[A-Z]+(?![a-z])|\d+',
        ).allMatches(chunk).map((match) => match.group(0)!.toLowerCase()),
      )
      .toList(growable: false);
}

bool _hasForbiddenSyncAadValue(String value) {
  final normalized = _normalizeSyncFieldName(value);
  return _forbiddenSyncAadValueTerms.any(normalized.contains);
}

bool _hasForbiddenSyncItemIdValue(String value) {
  final normalized = _normalizeSyncFieldName(value);
  return _forbiddenSyncItemIdValueTerms.any(normalized.contains);
}

bool _hasForbiddenSyncEncryptedValue(String value) {
  final normalized = _normalizeSyncFieldName(value);
  return _forbiddenSyncEncryptedValueTerms.any(normalized.contains);
}

bool _looksLikePlaintextSecretValue(String value) {
  return _plaintextAssignmentPattern.hasMatch(value);
}
