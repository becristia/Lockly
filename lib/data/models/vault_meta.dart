import 'dart:convert';

import 'package:secure_box/core/crypto/kdf_service.dart';

class VaultMeta {
  const VaultMeta({
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
  });

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

  Map<String, Object?> toDb() => {
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

  factory VaultMeta.fromDb(Map<String, Object?> row) {
    final decodedKdfParams = jsonDecode(row['kdf_params'] as String);

    return VaultMeta(
      id: row['id'] as String,
      version: row['version'] as int,
      kdf: row['kdf'] as String,
      kdfParams: KdfParams.fromJson(
        Map<String, Object?>.from(decodedKdfParams as Map<Object?, Object?>),
      ),
      salt: row['salt'] as String,
      encryptedDekByMaster: row['encrypted_dek_by_master'] as String,
      encryptedDekByMasterNonce: row['encrypted_dek_by_master_nonce'] as String,
      encryptedDekByMasterMac: row['encrypted_dek_by_master_mac'] as String,
      encryptedDekByBiometric: row['encrypted_dek_by_biometric'] as String?,
      encryptedDekByBiometricNonce:
          row['encrypted_dek_by_biometric_nonce'] as String?,
      encryptedDekByBiometricMac:
          row['encrypted_dek_by_biometric_mac'] as String?,
      biometricEnabled: row['biometric_enabled'] == 1,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }
}
