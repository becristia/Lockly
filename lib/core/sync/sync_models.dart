import 'dart:convert';

import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:secure_box/core/sync/sync_payload_guard.dart';
import 'package:secure_box/data/models/encrypted_vault_blob.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:secure_box/data/models/vault_meta.dart';

class SyncAuthTokens {
  const SyncAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'token_type': tokenType,
  };

  factory SyncAuthTokens.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(json, _syncAuthTokenFields, 'auth tokens');
    return SyncAuthTokens(
      accessToken: _readString(json, 'access_token'),
      refreshToken: _readString(json, 'refresh_token'),
      tokenType: _readString(json, 'token_type'),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SyncAuthTokens &&
        other.accessToken == accessToken &&
        other.refreshToken == refreshToken &&
        other.tokenType == tokenType;
  }

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, tokenType);
}

class SyncAccount {
  const SyncAccount({required this.id, required this.email});

  final String id;
  final String email;

  Map<String, Object?> toJson() => {'id': id, 'email': email};

  factory SyncAccount.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(json, _syncAccountFields, 'sync account');
    return SyncAccount(
      id: _readString(json, 'id'),
      email: _readString(json, 'email'),
    );
  }
}

class SyncDevice {
  const SyncDevice({
    required this.id,
    required this.deviceName,
    this.deviceType,
    this.platform,
    this.clientVersion,
    required this.trusted,
    this.lastSyncAt,
    this.lastIpAddress,
    this.lastUserAgent,
    required this.createdAt,
    this.revokedAt,
  });

  final String id;
  final String deviceName;
  final String? deviceType;
  final String? platform;
  final String? clientVersion;
  final bool trusted;
  final String? lastSyncAt;
  final String? lastIpAddress;
  final String? lastUserAgent;
  final String createdAt;
  final String? revokedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'device_name': deviceName,
    'device_type': deviceType,
    'platform': platform,
    'client_version': clientVersion,
    'trusted': trusted,
    'last_sync_at': lastSyncAt,
    'last_ip_address': lastIpAddress,
    'last_user_agent': lastUserAgent,
    'created_at': createdAt,
    'revoked_at': revokedAt,
  };

  factory SyncDevice.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(json, _syncDeviceFields, 'sync device');
    return SyncDevice(
      id: _readString(json, 'id'),
      deviceName: _readString(json, 'device_name'),
      deviceType: _readOptionalString(json, 'device_type'),
      platform: _readOptionalString(json, 'platform'),
      clientVersion: _readOptionalString(json, 'client_version'),
      trusted: _readBool(json, 'trusted'),
      lastSyncAt: _readOptionalString(json, 'last_sync_at'),
      lastIpAddress: _readOptionalString(json, 'last_ip_address'),
      lastUserAgent: _readOptionalString(json, 'last_user_agent'),
      createdAt: _readString(json, 'created_at'),
      revokedAt: _readOptionalString(json, 'revoked_at'),
    );
  }
}

