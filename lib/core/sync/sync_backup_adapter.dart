import 'dart:convert';

import 'package:secure_box/core/backup/backup_service.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/core/sync/sync_payload_guard.dart';

VaultBackup cloudVaultBackupFromSync({
  required SyncVaultMetaPayload meta,
  required List<SyncItem> items,
  List<SyncBlob> blobs = const [],
}) {
  final manifestJson = meta.manifest;
  if (manifestJson == null) {
    throw const BackupFormatException(
      'Cloud vault metadata is missing manifest integrity data',
    );
  }
  final dekEnvelope = _readEnvelope(meta.encryptedDekByMaster);
  final backupItems = items.map(_backupItemFromSync).toList(growable: false);
  final itemIds = backupItems.map((item) => item.id).toSet();
  final backupBlobs = blobs
      .where((blob) => itemIds.contains(blob.itemId))
      .map(_backupBlobFromSync)
      .toList(growable: false);
  final vaultCreatedAt = _requiredIsoMillis(meta.createdAt, 'created_at');
  final vaultUpdatedAt = _requiredIsoMillis(meta.updatedAt, 'updated_at');
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;

  return VaultBackup(
    version: 2,
    magic: 'secure-box-backup',
    createdAt: now,
    scope: 'full',
    itemCount: backupItems.length,
    historyCount: 0,
    vaultId: meta.id ?? 'cloud-vault',
    vaultCreatedAt: vaultCreatedAt,
    vaultUpdatedAt: vaultUpdatedAt,
    biometricEnabled: false,
    encryptedDekByBiometric: null,
    encryptedDekByBiometricNonce: null,
    encryptedDekByBiometricMac: null,
    manifest: BackupManifest.fromJson(manifestJson),
    kdf: meta.kdf,
    kdfParams: meta.kdfParams,
    salt: meta.salt,
    encryptedDekByMaster: dekEnvelope.ciphertext,
    encryptedDekByMasterNonce: dekEnvelope.nonce,
    encryptedDekByMasterMac: dekEnvelope.mac,
    items: backupItems,
    blobs: backupBlobs,
  );
}

BackupItem _backupItemFromSync(SyncItem item) {
  final aad = _readAad(item.payload.aad);
  return BackupItem(
    id: item.id,
    nonce: item.payload.nonce,
    ciphertext: item.payload.ciphertext,
    mac: aad.mac,
    createdAt: item.payload.createdAt,
    updatedAt: item.payload.updatedAt,
    deletedAt: item.payload.deleted ? item.payload.deletedAt : null,
  );
}

BackupBlob _backupBlobFromSync(SyncBlob blob) {
  final metadataAad = _readBlobAad(
    blob.payload.metadataAad,
    expectedSchema: 'lockly-blob-meta-v1',
  );
  final contentAad = _readBlobAad(
    blob.payload.aad,
    expectedSchema: 'lockly-blob-v1',
  );
  return BackupBlob(
    blobId: blob.id,
    itemId: blob.itemId,
    metadataNonce: blob.payload.metadataNonce,
    metadataCiphertext: blob.payload.metadataCiphertext,
    metadataMac: metadataAad.mac,
    nonce: blob.payload.nonce,
    ciphertext: blob.payload.ciphertext,
    mac: contentAad.mac,
    createdAt: blob.payload.createdAt,
    updatedAt: blob.payload.updatedAt,
    deletedAt: blob.payload.deleted ? blob.payload.deletedAt : null,
  );
}

_Envelope _readEnvelope(String encoded) {
  final decoded = _decodeObject(encoded, 'encrypted_dek_by_master');
  final unsupported = decoded.keys.toSet().difference({
    'ciphertext',
    'nonce',
    'mac',
  });
  if (unsupported.isNotEmpty || findForbiddenSyncFields(decoded).isNotEmpty) {
    throw const BackupFormatException(
      'Invalid "encrypted_dek_by_master": unsupported field',
    );
  }
  return _Envelope(
    ciphertext: _requiredSafeString(decoded, 'ciphertext'),
    nonce: _requiredSafeString(decoded, 'nonce'),
    mac: _requiredSafeString(decoded, 'mac'),
  );
}

_Aad _readAad(String? encoded) {
  if (encoded == null) {
    throw const BackupFormatException('Cloud item metadata is missing aad');
  }
  final decoded = _readSafeAad(encoded);
  final schema = decoded['schema'];
  if (schema != 'lockly-item-v1') {
    throw const BackupFormatException('Unsupported cloud item schema');
  }
  return _Aad(mac: _requiredString(decoded, 'mac'));
}

_Aad _readBlobAad(String encoded, {required String expectedSchema}) {
  final decoded = _readSafeAad(encoded);
  final schema = decoded['schema'];
  if (schema != expectedSchema) {
    throw const BackupFormatException('Unsupported cloud blob schema');
  }
  return _Aad(mac: _requiredString(decoded, 'mac'));
}

Map<String, Object?> _readSafeAad(String encoded) {
  try {
    return parseSafeSyncItemAad(encoded);
  } on FormatException catch (error) {
    throw BackupFormatException(error.message);
  }
}

Map<String, Object?> _decodeObject(String encoded, String field) {
  final Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on FormatException catch (error) {
    throw BackupFormatException('Invalid "$field" JSON: ${error.message}');
  }
  if (decoded is! Map) {
    throw BackupFormatException('Invalid "$field": expected an object');
  }
  return Map<String, Object?>.from(decoded);
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String || value.isEmpty) {
    throw BackupFormatException('Invalid "$field": expected a string');
  }
  return value;
}

String _requiredSafeString(Map<String, Object?> json, String field) {
  final value = _requiredString(json, field);
  try {
    assertSafeSyncEncryptedValue(value, 'encrypted_dek_by_master.$field');
  } on FormatException catch (error) {
    throw BackupFormatException(error.message);
  }
  return value;
}

int _requiredIsoMillis(String? value, String field) {
  if (value == null || value.isEmpty) {
    throw BackupFormatException('Invalid "$field": expected an ISO timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw BackupFormatException('Invalid "$field": expected an ISO timestamp');
  }
  return parsed.toUtc().millisecondsSinceEpoch;
}

class _Envelope {
  const _Envelope({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  final String ciphertext;
  final String nonce;
  final String mac;
}

class _Aad {
  const _Aad({required this.mac});

  final String mac;
}
