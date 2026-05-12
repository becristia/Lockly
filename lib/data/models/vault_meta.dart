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
    _validateConstructorBiometricState(
      biometricEnabled: biometricEnabled,
      encryptedDekByBiometric: encryptedDekByBiometric,
      encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
      encryptedDekByBiometricMac: encryptedDekByBiometricMac,
    );
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
    _validateSerializableBiometricState(
      biometricEnabled: biometricEnabled,
      encryptedDekByBiometric: encryptedDekByBiometric,
      encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
      encryptedDekByBiometricMac: encryptedDekByBiometricMac,
    );

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
    final kdf = _readRequiredString(row, 'kdf');
    final kdfParams = _parseKdfParams(row['kdf_params']);
    _validateDbKdfConsistency(kdf: kdf, kdfParams: kdfParams);
    final biometricEnabled = _parseBiometricEnabled(
      _readRequiredInt(row, 'biometric_enabled'),
    );
    final encryptedDekByBiometric = _readNullableString(
      row,
      'encrypted_dek_by_biometric',
    );
    final encryptedDekByBiometricNonce = _readNullableString(
      row,
      'encrypted_dek_by_biometric_nonce',
    );
    final encryptedDekByBiometricMac = _readNullableString(
      row,
      'encrypted_dek_by_biometric_mac',
    );
    _validateDbBiometricState(
      biometricEnabled: biometricEnabled,
      encryptedDekByBiometric: encryptedDekByBiometric,
      encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
      encryptedDekByBiometricMac: encryptedDekByBiometricMac,
    );

    return VaultMeta(
      id: _readRequiredString(row, 'id'),
      version: _readRequiredInt(row, 'version'),
      kdf: kdf,
      kdfParams: kdfParams,
      salt: _readRequiredString(row, 'salt'),
      encryptedDekByMaster: _readRequiredString(row, 'encrypted_dek_by_master'),
      encryptedDekByMasterNonce: _readRequiredString(
        row,
        'encrypted_dek_by_master_nonce',
      ),
      encryptedDekByMasterMac: _readRequiredString(
        row,
        'encrypted_dek_by_master_mac',
      ),
      encryptedDekByBiometric: encryptedDekByBiometric,
      encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
      encryptedDekByBiometricMac: encryptedDekByBiometricMac,
      biometricEnabled: biometricEnabled,
      createdAt: _readRequiredInt(row, 'created_at'),
      updatedAt: _readRequiredInt(row, 'updated_at'),
    );
  }

  static String _readRequiredString(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value is! String) {
      throw FormatException('Invalid "$field": expected a string');
    }

    return value;
  }

  static String? _readNullableString(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException('Invalid "$field": expected a string or null');
    }

    return value;
  }

  static int _readRequiredInt(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value is! int) {
      throw FormatException('Invalid "$field": expected an int');
    }

    return value;
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

  static bool _hasCompleteBiometricTuple({
    required String? encryptedDekByBiometric,
    required String? encryptedDekByBiometricNonce,
    required String? encryptedDekByBiometricMac,
  }) {
    return encryptedDekByBiometric != null &&
        encryptedDekByBiometricNonce != null &&
        encryptedDekByBiometricMac != null;
  }

  static bool _hasEmptyBiometricTuple({
    required String? encryptedDekByBiometric,
    required String? encryptedDekByBiometricNonce,
    required String? encryptedDekByBiometricMac,
  }) {
    return encryptedDekByBiometric == null &&
        encryptedDekByBiometricNonce == null &&
        encryptedDekByBiometricMac == null;
  }

  static bool _hasValidBiometricState({
    required bool biometricEnabled,
    required String? encryptedDekByBiometric,
    required String? encryptedDekByBiometricNonce,
    required String? encryptedDekByBiometricMac,
  }) {
    if (biometricEnabled) {
      return _hasCompleteBiometricTuple(
        encryptedDekByBiometric: encryptedDekByBiometric,
        encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
        encryptedDekByBiometricMac: encryptedDekByBiometricMac,
      );
    }

    return _hasEmptyBiometricTuple(
      encryptedDekByBiometric: encryptedDekByBiometric,
      encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
      encryptedDekByBiometricMac: encryptedDekByBiometricMac,
    );
  }

  static void _validateConstructorBiometricState({
    required bool biometricEnabled,
    required String? encryptedDekByBiometric,
    required String? encryptedDekByBiometricNonce,
    required String? encryptedDekByBiometricMac,
  }) {
    if (_hasValidBiometricState(
      biometricEnabled: biometricEnabled,
      encryptedDekByBiometric: encryptedDekByBiometric,
      encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
      encryptedDekByBiometricMac: encryptedDekByBiometricMac,
    )) {
      return;
    }

    throw ArgumentError.value(
      biometricEnabled,
      'biometricEnabled',
      _biometricStateMismatchMessage(
        biometricEnabledFieldName: 'biometricEnabled',
        biometricEnabledValue: biometricEnabled,
        encryptedDekByBiometricFieldName: 'encryptedDekByBiometric',
        encryptedDekByBiometricNonceFieldName: 'encryptedDekByBiometricNonce',
        encryptedDekByBiometricMacFieldName: 'encryptedDekByBiometricMac',
      ),
    );
  }

  static void _validateSerializableBiometricState({
    required bool biometricEnabled,
    required String? encryptedDekByBiometric,
    required String? encryptedDekByBiometricNonce,
    required String? encryptedDekByBiometricMac,
  }) {
    if (_hasValidBiometricState(
      biometricEnabled: biometricEnabled,
      encryptedDekByBiometric: encryptedDekByBiometric,
      encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
      encryptedDekByBiometricMac: encryptedDekByBiometricMac,
    )) {
      return;
    }

    throw StateError(
      'Invalid vault meta: ${_biometricStateMismatchMessage(biometricEnabledFieldName: 'biometricEnabled', biometricEnabledValue: biometricEnabled, encryptedDekByBiometricFieldName: 'encryptedDekByBiometric', encryptedDekByBiometricNonceFieldName: 'encryptedDekByBiometricNonce', encryptedDekByBiometricMacFieldName: 'encryptedDekByBiometricMac')}',
    );
  }

  static void _validateDbBiometricState({
    required bool biometricEnabled,
    required String? encryptedDekByBiometric,
    required String? encryptedDekByBiometricNonce,
    required String? encryptedDekByBiometricMac,
  }) {
    if (_hasValidBiometricState(
      biometricEnabled: biometricEnabled,
      encryptedDekByBiometric: encryptedDekByBiometric,
      encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
      encryptedDekByBiometricMac: encryptedDekByBiometricMac,
    )) {
      return;
    }

    throw FormatException(
      'Invalid vault_meta row: ${_biometricStateMismatchMessage(biometricEnabledFieldName: 'biometric_enabled', biometricEnabledValue: biometricEnabled ? 1 : 0, encryptedDekByBiometricFieldName: 'encrypted_dek_by_biometric', encryptedDekByBiometricNonceFieldName: 'encrypted_dek_by_biometric_nonce', encryptedDekByBiometricMacFieldName: 'encrypted_dek_by_biometric_mac')}',
    );
  }

  static String _kdfMismatchMessage({
    required String kdf,
    required String expectedFieldName,
    required String expectedValue,
  }) {
    return 'kdf "$kdf" does not match $expectedFieldName "$expectedValue"';
  }

  static String _biometricStateMismatchMessage({
    required String biometricEnabledFieldName,
    required Object biometricEnabledValue,
    required String encryptedDekByBiometricFieldName,
    required String encryptedDekByBiometricNonceFieldName,
    required String encryptedDekByBiometricMacFieldName,
  }) {
    final requirement =
        '$encryptedDekByBiometricFieldName, $encryptedDekByBiometricNonceFieldName, and $encryptedDekByBiometricMacFieldName';
    final expectation =
        '$biometricEnabledFieldName "$biometricEnabledValue" requires $requirement to all be ${biometricEnabledValue == true || biometricEnabledValue == 1 ? 'present' : 'absent'}';

    return expectation;
  }
}