class SyncVaultMetaPayload {
  const SyncVaultMetaPayload._({
    this.id,
    required this.kdf,
    required this.kdfParams,
    required this.salt,
    required this.encryptedDekByMaster,
    this.manifest,
    required this.revision,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String kdf;
  final Map<String, Object?> kdfParams;
  final String salt;
  final String encryptedDekByMaster;
  final Map<String, Object?>? manifest;
  final int revision;
  final String? createdAt;
  final String? updatedAt;

  factory SyncVaultMetaPayload.fromLocal(
    VaultMeta meta, {
    required VaultManifest manifest,
    required int revision,
  }) {
    return SyncVaultMetaPayload._(
      kdf: meta.kdf,
      kdfParams: meta.kdfParams.toJson(),
      salt: meta.salt,
      encryptedDekByMaster: jsonEncode({
        'ciphertext': meta.encryptedDekByMaster,
        'nonce': meta.encryptedDekByMasterNonce,
        'mac': meta.encryptedDekByMasterMac,
      }),
      manifest: {
        'version': manifest.version,
        'epoch': manifest.epoch,
        'counter': manifest.counter,
        'nonce': manifest.nonce,
        'ciphertext': manifest.ciphertext,
        'mac': manifest.mac,
        'updated_at': manifest.updatedAt,
      },
      revision: revision,
    );
  }

  Map<String, Object?> toJson({bool includeRevision = true}) {
    final json = <String, Object?>{
      'kdf': kdf,
      'kdf_params': Map<String, Object?>.unmodifiable(kdfParams),
      'salt': salt,
      'encrypted_dek_by_master': encryptedDekByMaster,
    };
    if (includeRevision) {
      json['revision'] = revision;
    }
    final manifest = this.manifest;
    if (manifest != null) {
      json['manifest'] = Map<String, Object?>.unmodifiable(manifest);
    }
    assertNoForbiddenSyncFields(json);
    return json;
  }

  SyncVaultMetaPayload withRevision(int revision) {
    return SyncVaultMetaPayload._(
      id: id,
      kdf: kdf,
      kdfParams: Map<String, Object?>.unmodifiable(kdfParams),
      salt: salt,
      encryptedDekByMaster: encryptedDekByMaster,
      manifest: manifest == null
          ? null
          : Map<String, Object?>.unmodifiable(manifest!),
      revision: revision,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory SyncVaultMetaPayload.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(json, _syncVaultMetaFields, 'vault metadata');
    final kdf = _readString(json, 'kdf');
    final kdfParams = _readStringObjectMap(json, 'kdf_params');
    _assertSafeKdfParams(kdf, kdfParams);
    final encryptedDekByMaster = _readString(json, 'encrypted_dek_by_master');
    _assertSafeEncryptedEnvelope(
      encryptedDekByMaster,
      'encrypted_dek_by_master',
    );
    final manifest = _readOptionalStringObjectMap(json, 'manifest');
    if (manifest != null) {
      _assertSafeManifest(manifest);
    }
    return SyncVaultMetaPayload._(
      id: _readOptionalString(json, 'id'),
      kdf: kdf,
      kdfParams: kdfParams,
      salt: _readString(json, 'salt'),
      encryptedDekByMaster: encryptedDekByMaster,
      manifest: manifest,
      revision: _readInt(json, 'revision'),
      createdAt: _readOptionalString(json, 'created_at'),
      updatedAt: _readOptionalString(json, 'updated_at'),
    );
  }
}

class SyncItemPayload {
  const SyncItemPayload._({
    required this.ciphertext,
    required this.nonce,
    required this.aad,
    required this.revision,
    required this.deleted,
    required this.clientUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.serverUpdatedAt,
  });

  final String ciphertext;
  final String nonce;
  final String aad;
  final int revision;
  final bool deleted;
  final String clientUpdatedAt;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String? serverUpdatedAt;

  factory SyncItemPayload.fromLocal(
    EncryptedVaultItem item, {
    required int revision,
  }) {
    return SyncItemPayload._(
      ciphertext: item.ciphertext,
      nonce: item.nonce,
      aad: jsonEncode({'mac': item.mac, 'schema': 'lockly-item-v1'}),
      revision: revision,
      deleted: item.deletedAt != null,
      clientUpdatedAt: _isoUtcFromMilliseconds(
        item.deletedAt ?? item.updatedAt,
      ),
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      deletedAt: item.deletedAt,
    );
  }

  Map<String, Object?> toJson() {
    assertSafeSyncItemAad(aad);
    final json = <String, Object?>{
      'ciphertext': ciphertext,
      'nonce': nonce,
      'aad': aad,
      'revision': revision,
      'deleted': deleted,
      'client_updated_at': clientUpdatedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
    final serverUpdatedAt = this.serverUpdatedAt;
    if (serverUpdatedAt != null) {
      json['server_updated_at'] = serverUpdatedAt;
    }
    assertNoForbiddenSyncFields(json);
    return json;
  }

  factory SyncItemPayload.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(json, _syncItemPayloadFields, 'sync item payload');
    final clientUpdatedAt = _readString(json, 'client_updated_at');
    final fallbackMillis = _millisecondsFromIso(clientUpdatedAt);
    final deleted = _readBool(json, 'deleted');
    return SyncItemPayload._(
      ciphertext: _readSafeOpaqueEncryptedValue(json, 'ciphertext'),
      nonce: _readSafeOpaqueEncryptedValue(json, 'nonce'),
      aad: _readSafeAad(json, 'aad'),
      revision: _readInt(json, 'revision'),
      deleted: deleted,
      clientUpdatedAt: clientUpdatedAt,
      createdAt:
          _readOptionalTimestampMillis(json, 'created_at') ?? fallbackMillis,
      updatedAt:
          _readOptionalTimestampMillis(json, 'updated_at') ?? fallbackMillis,
      deletedAt:
          _readOptionalTimestampMillis(json, 'deleted_at') ??
          (deleted ? fallbackMillis : null),
      serverUpdatedAt: _readOptionalString(json, 'server_updated_at'),
    );
  }
}

class SyncItem {
  const SyncItem({required this.id, required this.payload});

  final String id;
  final SyncItemPayload payload;

  Map<String, Object?> toJson() {
    assertSafeSyncItemId(id);
    return {'item_id': id, ...payload.toJson()};
  }

  static void assertSafeRawItems(Iterable<Map<String, Object?>> items) {
    for (final item in items) {
      _assertAllowedSyncFields(item, _syncRawPushItemFields, 'raw sync item');
      final payloadJson = Map<String, Object?>.from(item)..remove('item_id');
      assertSafeSyncItemId(_readString(item, 'item_id'));
      SyncItemPayload.fromJson(payloadJson);
    }
  }

  factory SyncItem.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(json, _syncItemFields, 'sync item');
    final payloadJson = Map<String, Object?>.from(json)..remove('item_id');
    final itemId = _readString(json, 'item_id');
    assertSafeSyncItemId(itemId);
    return SyncItem(id: itemId, payload: SyncItemPayload.fromJson(payloadJson));
  }
}

class SyncConflict {
  const SyncConflict({
    required this.itemId,
    required this.localRevision,
    required this.remoteRevision,
  });

  final String itemId;
  final int localRevision;
  final int remoteRevision;

  Map<String, Object?> toJson() {
    assertSafeSyncItemId(itemId);
    return {
      'item_id': itemId,
      'client_revision': localRevision,
      'server_revision': remoteRevision,
    };
  }

  factory SyncConflict.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(json, _syncConflictFields, 'sync conflict');
    final itemId = _readString(json, 'item_id');
    assertSafeSyncItemId(itemId);
    return SyncConflict(
      itemId: itemId,
      localRevision: _readInt(json, 'client_revision'),
      remoteRevision: _readInt(json, 'server_revision'),
    );
  }
}

class SyncPushResponse {
  const SyncPushResponse({
    this.serverTime,
    required this.applied,
    required this.conflicts,
  });

  final String? serverTime;
  final List<SyncItem> applied;
  final List<SyncConflict> conflicts;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'applied': applied.map((item) => item.toJson()).toList(),
      'conflicts': conflicts.map((conflict) => conflict.toJson()).toList(),
    };
    final serverTime = this.serverTime;
    if (serverTime != null) {
      json['server_time'] = serverTime;
    }
    return json;
  }

  factory SyncPushResponse.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(
      json,
      _syncPushResponseFields,
      'sync push response',
    );
    return SyncPushResponse(
      serverTime: _readOptionalString(json, 'server_time'),
      applied: _readList(json, 'applied', SyncItem.fromJson),
      conflicts: _readList(json, 'conflicts', SyncConflict.fromJson),
    );
  }
}

class SyncPullResponse {
  const SyncPullResponse({required this.serverTime, required this.items});

  final String serverTime;
  final List<SyncItem> items;

  Map<String, Object?> toJson() => {
    'server_time': serverTime,
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory SyncPullResponse.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(
      json,
      _syncPullResponseFields,
      'sync pull response',
    );
    return SyncPullResponse(
      serverTime: _readString(json, 'server_time'),
      items: _readList(json, 'items', SyncItem.fromJson),
    );
  }
}

class SyncBlobPayload {
  const SyncBlobPayload._({
    required this.metadataCiphertext,
    required this.metadataNonce,
    required this.metadataAad,
    required this.ciphertext,
    required this.nonce,
    required this.aad,
    required this.ciphertextSha256,
    required this.ciphertextSize,
    required this.revision,
    required this.deleted,
    required this.clientUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.serverUpdatedAt,
  });

  final String metadataCiphertext;
  final String metadataNonce;
  final String metadataAad;
  final String ciphertext;
  final String nonce;
  final String aad;
  final String ciphertextSha256;
  final int ciphertextSize;
  final int revision;
  final bool deleted;
  final String clientUpdatedAt;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String? serverUpdatedAt;

  factory SyncBlobPayload.fromLocal(
    EncryptedVaultBlob blob, {
    required int revision,
  }) {
    return SyncBlobPayload._(
      metadataCiphertext: blob.metadataCiphertext,
      metadataNonce: blob.metadataNonce,
      metadataAad: jsonEncode({
        'mac': blob.metadataMac,
        'schema': 'lockly-blob-meta-v1',
      }),
      ciphertext: blob.ciphertext,
      nonce: blob.nonce,
      aad: jsonEncode({'mac': blob.mac, 'schema': 'lockly-blob-v1'}),
      ciphertextSha256: hashlib.sha256sum(blob.ciphertext, utf8),
      ciphertextSize: blob.ciphertext.length,
      revision: revision,
      deleted: blob.deletedAt != null,
      clientUpdatedAt: _isoUtcFromMilliseconds(
        blob.deletedAt ?? blob.updatedAt,
      ),
      createdAt: blob.createdAt,
      updatedAt: blob.updatedAt,
      deletedAt: blob.deletedAt,
    );
  }

