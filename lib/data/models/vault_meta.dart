import 'dart:convert';

import 'package:secure_box/core/crypto/kdf_service.dart';

class VaultMeta {
  VaultMeta({
    required this.id,
    required this.version,
    required this.kdf,
    required this.kdfParams,
    required this.salt,
    required this.encryptedDekByMaster,
    required this.encryptedDekByMasterNonce,
    required this.encryptedDekByMasterMac,
    required this.biometricEnabled,
    required this.createdAt,
    required this.updatedAt,
    this.encryptedDekByBiometric,
    this.encryptedDekByBiometricNonce,
    this.encryptedDekByBiometricMac,
  }) {
    _validateConstructorKdfConsistency(kdf: kdf, kdfParams: kdfParams);
  }

  final String id;
  final int version;
  final String kdf;
  final KdfParams kdfParams;
  final String salt;
  final String encryptedDekByMaster;
  final String encryptedDekByMasterNonce;
  final String encryptedDekByMasterMac;
  final bool biometricEnabled;
  final int createdAt;
  final int updatedAt;
  final String? encryptedDekByBiometric;
  final String? encryptedDekByBiometricNonce;
  final String? encryptedDekByBiometricMac;

  Map<String, Object?> toDb() {
    _validateSerializableKdfConsistency(kdf: kdf, kdfParams: kdfParams);

    return {
      'id': id,
      'version': version,
      'kdf': kdf,
      'kdf_params': jsonEncode(kdfParams.toJson()),
      'salt': salt,
      'encrypted_dek_by_master': encryptedDekByMaster,
      'encrypted_dek_by_master_nonce': encryptedDekByMasterNonce,
      'encrypted_dek_by_master_mac': encryptedDekByMasterMac,
      'encrypted_dek_by_biometric': encryptedDekByBiometric,
      'encrypted_dek_by_biometric_nonce': encryptedDekByBiometricNonce,
      'encrypted_dek_by_biometric_mac': encryptedDekByBiometricMac,
      'biometric_enabled': biometricEnabled ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory VaultMeta.fromDb(Map<String, Object?> row) {
    final kdf = row['kdf'] as String;
    final kdfParams = _parseKdfParams(row['kdf_params']);
    _validateDbKdfConsistency(kdf: kdf, kdfParams: kdfParams);
    final biometricEnabled = _parseBiometricEnabled(row['biometric_enabled']);

    return VaultMeta(
      id: row['id'] as String,
      version: row['version'] as int,
      kdf: kdf,
      kdfParams: kdfParams,
      salt: row['salt'] as String,
      encryptedDekByMaster: row['encrypted_dek_by_master'] as String,
      encryptedDekByMasterNonce: row['encrypted_dek_by_master_nonce'] as String,
      encryptedDekByMasterMac: row['encrypted_dek_by_master_mac'] as String,
      encryptedDekByBiometric: row['encrypted_dek_by_biometric'] as String?,
      encryptedDekByBiometricNonce:
          row['encrypted_dek_by_biometric_nonce'] as String?,
      encryptedDekByBiometricMac:
          row['encrypted_dek_by_biometric_mac'] as String?,
      biometricEnabled: biometricEnabled,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }

  static KdfParams _parseKdfParams(Object? rawValue) {
    if (rawValue is! String) {
      throw const FormatException('Invalid kdf_params: expected JSON text');
    }

    final Object? decodedValue;
    try {
      decodedValue = jsonDecode(rawValue);
    } on FormatException catch (error) {
      throw FormatException(
        'Invalid kdf_params JSON text: ${error.message}',
        rawValue,
        error.offset,
      );
    }

    if (decodedValue is! Map<Object?, Object?>) {
      throw FormatException(
        'Invalid kdf_params JSON text: expected an object',
        rawValue,
      );
    }

    final json = Map<String, Object?>.from(decodedValue);
    if (json['name'] is! String ||
        json['iterations'] is! int ||
        json['bits'] is! int) {
      throw FormatException(
        'Invalid kdf_params JSON object: expected string name and integer iterations/bits',
        rawValue,
      );
    }

    return KdfParams.fromJson(json);
  }

  static bool _hasMatchingKdf({
    required String kdf,
    required KdfParams kdfParams,
  }) {
    return kdf == kdfParams.name;
  }

  static void _validateConstructorKdfConsistency({
    required String kdf,
    required KdfParams kdfParams,
  }) {
    if (_hasMatchingKdf(kdf: kdf, kdfParams: kdfParams)) {
      return;
    }

    throw ArgumentError.value(
      kdf,
      'kdf',
      _kdfMismatchMessage(
        kdf: kdf,
        expectedFieldName: 'kdfParams.name',
        expectedValue: kdfParams.name,
      ),
    );
  }

  static void _validateSerializableKdfConsistency({
    required String kdf,
    required KdfParams kdfParams,
  }) {
    if (_hasMatchingKdf(kdf: kdf, kdfParams: kdfParams)) {
      return;
    }

    throw StateError(
      'Invalid vault meta: ${_kdfMismatchMessage(kdf: kdf, expectedFieldName: 'kdfParams.name', expectedValue: kdfParams.name)}',
    );
  }

  static void _validateDbKdfConsistency({
    required String kdf,
    required KdfParams kdfParams,
  }) {
    if (_hasMatchingKdf(kdf: kdf, kdfParams: kdfParams)) {
      return;
    }

    throw FormatException(
      'Invalid vault_meta row: ${_kdfMismatchMessage(kdf: kdf, expectedFieldName: 'kdf_params.name', expectedValue: kdfParams.name)}',
    );
  }

  static bool _parseBiometricEnabled(Object? rawValue) {
    if (rawValue is! int || (rawValue != 0 && rawValue != 1)) {
      throw FormatException(
        'Invalid biometric_enabled: expected integer 0 or 1',
      );
    }

    return rawValue == 1;
  }

  static String _kdfMismatchMessage({
    required String kdf,
    required String expectedFieldName,
    required String expectedValue,
  }) {
    return 'kdf "$kdf" does not match $expectedFieldName "$expectedValue"';
  }
}
