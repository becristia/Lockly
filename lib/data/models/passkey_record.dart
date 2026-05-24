class PasskeyRecord {
  const PasskeyRecord({
    required this.relyingPartyId,
    required this.credentialId,
    required this.userHandle,
    required this.displayName,
    required this.publicKeyAlgorithm,
    required this.platform,
    required this.platformReady,
  });

  final String relyingPartyId;
  final String credentialId;
  final String userHandle;
  final String displayName;
  final String publicKeyAlgorithm;
  final String platform;
  final bool platformReady;

  Map<String, Object?> toJson() => {
    'relying_party_id': relyingPartyId,
    'credential_id': credentialId,
    'user_handle': userHandle,
    'display_name': displayName,
    'public_key_algorithm': publicKeyAlgorithm,
    'platform': platform,
    'platform_ready': platformReady,
  };

  factory PasskeyRecord.fromJson(Map<String, Object?> json) {
    final unsupported = json.keys.toSet().difference(_allowedFields);
    if (unsupported.isNotEmpty) {
      throw FormatException('Invalid passkey field: ${unsupported.first}');
    }
    for (final field in json.keys) {
      if (_isPrivateMaterialField(field)) {
        throw FormatException('Invalid passkey private material field: $field');
      }
    }
    return PasskeyRecord(
      relyingPartyId: _readRequiredString(json, 'relying_party_id'),
      credentialId: _readRequiredString(json, 'credential_id'),
      userHandle: _readRequiredString(json, 'user_handle'),
      displayName: _readRequiredString(json, 'display_name'),
      publicKeyAlgorithm: _readRequiredString(json, 'public_key_algorithm'),
      platform: _readRequiredString(json, 'platform'),
      platformReady: _readRequiredBool(json, 'platform_ready'),
    );
  }

  static String _readRequiredString(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! String) {
      throw FormatException('Invalid passkey "$field": expected a string');
    }
    return value;
  }

  static bool _readRequiredBool(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! bool) {
      throw FormatException('Invalid passkey "$field": expected a bool');
    }
    return value;
  }
}

const Set<String> _allowedFields = {
  'relying_party_id',
  'credential_id',
  'user_handle',
  'display_name',
  'public_key_algorithm',
  'platform',
  'platform_ready',
};

bool _isPrivateMaterialField(String field) {
  final normalized = field
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .toLowerCase();
  return normalized.contains('privatekey') ||
      normalized.contains('rawkey') ||
      normalized.contains('secret') ||
      normalized.contains('credentialprivatekey') ||
      normalized.contains('clientsecret');
}