  Map<String, Object?> toJson() {
    _assertSafeAadSchema(
      metadataAad,
      field: 'metadata_aad',
      schema: 'lockly-blob-meta-v1',
    );
    _assertSafeAadSchema(aad, field: 'aad', schema: 'lockly-blob-v1');
    final json = <String, Object?>{
      'metadata_ciphertext': metadataCiphertext,
      'metadata_nonce': metadataNonce,
      'metadata_aad': metadataAad,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'aad': aad,
      'ciphertext_sha256': ciphertextSha256,
      'ciphertext_size': ciphertextSize,
      'revision': revision,
      'deleted': deleted,
      'client_updated_at': clientUpdatedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
    final serverUpdatedAt = this.serverUpdatedAt;
    if (serverUpdatedAt != null) {
      json['server_updated_at'] = serverUpdatedAt;
    }
    assertNoForbiddenSyncFields(json);
    return json;
  }

  factory SyncBlobPayload.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(json, _syncBlobPayloadFields, 'sync blob payload');
    final ciphertextSha256 = _readString(json, 'ciphertext_sha256');
    if (!_sha256HexPattern.hasMatch(ciphertextSha256)) {
      throw const FormatException(
        'Invalid "ciphertext_sha256": expected SHA-256 hex',
      );
    }
    final ciphertextSize = _readInt(json, 'ciphertext_size');
    if (ciphertextSize < 0) {
      throw const FormatException(
        'Invalid "ciphertext_size": expected a non-negative int',
      );
    }
    final clientUpdatedAt = _readString(json, 'client_updated_at');
    final fallbackMillis = _millisecondsFromIso(clientUpdatedAt);
    final deleted = _readBool(json, 'deleted');
    return SyncBlobPayload._(
      metadataCiphertext: _readSafeOpaqueEncryptedValue(
        json,
        'metadata_ciphertext',
      ),
      metadataNonce: _readSafeOpaqueEncryptedValue(json, 'metadata_nonce'),
      metadataAad: _readSafeAadWithSchema(
        json,
        'metadata_aad',
        'lockly-blob-meta-v1',
      ),
      ciphertext: _readSafeOpaqueEncryptedValue(json, 'ciphertext'),
      nonce: _readSafeOpaqueEncryptedValue(json, 'nonce'),
      aad: _readSafeAadWithSchema(json, 'aad', 'lockly-blob-v1'),
      ciphertextSha256: ciphertextSha256,
      ciphertextSize: ciphertextSize,
      revision: _readInt(json, 'revision'),
      deleted: deleted,
      clientUpdatedAt: clientUpdatedAt,
      createdAt:
          _readOptionalTimestampMillis(json, 'created_at') ?? fallbackMillis,
      updatedAt:
          _readOptionalTimestampMillis(json, 'updated_at') ?? fallbackMillis,
      deletedAt:
          _readOptionalTimestampMillis(json, 'deleted_at') ??
          (deleted ? fallbackMillis : null),
      serverUpdatedAt: _readOptionalString(json, 'server_updated_at'),
    );
  }
}

class SyncBlob {
  const SyncBlob({
    required this.id,
    required this.itemId,
    required this.payload,
  });

  final String id;
  final String itemId;
  final SyncBlobPayload payload;

  Map<String, Object?> toJson() {
    assertSafeSyncItemId(id);
    assertSafeSyncItemId(itemId);
    return {'blob_id': id, 'item_id': itemId, ...payload.toJson()};
  }

  Map<String, Object?> toPushJson() {
    final json = toJson();
    json.remove('server_updated_at');
    return json;
  }

  static void assertSafeRawBlobs(Iterable<Map<String, Object?>> blobs) {
    for (final blob in blobs) {
      _assertAllowedSyncFields(blob, _syncRawPushBlobFields, 'raw sync blob');
      final payloadJson = Map<String, Object?>.from(blob)
        ..remove('blob_id')
        ..remove('item_id');
      assertSafeSyncItemId(_readString(blob, 'blob_id'));
      assertSafeSyncItemId(_readString(blob, 'item_id'));
      SyncBlobPayload.fromJson(payloadJson);
    }
  }

  factory SyncBlob.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(json, _syncBlobFields, 'sync blob');
    final payloadJson = Map<String, Object?>.from(json)
      ..remove('blob_id')
      ..remove('item_id');
    final blobId = _readString(json, 'blob_id');
    final itemId = _readString(json, 'item_id');
    assertSafeSyncItemId(blobId);
    assertSafeSyncItemId(itemId);
    return SyncBlob(
      id: blobId,
      itemId: itemId,
      payload: SyncBlobPayload.fromJson(payloadJson),
    );
  }
}

class SyncBlobConflict {
  const SyncBlobConflict({
    required this.blobId,
    required this.localRevision,
    required this.remoteRevision,
  });

  final String blobId;
  final int localRevision;
  final int remoteRevision;

  Map<String, Object?> toJson() {
    assertSafeSyncItemId(blobId);
    return {
      'blob_id': blobId,
      'client_revision': localRevision,
      'server_revision': remoteRevision,
    };
  }

  factory SyncBlobConflict.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(
      json,
      _syncBlobConflictFields,
      'sync blob conflict',
    );
    final blobId = _readString(json, 'blob_id');
    assertSafeSyncItemId(blobId);
    return SyncBlobConflict(
      blobId: blobId,
      localRevision: _readInt(json, 'client_revision'),
      remoteRevision: _readInt(json, 'server_revision'),
    );
  }
}

class SyncBlobPushResponse {
  const SyncBlobPushResponse({
    this.serverTime,
    required this.applied,
    required this.conflicts,
  });

  final String? serverTime;
  final List<SyncBlob> applied;
  final List<SyncBlobConflict> conflicts;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'applied': applied.map((blob) => blob.toJson()).toList(),
      'conflicts': conflicts.map((conflict) => conflict.toJson()).toList(),
    };
    final serverTime = this.serverTime;
    if (serverTime != null) {
      json['server_time'] = serverTime;
    }
    return json;
  }

  factory SyncBlobPushResponse.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(
      json,
      _syncBlobPushResponseFields,
      'sync blob push response',
    );
    return SyncBlobPushResponse(
      serverTime: _readOptionalString(json, 'server_time'),
      applied: _readList(json, 'applied', SyncBlob.fromJson),
      conflicts: _readList(json, 'conflicts', SyncBlobConflict.fromJson),
    );
  }
}

