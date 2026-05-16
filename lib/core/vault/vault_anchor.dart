import 'package:secure_box/core/crypto/encoding.dart';

class VaultAnchor {
  const VaultAnchor({
    required this.vaultId,
    required this.schemaVersion,
    required this.manifestEpoch,
    required this.manifestCounter,
    required this.manifestDigest,
    required this.updatedAt,
  });

  static const currentSchemaVersion = 1;

  final String vaultId;
  final int schemaVersion;
  final int manifestEpoch;
  final int manifestCounter;
  final String manifestDigest;
  final int updatedAt;

  Map<String, Object?> toJson() {
    return {
      'vault_id': vaultId,
      'schema_version': schemaVersion,
      'manifest_epoch': manifestEpoch,
      'manifest_counter': manifestCounter,
      'manifest_digest': manifestDigest,
      'updated_at': updatedAt,
    };
  }

  factory VaultAnchor.fromJson(Map<String, Object?> json) {
    final schemaVersion = _readRequiredInt(json, 'schema_version');
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('Invalid vault anchor schema version');
    }
    final manifestEpoch = _readRequiredInt(json, 'manifest_epoch');
    final manifestCounter = _readRequiredInt(json, 'manifest_counter');
    if (manifestEpoch < 1 || manifestCounter < 1) {
      throw const FormatException('Invalid vault anchor manifest position');
    }

    return VaultAnchor(
      vaultId: _readRequiredString(json, 'vault_id'),
      schemaVersion: schemaVersion,
      manifestEpoch: manifestEpoch,
      manifestCounter: manifestCounter,
      manifestDigest: _readRequiredDigest(json, 'manifest_digest'),
      updatedAt: _readRequiredInt(json, 'updated_at'),
    );
  }

  static String _readRequiredString(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! String || value.isEmpty) {
      throw FormatException('Invalid "$field": expected a non-empty string');
    }
    return value;
  }

  static int _readRequiredInt(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! int) {
      throw FormatException('Invalid "$field": expected an int');
    }
    return value;
  }

  static String _readRequiredDigest(Map<String, Object?> json, String field) {
    final value = _readRequiredString(json, field);
    try {
      if (fromB64(value).length == 32) {
        return value;
      }
    } on FormatException {
      throw FormatException('Invalid "$field": expected a 32-byte digest');
    }

    throw FormatException('Invalid "$field": expected a 32-byte digest');
  }
}