class SyncBlobPullResponse {
  const SyncBlobPullResponse({required this.serverTime, required this.blobs});

  final String serverTime;
  final List<SyncBlob> blobs;

  Map<String, Object?> toJson() => {
    'server_time': serverTime,
    'blobs': blobs.map((blob) => blob.toJson()).toList(),
  };

  factory SyncBlobPullResponse.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(
      json,
      _syncBlobPullResponseFields,
      'sync blob pull response',
    );
    return SyncBlobPullResponse(
      serverTime: _readString(json, 'server_time'),
      blobs: _readList(json, 'blobs', SyncBlob.fromJson),
    );
  }
}

class SyncVaultPushResponse {
  const SyncVaultPushResponse({
    this.serverTime,
    required this.items,
    required this.blobs,
  });

  final String? serverTime;
  final SyncPushResponse items;
  final SyncBlobPushResponse blobs;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'items': items.toJson(),
      'blobs': blobs.toJson(),
    };
    final serverTime = this.serverTime;
    if (serverTime != null) {
      json['server_time'] = serverTime;
    }
    return json;
  }

  factory SyncVaultPushResponse.fromJson(Map<String, Object?> json) {
    _assertAllowedSyncFields(
      json,
      _syncVaultPushResponseFields,
      'sync vault push response',
    );
    return SyncVaultPushResponse(
      serverTime: _readOptionalString(json, 'server_time'),
      items: SyncPushResponse.fromJson(_readStringObjectMap(json, 'items')),
      blobs: SyncBlobPushResponse.fromJson(_readStringObjectMap(json, 'blobs')),
    );
  }
}

class EmergencyContactCreateRequest {
  const EmergencyContactCreateRequest({
    required this.recipientEmail,
    required this.recipientPublicKey,
    required this.recipientKeyFingerprint,
    this.recipientLabel,
  });

  final String recipientEmail;
  final String recipientPublicKey;
  final String recipientKeyFingerprint;
  final String? recipientLabel;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'recipient_email': recipientEmail,
      'recipient_public_key': recipientPublicKey,
      'recipient_key_fingerprint': recipientKeyFingerprint,
    };
    final recipientLabel = this.recipientLabel;
    if (recipientLabel != null) {
      json['recipient_label'] = recipientLabel;
    }
    try {
      _assertAllowedEmergencyFields(
        json,
        _emergencyContactCreateFields,
        'emergency contact create request',
        allowedForbiddenPaths: _emergencyContactProtocolFields,
      );
      _assertSafeEmergencyToken(recipientPublicKey, 'recipient_public_key');
      _assertSafeEmergencyToken(
        recipientKeyFingerprint,
        'recipient_key_fingerprint',
      );
      _assertSafeEmergencyLabel(recipientLabel, 'recipient_label');
    } on FormatException catch (error) {
      throw StateError('Unsafe emergency contact request: ${error.message}');
    }
    return json;
  }
}

class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.ownerUserId,
    required this.recipientUserId,
    required this.recipientEmail,
    required this.recipientPublicKey,
    required this.recipientKeyFingerprint,
    this.recipientLabel,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.revokedAt,
  });

  final String id;
  final String ownerUserId;
  final String recipientUserId;
  final String? recipientEmail;
  final String recipientPublicKey;
  final String recipientKeyFingerprint;
  final String? recipientLabel;
  final String status;
  final String createdAt;
  final String? updatedAt;
  final String? revokedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'owner_user_id': ownerUserId,
    'recipient_user_id': recipientUserId,
    'recipient_email': recipientEmail,
    'recipient_public_key': recipientPublicKey,
    'recipient_key_fingerprint': recipientKeyFingerprint,
    'recipient_label': recipientLabel,
    'status': status,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'revoked_at': revokedAt,
  };

  factory EmergencyContact.fromJson(Map<String, Object?> json) {
    _assertAllowedEmergencyFields(
      json,
      _emergencyContactFields,
      'emergency contact',
      allowedForbiddenPaths: _emergencyContactProtocolFields,
    );
    final recipientPublicKey = _readString(json, 'recipient_public_key');
    final recipientKeyFingerprint = _readString(
      json,
      'recipient_key_fingerprint',
    );
    final recipientLabel = _readOptionalString(json, 'recipient_label');
    _assertSafeEmergencyToken(recipientPublicKey, 'recipient_public_key');
    _assertSafeEmergencyToken(
      recipientKeyFingerprint,
      'recipient_key_fingerprint',
    );
    _assertSafeEmergencyLabel(recipientLabel, 'recipient_label');
    return EmergencyContact(
      id: _readString(json, 'id'),
      ownerUserId: _readString(json, 'owner_user_id'),
      recipientUserId: _readString(json, 'recipient_user_id'),
      recipientEmail: _readOptionalString(json, 'recipient_email'),
      recipientPublicKey: recipientPublicKey,
      recipientKeyFingerprint: recipientKeyFingerprint,
      recipientLabel: recipientLabel,
      status: _readString(json, 'status'),
      createdAt: _readString(json, 'created_at'),
      updatedAt: _readOptionalString(json, 'updated_at'),
      revokedAt: _readOptionalString(json, 'revoked_at'),
    );
  }
}

class EmergencyContactListResponse {
  const EmergencyContactListResponse({required this.items});

  final List<EmergencyContact> items;

  factory EmergencyContactListResponse.fromJson(Map<String, Object?> json) {
    _assertAllowedEmergencyEnvelopeFields(
      json,
      _emergencyListResponseFields,
      'emergency contacts response',
    );
    return EmergencyContactListResponse(
      items: _readList(json, 'items', EmergencyContact.fromJson),
    );
  }
}

class EmergencyGrantCreateRequest {
  const EmergencyGrantCreateRequest({
    required this.contactId,
    required this.waitingPeriodHours,
    required this.encryptedRecoveryPackage,
    required this.packageAad,
    required this.packageFingerprint,
  });

  final String contactId;
  final int waitingPeriodHours;
  final String encryptedRecoveryPackage;
  final String packageAad;
  final String packageFingerprint;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'contact_id': contactId,
      'waiting_period_hours': waitingPeriodHours,
      'encrypted_recovery_package': encryptedRecoveryPackage,
      'package_aad': packageAad,
      'package_fingerprint': packageFingerprint,
    };
    try {
      _assertAllowedEmergencyFields(
        json,
        _emergencyGrantCreateFields,
        'emergency grant create request',
      );
      assertSafeEmergencyPathSegment(contactId, 'contact_id');
      _assertSafeWaitingPeriod(waitingPeriodHours);
      _assertSafeEmergencyPackageEnvelope(encryptedRecoveryPackage);
      _assertSafeEmergencyPackageAad(packageAad);
      _assertSafeEmergencyToken(packageFingerprint, 'package_fingerprint');
    } on FormatException catch (error) {
      throw StateError('Unsafe emergency grant request: ${error.message}');
    }
    return json;
  }
}

class EmergencyGrantAcceptRequest {
  const EmergencyGrantAcceptRequest({required this.recipientKeyFingerprint});

  final String recipientKeyFingerprint;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'recipient_key_fingerprint': recipientKeyFingerprint,
    };
    try {
      _assertAllowedEmergencyFields(
        json,
        _emergencyGrantAcceptFields,
        'emergency grant accept request',
        allowedForbiddenPaths: _emergencyRecipientKeyProtocolFields,
      );
      _assertSafeEmergencyToken(
        recipientKeyFingerprint,
        'recipient_key_fingerprint',
      );
    } on FormatException catch (error) {
      throw StateError(
        'Unsafe emergency grant accept request: ${error.message}',
      );
    }
    return json;
  }
}

class EmergencyGrantRequestAccessRequest {
  const EmergencyGrantRequestAccessRequest({
    this.requestMessageCiphertext,
    this.requestMessageAad,
  });

  final String? requestMessageCiphertext;
  final String? requestMessageAad;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    final requestMessageCiphertext = this.requestMessageCiphertext;
    final requestMessageAad = this.requestMessageAad;
    if (requestMessageCiphertext != null) {
      json['request_message_ciphertext'] = requestMessageCiphertext;
    }
    if (requestMessageAad != null) {
      json['request_message_aad'] = requestMessageAad;
    }
    try {
      _assertAllowedEmergencyFields(
        json,
        _emergencyGrantRequestAccessFields,
        'emergency grant request-access request',
      );
      if (requestMessageCiphertext != null) {
        _assertSafeEmergencyToken(
          requestMessageCiphertext,
          'request_message_ciphertext',
        );
      }
      if (requestMessageAad != null) {
        _assertSafeEmergencyRequestMessageAad(requestMessageAad);
      }
    } on FormatException catch (error) {
      throw StateError(
        'Unsafe emergency grant request-access request: ${error.message}',
      );
    }
    return json;
  }
}

class EmergencyGrant {
  const EmergencyGrant({
    required this.id,
    required this.ownerUserId,
    required this.recipientUserId,
    required this.contactId,
    required this.vaultId,
    required this.status,
    required this.waitingPeriodHours,
    required this.packageAad,
    required this.packageFingerprint,
    required this.recipientKeyFingerprint,
    this.requestedAt,
    this.readyAt,
    this.downloadedAt,
    this.cancelledAt,
    this.revokedAt,
    this.expiresAt,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ownerUserId;
  final String recipientUserId;
  final String contactId;
  final String? vaultId;
  final String status;
  final int waitingPeriodHours;
  final String packageAad;
  final String packageFingerprint;
  final String? recipientKeyFingerprint;
  final String? requestedAt;
  final String? readyAt;
  final String? downloadedAt;
  final String? cancelledAt;
  final String? revokedAt;
  final String? expiresAt;
  final String createdAt;
  final String? updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'owner_user_id': ownerUserId,
    'recipient_user_id': recipientUserId,
    'contact_id': contactId,
    'vault_id': vaultId,
    'status': status,
    'waiting_period_hours': waitingPeriodHours,
    'package_aad': packageAad,
    'package_fingerprint': packageFingerprint,
    'recipient_key_fingerprint': recipientKeyFingerprint,
    'requested_at': requestedAt,
    'ready_at': readyAt,
    'downloaded_at': downloadedAt,
    'cancelled_at': cancelledAt,
    'revoked_at': revokedAt,
    'expires_at': expiresAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory EmergencyGrant.fromJson(Map<String, Object?> json) {
    _assertAllowedEmergencyFields(
      json,
      _emergencyGrantFields,
      'emergency grant',
      allowedForbiddenPaths: _emergencyGrantProtocolFields,
    );
    final packageAad = _readString(json, 'package_aad');
    final packageFingerprint = _readString(json, 'package_fingerprint');
    final recipientKeyFingerprint = _readOptionalString(
      json,
      'recipient_key_fingerprint',
    );
    _assertSafeEmergencyPackageAad(packageAad);
    _assertSafeEmergencyToken(packageFingerprint, 'package_fingerprint');
    if (recipientKeyFingerprint != null) {
      _assertSafeEmergencyToken(
        recipientKeyFingerprint,
        'recipient_key_fingerprint',
      );
    }
    final waitingPeriodHours = _readInt(json, 'waiting_period_hours');
    _assertSafeWaitingPeriod(waitingPeriodHours);
    return EmergencyGrant(
      id: _readString(json, 'id'),
      ownerUserId: _readString(json, 'owner_user_id'),
      recipientUserId: _readString(json, 'recipient_user_id'),
      contactId: _readString(json, 'contact_id'),
      vaultId: _readOptionalString(json, 'vault_id'),
      status: _readOfficialEmergencyStatus(json, 'status'),
      waitingPeriodHours: waitingPeriodHours,
      packageAad: packageAad,
      packageFingerprint: packageFingerprint,
      recipientKeyFingerprint: recipientKeyFingerprint,
      requestedAt: _readOptionalString(json, 'requested_at'),
      readyAt: _readOptionalString(json, 'ready_at'),
      downloadedAt: _readOptionalString(json, 'downloaded_at'),
      cancelledAt: _readOptionalString(json, 'cancelled_at'),
      revokedAt: _readOptionalString(json, 'revoked_at'),
      expiresAt: _readOptionalString(json, 'expires_at'),
      createdAt: _readString(json, 'created_at'),
      updatedAt: _readOptionalString(json, 'updated_at'),
    );
  }
}

class EmergencyGrantListResponse {
  const EmergencyGrantListResponse({required this.items});

  final List<EmergencyGrant> items;

  factory EmergencyGrantListResponse.fromJson(Map<String, Object?> json) {
    _assertAllowedEmergencyEnvelopeFields(
      json,
      _emergencyListResponseFields,
      'emergency grants response',
    );
    return EmergencyGrantListResponse(
      items: _readList(json, 'items', EmergencyGrant.fromJson),
    );
  }
}

class EmergencyAccessPackage {
  const EmergencyAccessPackage({
    required this.grantId,
    required this.ownerUserId,
    required this.recipientUserId,
    required this.contactId,
    required this.status,
    required this.encryptedRecoveryPackage,
    required this.packageAad,
    required this.packageFingerprint,
    required this.recipientKeyFingerprint,
    this.downloadedAt,
  });

  final String grantId;
  final String ownerUserId;
  final String recipientUserId;
  final String contactId;
  final String status;
  final String encryptedRecoveryPackage;
  final String packageAad;
  final String packageFingerprint;
  final String? recipientKeyFingerprint;
  final String? downloadedAt;

  factory EmergencyAccessPackage.fromJson(Map<String, Object?> json) {
    _assertAllowedEmergencyFields(
      json,
      _emergencyAccessPackageFields,
      'emergency access package',
      allowedForbiddenPaths: _emergencyPackageProtocolFields,
    );
    final encryptedRecoveryPackage = _readString(
      json,
      'encrypted_recovery_package',
    );
    final packageAad = _readString(json, 'package_aad');
    final packageFingerprint = _readString(json, 'package_fingerprint');
    final recipientKeyFingerprint = _readOptionalString(
      json,
      'recipient_key_fingerprint',
    );
    _assertSafeEmergencyPackageEnvelope(encryptedRecoveryPackage);
    _assertSafeEmergencyPackageAad(packageAad);
    _assertSafeEmergencyToken(packageFingerprint, 'package_fingerprint');
    if (recipientKeyFingerprint != null) {
      _assertSafeEmergencyToken(
        recipientKeyFingerprint,
        'recipient_key_fingerprint',
      );
    }
    return EmergencyAccessPackage(
      grantId: _readString(json, 'grant_id'),
      ownerUserId: _readString(json, 'owner_user_id'),
      recipientUserId: _readString(json, 'recipient_user_id'),
      contactId: _readString(json, 'contact_id'),
      status: _readOfficialEmergencyStatus(json, 'status'),
      encryptedRecoveryPackage: encryptedRecoveryPackage,
      packageAad: packageAad,
      packageFingerprint: packageFingerprint,
      recipientKeyFingerprint: recipientKeyFingerprint,
      downloadedAt: _readOptionalString(json, 'downloaded_at'),
    );
  }
}

String _readString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String) {
    throw FormatException('Invalid "$field": expected a string');
  }
  return value;
}

String _readOfficialEmergencyStatus(Map<String, Object?> json, String field) {
  final value = _readString(json, field);
  if (!_officialEmergencyStatuses.contains(value)) {
    throw FormatException('Invalid "$field": unsupported emergency status');
  }
  return value;
}

int _readInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! int) {
    throw FormatException('Invalid "$field": expected an int');
  }
  return value;
}

int? _readOptionalTimestampMillis(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! int || value < 0) {
    throw FormatException(
      'Invalid "$field": expected a non-negative int or null',
    );
  }
  return value;
}

String? _readOptionalString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Invalid "$field": expected a string or null');
  }
  return value;
}

String _readSafeAad(Map<String, Object?> json, String field) {
  final value = _readString(json, field);
  parseSafeSyncItemAad(value);
  return value;
}

String _readSafeAadWithSchema(
  Map<String, Object?> json,
  String field,
  String schema,
) {
  final value = _readString(json, field);
  _assertSafeAadSchema(value, field: field, schema: schema);
  return value;
}

String _readSafeOpaqueEncryptedValue(Map<String, Object?> json, String field) {
  final value = _readString(json, field);
  assertSafeSyncOpaqueEncryptedValue(value, field);
  return value;
}

void _assertSafeAadSchema(
  String value, {
  required String field,
  required String schema,
}) {
  final aad = parseSafeSyncItemAad(value);
  if (aad['schema'] != schema) {
    throw FormatException('Invalid "$field": unsupported schema');
  }
}

bool _readBool(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! bool) {
    throw FormatException('Invalid "$field": expected a bool');
  }
  return value;
}

Map<String, Object?> _readStringObjectMap(
  Map<String, Object?> json,
  String field,
) {
  final value = json[field];
  if (value is! Map) {
    throw FormatException('Invalid "$field": expected an object');
  }
  return Map<String, Object?>.from(value);
}

Map<String, Object?>? _readOptionalStringObjectMap(
  Map<String, Object?> json,
  String field,
) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    throw FormatException('Invalid "$field": expected an object or null');
  }
  return Map<String, Object?>.from(value);
}

List<T> _readList<T>(
  Map<String, Object?> json,
  String field,
  T Function(Map<String, Object?> json) fromJson,
) {
  final value = json[field];
  if (value is! List) {
    throw FormatException('Invalid "$field": expected a list');
  }
  return value.map((item) {
    if (item is! Map) {
      throw FormatException('Invalid "$field": expected object entries');
    }
    return fromJson(Map<String, Object?>.from(item));
  }).toList();
}

const Set<String> _syncVaultMetaFields = {
  'id',
  'version',
  'revision',
  'kdf',
  'kdf_params',
  'salt',
  'encrypted_dek_by_master',
  'manifest',
  'created_at',
  'updated_at',
};
const Set<String> _syncItemPayloadFields = {
  'ciphertext',
  'nonce',
  'aad',
  'revision',
  'deleted',
  'client_updated_at',
  'created_at',
  'updated_at',
  'deleted_at',
  'server_updated_at',
};
const Set<String> _syncItemFields = {'item_id', ..._syncItemPayloadFields};
const Set<String> _syncRawPushItemFields = {
  'item_id',
  'ciphertext',
  'nonce',
  'aad',
  'revision',
  'deleted',
  'client_updated_at',
  'created_at',
  'updated_at',
  'deleted_at',
};
const Set<String> _syncConflictFields = {
  'item_id',
  'client_revision',
  'server_revision',
};
const Set<String> _syncPushResponseFields = {
  'server_time',
  'applied',
  'conflicts',
};
const Set<String> _syncPullResponseFields = {'server_time', 'items'};
const Set<String> _syncBlobPayloadFields = {
  'metadata_ciphertext',
  'metadata_nonce',
  'metadata_aad',
  'ciphertext',
  'nonce',
  'aad',
  'ciphertext_sha256',
  'ciphertext_size',
  'revision',
  'deleted',
  'client_updated_at',
  'created_at',
  'updated_at',
  'deleted_at',
  'server_updated_at',
};
const Set<String> _syncBlobFields = {
  'blob_id',
  'item_id',
  ..._syncBlobPayloadFields,
};
const Set<String> _syncRawPushBlobFields = {
  'blob_id',
  'item_id',
  'metadata_ciphertext',
  'metadata_nonce',
  'metadata_aad',
  'ciphertext',
  'nonce',
  'aad',
  'ciphertext_sha256',
  'ciphertext_size',
  'revision',
  'deleted',
  'client_updated_at',
  'created_at',
  'updated_at',
  'deleted_at',
};
const Set<String> _syncBlobConflictFields = {
  'blob_id',
  'client_revision',
  'server_revision',
};
const Set<String> _syncBlobPushResponseFields = {
  'server_time',
  'applied',
  'conflicts',
};
const Set<String> _syncBlobPullResponseFields = {'server_time', 'blobs'};
const Set<String> _syncVaultPushResponseFields = {
  'server_time',
  'items',
  'blobs',
};
const Set<String> _syncAuthTokenFields = {
  'access_token',
  'refresh_token',
  'token_type',
};
const Set<String> _syncAccountFields = {'id', 'email'};
const Set<String> _syncDeviceFields = {
  'id',
  'device_name',
  'device_type',
  'platform',
  'client_version',
  'trusted',
  'last_sync_at',
  'last_ip_address',
  'last_user_agent',
  'created_at',
  'revoked_at',
};
const Set<String> _vaultManifestFields = {
  'version',
  'epoch',
  'counter',
  'nonce',
  'ciphertext',
  'mac',
  'updated_at',
};
const Set<String> _emergencyContactCreateFields = {
  'recipient_email',
  'recipient_public_key',
  'recipient_key_fingerprint',
  'recipient_label',
};
const Set<String> _emergencyContactFields = {
  'id',
  'owner_user_id',
  'recipient_user_id',
  'recipient_email',
  'recipient_public_key',
  'recipient_key_fingerprint',
  'recipient_label',
  'status',
  'created_at',
  'updated_at',
  'revoked_at',
};
const Set<String> _emergencyGrantCreateFields = {
  'contact_id',
  'waiting_period_hours',
  'encrypted_recovery_package',
  'package_aad',
  'package_fingerprint',
};
const Set<String> _emergencyGrantAcceptFields = {'recipient_key_fingerprint'};
const Set<String> _emergencyGrantRequestAccessFields = {
  'request_message_ciphertext',
  'request_message_aad',
};
const Set<String> _emergencyGrantFields = {
  'id',
  'owner_user_id',
  'recipient_user_id',
  'contact_id',
  'vault_id',
  'status',
  'waiting_period_hours',
  'package_aad',
  'package_fingerprint',
  'recipient_key_fingerprint',
  'requested_at',
  'ready_at',
  'downloaded_at',
  'cancelled_at',
  'revoked_at',
  'expires_at',
  'created_at',
  'updated_at',
};
const Set<String> _emergencyAccessPackageFields = {
  'grant_id',
  'owner_user_id',
  'recipient_user_id',
  'contact_id',
  'status',
  'encrypted_recovery_package',
  'package_aad',
  'package_fingerprint',
  'recipient_key_fingerprint',
  'downloaded_at',
};
const Set<String> _emergencyListResponseFields = {'items'};
const Set<String> _emergencyContactProtocolFields = {
  'recipient_public_key',
  'recipient_key_fingerprint',
};
const Set<String> _emergencyRecipientKeyProtocolFields = {
  'recipient_key_fingerprint',
};
const Set<String> _emergencyGrantProtocolFields = {'recipient_key_fingerprint'};
const Set<String> _emergencyPackageProtocolFields = {
  'recipient_key_fingerprint',
};
const Set<String> _emergencyEnvelopeFields = {'ciphertext', 'nonce', 'mac'};
const Set<String> _emergencyPackageAadFields = {
  'schema',
  'mac',
  'grant_id',
  'recipient_key_fingerprint',
};
const Set<String> _emergencyRequestMessageAadFields = {'schema', 'mac'};
const Set<String> _officialEmergencyStatuses = {
  'pending_acceptance',
  'active',
  'access_requested',
  'ready_for_download',
  'downloaded',
  'cancelled',
  'revoked',
  'expired',
};
const Set<String> _allowedKdfNames = {'argon2id', 'pbkdf2-hmac-sha256'};
final RegExp _sha256HexPattern = RegExp(r'^[0-9a-fA-F]{64}$');
final RegExp _safeEmergencyTokenPattern = RegExp(r'^[A-Za-z0-9._~+/=:-]+$');
final RegExp _safeEmergencyPathSegmentPattern = RegExp(r'^[A-Za-z0-9._~-]+$');
const Set<String> _allowedKdfParamFields = {
  'name',
  'm',
  't',
  'p',
  'memory',
  'memoryKiB',
  'iterations',
  'parallelism',
  'bits',
};
const Set<String> _encryptedEnvelopeFields = {'ciphertext', 'nonce', 'mac'};
const Set<String> _emergencyForbiddenValueMarkers = {
  'masterpassword',
  'masterkey',
  'rawkek',
  'rawdek',
  'recoveryplaintext',
  'recipientprivatekey',
  'wrappedprivatekey',
  'passkeyprivatematerial',
  'passkeyprivatekey',
  'itemplaintext',
  'filebytes',
  'private',
  'privatekey',
  'password',
  'plaintext',
  'secret',
  'totp',
  'passkey',
  'username',
  'note',
  'notes',
  'filename',
  'decrypted',
};
const Set<String> _emergencyForbiddenLabelValueMarkers = {
  ..._emergencyForbiddenValueMarkers,
  'kek',
  'dek',
};

void _assertAllowedSyncFields(
  Map<String, Object?> json,
  Set<String> allowedFields,
  String label,
) {
  final forbidden = findForbiddenSyncFields(json);
  if (forbidden.isNotEmpty) {
    throw FormatException(
      'Invalid "$label": forbidden field ${forbidden.first}',
    );
  }
  final unsupported = json.keys.toSet().difference(allowedFields);
  if (unsupported.isNotEmpty) {
    throw FormatException(
      'Invalid "$label": unsupported field ${unsupported.first}',
    );
  }
}

void _assertAllowedEmergencyFields(
  Map<String, Object?> json,
  Set<String> allowedFields,
  String label, {
  Set<String> allowedForbiddenPaths = const {},
}) {
  final forbidden = findForbiddenSyncFields(
    json,
  ).where((path) => !allowedForbiddenPaths.contains(path)).toList();
  if (forbidden.isNotEmpty) {
    throw FormatException(
      'Invalid "$label": forbidden field ${forbidden.first}',
    );
  }
  final unsupported = json.keys.toSet().difference(allowedFields);
  if (unsupported.isNotEmpty) {
    throw FormatException(
      'Invalid "$label": unsupported field ${unsupported.first}',
    );
  }
}

void _assertAllowedEmergencyEnvelopeFields(
  Map<String, Object?> json,
  Set<String> allowedFields,
  String label,
) {
  final unsupported = json.keys.toSet().difference(allowedFields);
  if (unsupported.isNotEmpty) {
    final forbidden = findForbiddenSyncFields({unsupported.first: null});
    if (forbidden.isNotEmpty) {
      throw FormatException(
        'Invalid "$label": forbidden field ${unsupported.first}',
      );
    }
    throw FormatException(
      'Invalid "$label": unsupported field ${unsupported.first}',
    );
  }
}

void _assertSafeEmergencyToken(String value, String label) {
  final normalized = _normalizeEmergencyValue(value);
  if (!_safeEmergencyTokenPattern.hasMatch(value) ||
      _emergencyForbiddenValueMarkers.any(normalized.contains)) {
    throw FormatException('Invalid "$label": unsafe value');
  }
}

void assertSafeEmergencyPathSegment(String value, String label) {
  final normalized = _normalizeEmergencyValue(value);
  if (value.isEmpty ||
      value == '.' ||
      value.contains('..') ||
      !_safeEmergencyPathSegmentPattern.hasMatch(value) ||
      _emergencyForbiddenValueMarkers.any(normalized.contains)) {
    throw FormatException('Invalid "$label": unsafe path segment');
  }
}

void _assertSafeEmergencyLabel(String? value, String label) {
  if (value == null) {
    return;
  }
  final normalized = _normalizeEmergencyValue(value);
  if (_emergencyForbiddenLabelValueMarkers.any(normalized.contains)) {
    throw FormatException('Invalid "$label": unsafe value');
  }
}

void _assertSafeWaitingPeriod(int value) {
  if (value < 1 || value > 2160) {
    throw const FormatException(
      'Invalid "waiting_period_hours": expected 1..2160',
    );
  }
}

void _assertSafeEmergencyPackageEnvelope(String encoded) {
  final envelope = _parseEmergencyObjectString(
    encoded,
    'encrypted_recovery_package',
  );
  _assertAllowedEmergencyFields(
    envelope,
    _emergencyEnvelopeFields,
    'encrypted_recovery_package',
  );
  if (envelope.keys.toSet().length != _emergencyEnvelopeFields.length) {
    throw const FormatException(
      'Invalid "encrypted_recovery_package": missing field',
    );
  }
  for (final field in _emergencyEnvelopeFields) {
    _assertSafeEmergencyToken(
      _readString(envelope, field),
      'encrypted_recovery_package.$field',
    );
  }
}

void _assertSafeEmergencyPackageAad(String encoded) {
  final aad = _parseEmergencyObjectString(encoded, 'package_aad');
  _assertAllowedEmergencyFields(
    aad,
    _emergencyPackageAadFields,
    'package_aad',
    allowedForbiddenPaths: _emergencyRecipientKeyProtocolFields,
  );
  if (aad['schema'] != 'lockly-emergency-package-v1') {
    throw const FormatException('Invalid "package_aad": unsupported schema');
  }
  if (!aad.containsKey('mac')) {
    throw const FormatException('Invalid "package_aad": missing mac');
  }
  for (final entry in aad.entries) {
    final value = entry.value;
    if (value is! String) {
      throw FormatException(
        'Invalid "package_aad.${entry.key}": expected a string',
      );
    }
    _assertSafeEmergencyToken(value, 'package_aad.${entry.key}');
  }
}

void _assertSafeEmergencyRequestMessageAad(String encoded) {
  final aad = _parseEmergencyObjectString(encoded, 'request_message_aad');
  _assertAllowedEmergencyFields(
    aad,
    _emergencyRequestMessageAadFields,
    'request_message_aad',
  );
  final schema = aad['schema'];
  if (schema != null && schema != 'lockly-emergency-request-v1') {
    throw const FormatException(
      'Invalid "request_message_aad": unsupported schema',
    );
  }
  if (!aad.containsKey('mac')) {
    throw const FormatException('Invalid "request_message_aad": missing mac');
  }
  for (final entry in aad.entries) {
    final value = entry.value;
    if (value is! String) {
      throw FormatException(
        'Invalid "request_message_aad.${entry.key}": expected a string',
      );
    }
    _assertSafeEmergencyToken(value, 'request_message_aad.${entry.key}');
  }
}

Map<String, Object?> _parseEmergencyObjectString(String encoded, String field) {
  final Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on FormatException catch (error) {
    throw FormatException('Invalid "$field" JSON: ${error.message}');
  }
  if (decoded is! Map) {
    throw FormatException('Invalid "$field": expected an object');
  }
  return Map<String, Object?>.from(decoded);
}

String _normalizeEmergencyValue(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

void _assertSafeKdfParams(String kdf, Map<String, Object?> kdfParams) {
  if (!_allowedKdfNames.contains(kdf)) {
    throw const FormatException('Invalid "kdf": unsupported KDF');
  }
  final unsupported = kdfParams.keys.toSet().difference(_allowedKdfParamFields);
  if (unsupported.isNotEmpty) {
    throw FormatException(
      'Invalid "kdf_params": unsupported field ${unsupported.first}',
    );
  }
  for (final entry in kdfParams.entries) {
    if (entry.key == 'name') {
      if (entry.value != kdf) {
        throw const FormatException('Invalid "kdf_params.name": KDF mismatch');
      }
      continue;
    }
    if (entry.value is! int || entry.value is bool) {
      throw FormatException(
        'Invalid "kdf_params.${entry.key}": expected an int',
      );
    }
  }
}

void _assertSafeManifest(Map<String, Object?> manifest) {
  _assertAllowedSyncFields(manifest, _vaultManifestFields, 'vault manifest');
  for (final field in ['version', 'epoch', 'counter', 'updated_at']) {
    _readInt(manifest, field);
  }
  for (final field in ['nonce', 'ciphertext', 'mac']) {
    final value = _readString(manifest, field);
    assertSafeSyncEncryptedValue(value, 'vault manifest.$field');
  }
  if (manifest.keys.toSet().length != _vaultManifestFields.length) {
    throw const FormatException('Invalid "vault manifest": missing field');
  }
}

void _assertSafeEncryptedEnvelope(String encoded, String label) {
  final Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on FormatException catch (error) {
    throw FormatException('Invalid "$label" JSON: ${error.message}');
  }
  if (decoded is! Map) {
    throw FormatException('Invalid "$label": expected an object');
  }
  final envelope = Map<String, Object?>.from(decoded);
  _assertAllowedSyncFields(envelope, _encryptedEnvelopeFields, label);
  if (envelope.keys.toSet().length != _encryptedEnvelopeFields.length) {
    throw FormatException('Invalid "$label": missing field');
  }
  for (final field in _encryptedEnvelopeFields) {
    final value = _readString(envelope, field);
    assertSafeSyncEncryptedValue(value, '$label.$field');
  }
}

String _isoUtcFromMilliseconds(int millisecondsSinceEpoch) {
  return DateTime.fromMillisecondsSinceEpoch(
    millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

int _millisecondsFromIso(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException(
      'Invalid "client_updated_at": expected an ISO timestamp',
    );
  }
  return parsed.toUtc().millisecondsSinceEpoch;
}
