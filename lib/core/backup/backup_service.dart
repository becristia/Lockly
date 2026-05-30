import 'dart:collection';

import 'package:secure_box/core/cancellation/cancellation_token.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/encrypted_vault_blob.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:secure_box/data/models/vault_meta.dart';
import 'package:uuid/uuid.dart';

const int _legacyBackupVersion = 1;
const int _currentBackupVersion = 2;
const String _backupMagic = 'secure-box-backup';
const String _backupScopeFull = 'full';
const String _backupScopeItem = 'item';
const String _backupScopeSelected = 'selected';
const int _maximumImportedItems = 10000;
const int _maximumImportedFieldLength = 1048576;
const int _maximumImportedPbkdf2Iterations = 2000000;
const int _maximumImportedArgon2MemoryKiB = 262144;
const int _maximumImportedArgon2Iterations = 6;
const int _maximumImportedArgon2Parallelism = 4;

class BackupFormatException extends FormatException {
  const BackupFormatException(super.message, [super.source, super.offset]);
}

class BackupItem {
  const BackupItem({
    required this.id,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String nonce;
  final String ciphertext;
  final String mac;
  final int? createdAt;
  final int? updatedAt;
  final int? deletedAt;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'nonce': nonce,
      'ciphertext': ciphertext,
      'mac': mac,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    };
  }

  factory BackupItem.fromJson(Map<String, Object?> json) {
    return BackupItem(
      id: _readRequiredString(json, 'id'),
      nonce: _readRequiredString(json, 'nonce'),
      ciphertext: _readRequiredString(json, 'ciphertext'),
      mac: _readRequiredString(json, 'mac'),
      createdAt: _readOptionalInt(json, 'created_at'),
      updatedAt: _readOptionalInt(json, 'updated_at'),
      deletedAt: _readOptionalInt(json, 'deleted_at'),
    );
  }
}

class BackupBlob {
  const BackupBlob({
    required this.blobId,
    required this.itemId,
    required this.metadataNonce,
    required this.metadataCiphertext,
    required this.metadataMac,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String blobId;
  final String itemId;
  final String metadataNonce;
  final String metadataCiphertext;
  final String metadataMac;
  final String nonce;
  final String ciphertext;
  final String mac;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  Map<String, Object?> toJson() {
    return {
      'blob_id': blobId,
      'item_id': itemId,
      'metadata_nonce': metadataNonce,
      'metadata_ciphertext': metadataCiphertext,
      'metadata_mac': metadataMac,
      'nonce': nonce,
      'ciphertext': ciphertext,
      'mac': mac,
      'created_at': createdAt,
      'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    };
  }

  factory BackupBlob.fromJson(Map<String, Object?> json) {
    return BackupBlob(
      blobId: _readRequiredString(json, 'blob_id'),
      itemId: _readRequiredString(json, 'item_id'),
      metadataNonce: _readRequiredString(json, 'metadata_nonce'),
      metadataCiphertext: _readRequiredString(json, 'metadata_ciphertext'),
      metadataMac: _readRequiredString(json, 'metadata_mac'),
      nonce: _readRequiredString(json, 'nonce'),
      ciphertext: _readRequiredString(json, 'ciphertext'),
      mac: _readRequiredString(json, 'mac'),
      createdAt: _readRequiredInt(json, 'created_at'),
      updatedAt: _readRequiredInt(json, 'updated_at'),
      deletedAt: _readOptionalInt(json, 'deleted_at'),
    );
  }
}

class BackupHistoryItem {
  const BackupHistoryItem({
    required this.id,
    required this.entryId,
    required this.encryptedPassword,
    required this.nonce,
    required this.mac,
    required this.recordedAt,
  });

  factory BackupHistoryItem.fromRow(Map<String, Object?> row) {
    return BackupHistoryItem(
      id: _readRequiredInt(row, 'id'),
      entryId: _readRequiredString(row, 'entry_id'),
      encryptedPassword: _readRequiredString(row, 'encrypted_password'),
      nonce: _readRequiredString(row, 'password_nonce'),
      mac: _readRequiredString(row, 'password_mac'),
      recordedAt: _readRequiredInt(row, 'recorded_at'),
    );
  }

  final int id;
  final String entryId;
  final String encryptedPassword;
  final String nonce;
  final String mac;
  final int recordedAt;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'entry_id': entryId,
      'encrypted_password': encryptedPassword,
      'password_nonce': nonce,
      'password_mac': mac,
      'recorded_at': recordedAt,
    };
  }

  factory BackupHistoryItem.fromJson(Map<String, Object?> json) {
    return BackupHistoryItem(
      id: _readRequiredInt(json, 'id'),
      entryId: _readRequiredString(json, 'entry_id'),
      encryptedPassword: _readRequiredString(json, 'encrypted_password'),
      nonce: _readRequiredString(json, 'password_nonce'),
      mac: _readRequiredString(json, 'password_mac'),
      recordedAt: _readRequiredInt(json, 'recorded_at'),
    );
  }
}

class BackupManifest {
  const BackupManifest({
    required this.version,
    required this.epoch,
    required this.counter,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.updatedAt,
  });

  factory BackupManifest.fromVaultManifest(VaultManifest manifest) {
    return BackupManifest(
      version: manifest.version,
      epoch: manifest.epoch,
      counter: manifest.counter,
      nonce: manifest.nonce,
      ciphertext: manifest.ciphertext,
      mac: manifest.mac,
      updatedAt: manifest.updatedAt,
    );
  }

  final int version;
  final int epoch;
  final int counter;
  final String nonce;
  final String ciphertext;
  final String mac;
  final int updatedAt;

  Map<String, Object?> toJson() {
    return {
      'version': version,
      'epoch': epoch,
      'counter': counter,
      'nonce': nonce,
      'ciphertext': ciphertext,
      'mac': mac,
      'updated_at': updatedAt,
    };
  }

  VaultManifest toVaultManifest() {
    return VaultManifest(
      version: version,
      epoch: epoch,
      counter: counter,
      nonce: nonce,
      ciphertext: ciphertext,
      mac: mac,
      updatedAt: updatedAt,
    );
  }

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    return BackupManifest(
      version: _readRequiredInt(json, 'version'),
      epoch: _readRequiredInt(json, 'epoch'),
      counter: _readRequiredInt(json, 'counter'),
      nonce: _readRequiredString(json, 'nonce'),
      ciphertext: _readRequiredString(json, 'ciphertext'),
      mac: _readRequiredString(json, 'mac'),
      updatedAt: _readRequiredInt(json, 'updated_at'),
    );
  }
}

class VaultBackup {
  VaultBackup({
    required this.version,
    this.magic,
    this.createdAt,
    this.scope,
    this.itemCount,
    this.historyCount,
    this.blobCount,
    this.vaultId,
    this.vaultCreatedAt,
    this.vaultUpdatedAt,
    this.biometricEnabled,
    this.encryptedDekByBiometric,
    this.encryptedDekByBiometricNonce,
    this.encryptedDekByBiometricMac,
    this.manifest,
    required this.kdf,
    required Map<String, Object?> kdfParams,
    required this.salt,
    required this.encryptedDekByMaster,
    required this.encryptedDekByMasterNonce,
    required this.encryptedDekByMasterMac,
    required List<BackupItem> items,
    List<BackupBlob> blobs = const [],
    List<BackupHistoryItem> historyItems = const [],
  }) : kdfParams = UnmodifiableMapView(Map<String, Object?>.from(kdfParams)),
       items = List.unmodifiable(items),
       blobs = List.unmodifiable(blobs),
       historyItems = List.unmodifiable(historyItems) {
    if (version != _legacyBackupVersion && version != _currentBackupVersion) {
      throw BackupFormatException('Unsupported backup version: $version');
    }
    _parseKdfParams(kdf: kdf, rawParams: this.kdfParams);
    _validateImportedItems(this.items);
    _validateImportedBlobs(this.blobs);
    _validateImportedHistoryItems(this.historyItems);
    if (version == _currentBackupVersion) {
      if (magic != _backupMagic ||
          createdAt == null ||
          (scope != _backupScopeFull &&
              scope != _backupScopeItem &&
              scope != _backupScopeSelected) ||
          itemCount != this.items.length ||
          historyCount != this.historyItems.length ||
          (blobCount ?? this.blobs.length) != this.blobs.length ||
          vaultId == null ||
          vaultCreatedAt == null ||
          vaultUpdatedAt == null ||
          biometricEnabled == null ||
          manifest == null ||
          this.items.any(
            (item) => item.createdAt == null || item.updatedAt == null,
          )) {
        throw const BackupFormatException('Invalid backup format');
      }
    }
  }

  final int version;
  final String? magic;
  final int? createdAt;
  final String? scope;
  final int? itemCount;
  final int? historyCount;
  final int? blobCount;
  final String? vaultId;
  final int? vaultCreatedAt;
  final int? vaultUpdatedAt;
  final bool? biometricEnabled;
  final String? encryptedDekByBiometric;
  final String? encryptedDekByBiometricNonce;
  final String? encryptedDekByBiometricMac;
  final BackupManifest? manifest;
  final String kdf;
  final Map<String, Object?> kdfParams;
  final String salt;
  final String encryptedDekByMaster;
  final String encryptedDekByMasterNonce;
  final String encryptedDekByMasterMac;
  final List<BackupItem> items;
  final List<BackupBlob> blobs;
  final List<BackupHistoryItem> historyItems;

  Map<String, Object?> toJson() {
    return {
      'version': version,
      if (version == _currentBackupVersion) ...{
        'magic': magic,
        'created_at': createdAt,
        'scope': scope,
        'item_count': itemCount,
        'history_count': historyCount,
        'blob_count': blobCount ?? blobs.length,
        'vault_id': vaultId,
        'vault_created_at': vaultCreatedAt,
        'vault_updated_at': vaultUpdatedAt,
        'biometric_enabled': biometricEnabled,
        'encrypted_dek_by_biometric': encryptedDekByBiometric,
        'encrypted_dek_by_biometric_nonce': encryptedDekByBiometricNonce,
        'encrypted_dek_by_biometric_mac': encryptedDekByBiometricMac,
        'manifest': manifest!.toJson(),
      },
      'kdf': kdf,
      'kdf_params': Map<String, Object?>.from(kdfParams),
      'salt': salt,
      'encrypted_dek_by_master': encryptedDekByMaster,
      'encrypted_dek_by_master_nonce': encryptedDekByMasterNonce,
      'encrypted_dek_by_master_mac': encryptedDekByMasterMac,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      if (version == _currentBackupVersion)
        'blobs': blobs.map((blob) => blob.toJson()).toList(growable: false),
      if (version == _currentBackupVersion)
        'history': historyItems
            .map((item) => item.toJson())
            .toList(growable: false),
    };
  }

  factory VaultBackup.fromJson(Map<String, Object?> json) {
    final version = _readRequiredInt(json, 'version');
    if (version != _legacyBackupVersion && version != _currentBackupVersion) {
      throw BackupFormatException('Unsupported backup version: $version');
    }

    final rawKdfParams = json['kdf_params'];
    if (rawKdfParams is! Map<Object?, Object?>) {
      throw const BackupFormatException(
        'Invalid "kdf_params": expected an object',
      );
    }

    final rawItems = json['items'];
    if (rawItems is! List<Object?>) {
      throw const BackupFormatException('Invalid "items": expected a list');
    }

    BackupManifest? manifest;
    var blobs = const <BackupBlob>[];
    var historyItems = const <BackupHistoryItem>[];
    if (version == _currentBackupVersion) {
      final rawManifest = json['manifest'];
      if (rawManifest is! Map<Object?, Object?>) {
        throw const BackupFormatException('Invalid backup format');
      }
      manifest = BackupManifest.fromJson(
        Map<String, Object?>.from(rawManifest),
      );
      final rawBlobs = json['blobs'];
      if (rawBlobs != null) {
        if (rawBlobs is! List<Object?>) {
          throw const BackupFormatException('Invalid "blobs": expected a list');
        }
        blobs = rawBlobs
            .map((item) {
              if (item is! Map<Object?, Object?>) {
                throw const BackupFormatException(
                  'Invalid backup blob: expected an object',
                );
              }
              return BackupBlob.fromJson(Map<String, Object?>.from(item));
            })
            .toList(growable: false);
      }
      final rawHistory = json['history'];
      if (rawHistory != null) {
        if (rawHistory is! List<Object?>) {
          throw const BackupFormatException(
            'Invalid "history": expected a list',
          );
        }
        historyItems = rawHistory
            .map((item) {
              if (item is! Map<Object?, Object?>) {
                throw const BackupFormatException(
                  'Invalid backup history item: expected an object',
                );
              }
              return BackupHistoryItem.fromJson(
                Map<String, Object?>.from(item),
              );
            })
            .toList(growable: false);
      }
    }

    return VaultBackup(
      version: version,
      magic: version == _currentBackupVersion
          ? _readRequiredString(json, 'magic')
          : null,
      createdAt: version == _currentBackupVersion
          ? _readRequiredInt(json, 'created_at')
          : null,
      scope: version == _currentBackupVersion
          ? _readOptionalString(json, 'scope') ?? _backupScopeFull
          : null,
      itemCount: version == _currentBackupVersion
          ? _readRequiredInt(json, 'item_count')
          : null,
      historyCount: version == _currentBackupVersion
          ? _readOptionalInt(json, 'history_count') ?? historyItems.length
          : null,
      blobCount: version == _currentBackupVersion
          ? _readOptionalInt(json, 'blob_count') ?? blobs.length
          : null,
      vaultId: version == _currentBackupVersion
          ? _readRequiredString(json, 'vault_id')
          : null,
      vaultCreatedAt: version == _currentBackupVersion
          ? _readRequiredInt(json, 'vault_created_at')
          : null,
      vaultUpdatedAt: version == _currentBackupVersion
          ? _readRequiredInt(json, 'vault_updated_at')
          : null,
      biometricEnabled: version == _currentBackupVersion
          ? _readRequiredBool(json, 'biometric_enabled')
          : null,
      encryptedDekByBiometric: version == _currentBackupVersion
          ? _readOptionalString(json, 'encrypted_dek_by_biometric')
          : null,
      encryptedDekByBiometricNonce: version == _currentBackupVersion
          ? _readOptionalString(json, 'encrypted_dek_by_biometric_nonce')
          : null,
      encryptedDekByBiometricMac: version == _currentBackupVersion
          ? _readOptionalString(json, 'encrypted_dek_by_biometric_mac')
          : null,
      manifest: manifest,
      kdf: _readRequiredString(json, 'kdf'),
      kdfParams: Map<String, Object?>.from(rawKdfParams),
      salt: _readRequiredString(json, 'salt'),
      encryptedDekByMaster: _readRequiredString(
        json,
        'encrypted_dek_by_master',
      ),
      encryptedDekByMasterNonce: _readRequiredString(
        json,
        'encrypted_dek_by_master_nonce',
      ),
      encryptedDekByMasterMac: _readRequiredString(
        json,
        'encrypted_dek_by_master_mac',
      ),
      items: rawItems
          .map((item) {
            if (item is! Map<Object?, Object?>) {
              throw const BackupFormatException(
                'Invalid backup item: expected an object',
              );
            }
            return BackupItem.fromJson(Map<String, Object?>.from(item));
          })
          .toList(growable: false),
      blobs: blobs,
      historyItems: historyItems,
    );
  }

  KdfParams get parsedKdfParams =>
      _parseKdfParams(kdf: kdf, rawParams: kdfParams);
}

void _validateImportedHistoryItems(List<BackupHistoryItem> items) {
  if (items.length > _maximumImportedItems * 5) {
    throw BackupFormatException(
      'Invalid "history": exceeds ${_maximumImportedItems * 5} entries',
    );
  }
  for (final item in items) {
    _validateImportedStringField('history.entry_id', item.entryId);
    _validateImportedStringField(
      'history.encrypted_password',
      item.encryptedPassword,
    );
    _validateImportedStringField('history.password_nonce', item.nonce);
    _validateImportedStringField('history.password_mac', item.mac);
  }
}

void _validateImportedItems(List<BackupItem> items) {
  if (items.length > _maximumImportedItems) {
    throw BackupFormatException(
      'Invalid "items": exceeds $_maximumImportedItems entries',
    );
  }
  for (final item in items) {
    _validateImportedStringField('items.id', item.id);
    _validateImportedStringField('items.nonce', item.nonce);
    _validateImportedStringField('items.ciphertext', item.ciphertext);
    _validateImportedStringField('items.mac', item.mac);
  }
}

void _validateImportedBlobs(List<BackupBlob> blobs) {
  if (blobs.length > _maximumImportedItems * 10) {
    throw BackupFormatException(
      'Invalid "blobs": exceeds ${_maximumImportedItems * 10} entries',
    );
  }
  for (final blob in blobs) {
    _validateImportedStringField('blobs.blob_id', blob.blobId);
    _validateImportedStringField('blobs.item_id', blob.itemId);
    _validateImportedStringField('blobs.metadata_nonce', blob.metadataNonce);
    _validateImportedStringField(
      'blobs.metadata_ciphertext',
      blob.metadataCiphertext,
    );
    _validateImportedStringField('blobs.metadata_mac', blob.metadataMac);
    _validateImportedStringField('blobs.nonce', blob.nonce);
    _validateImportedStringField('blobs.ciphertext', blob.ciphertext);
    _validateImportedStringField('blobs.mac', blob.mac);
  }
}

void _validateImportedStringField(String field, String value) {
  if (value.length > _maximumImportedFieldLength) {
    throw BackupFormatException(
      'Invalid "$field": exceeds $_maximumImportedFieldLength characters',
    );
  }
}

enum BackupImportMode { overwrite, skip, merge }

enum BackupImportConflictReason { existingLocalEntry, duplicateIncomingEntry }

class BackupImportConflict {
  const BackupImportConflict({
    required this.itemId,
    required this.title,
    required this.website,
    required this.username,
    required this.reason,
  });

  final String itemId;
  final String title;
  final String website;
  final String username;
  final BackupImportConflictReason reason;
}

class ConflictAwareBackupImportResult {
  const ConflictAwareBackupImportResult({
    required this.importedCount,
    required this.skippedCount,
    required this.conflicts,
  });

  final int importedCount;
  final int skippedCount;
  final List<BackupImportConflict> conflicts;
}

String backupIdentityConflictKey({
  required String title,
  required String website,
  required String username,
}) {
  return [
    _normalizeIdentityField(title),
    _normalizeWebsiteIdentityField(website),
    _normalizeIdentityField(username),
  ].join('\u001f');
}

String _normalizeIdentityField(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

String _normalizeWebsiteIdentityField(String value) {
  var normalized = _normalizeIdentityField(value);
  if (normalized.startsWith('http://')) {
    normalized = normalized.substring('http://'.length);
  } else if (normalized.startsWith('https://')) {
    normalized = normalized.substring('https://'.length);
  }
  if (normalized.startsWith('www.')) {
    normalized = normalized.substring('www.'.length);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

class BackupService {
  BackupService({
    required this.repository,
    required this.vaultService,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final VaultRepository repository;
  final VaultService vaultService;
  final Uuid _uuid;

  Future<VaultBackup> exportBackup() async {
    final meta = await repository.metaDao.get();
    if (meta == null) {
      throw StateError('Vault has not been created');
    }

    final items = await repository.itemsDao.activeItems();
    final activeIds = items.map((item) => item.id).toSet();
    final blobs = (await repository.blobsDao.allForManifest())
        .where(
          (blob) => blob.deletedAt == null && activeIds.contains(blob.itemId),
        )
        .toList(growable: false);
    final historyItems =
        (await repository.historyDao?.allRowsForManifest())
            ?.where((row) => activeIds.contains(row['entry_id']))
            .map((row) => BackupHistoryItem.fromRow(row))
            .toList(growable: false) ??
        const <BackupHistoryItem>[];
    return _buildBackup(
      meta: meta,
      items: items,
      blobs: blobs,
      historyItems: historyItems,
      scope: _backupScopeFull,
    );
  }

  Future<VaultBackup> exportItemBackup(String itemId) async {
    final meta = await repository.metaDao.get();
    if (meta == null) {
      throw StateError('Vault has not been created');
    }

    final item = await repository.itemsDao.byId(itemId);
    if (item == null || item.deletedAt != null) {
      throw VaultItemNotFoundException(itemId);
    }

    final historyItems =
        (await repository.historyDao?.allRowsForManifest())
            ?.where((row) => row['entry_id'] == itemId)
            .map((row) => BackupHistoryItem.fromRow(row))
            .toList(growable: false) ??
        const <BackupHistoryItem>[];
    final blobs = await repository.blobsDao.activeByItem(itemId);
    return _buildBackup(
      meta: meta,
      items: [item],
      blobs: blobs,
      historyItems: historyItems,
      scope: _backupScopeItem,
    );
  }

  Future<VaultBackup> exportSelectedItemsBackup({
    required List<String> itemIds,
    bool includeBlobs = true,
    bool includeHistory = false,
  }) async {
    if (itemIds.isEmpty) {
      throw ArgumentError.value(
        itemIds,
        'itemIds',
        'At least one item must be selected',
      );
    }
    final meta = await repository.metaDao.get();
    if (meta == null) {
      throw StateError('Vault has not been created');
    }

    final selectedIds = LinkedHashSet<String>.from(itemIds).toList();
    final items = <EncryptedVaultItem>[];
    for (final itemId in selectedIds) {
      final item = await repository.itemsDao.byId(itemId);
      if (item == null || item.deletedAt != null) {
        throw VaultItemNotFoundException(itemId);
      }
      items.add(item);
    }
    final selectedIdSet = selectedIds.toSet();
    final blobs = includeBlobs
        ? (await repository.blobsDao.allForManifest())
              .where(
                (blob) =>
                    blob.deletedAt == null &&
                    selectedIdSet.contains(blob.itemId),
              )
              .toList(growable: false)
        : const <EncryptedVaultBlob>[];
    final historyItems = includeHistory
        ? (await repository.historyDao?.allRowsForManifest())
                  ?.where((row) => selectedIdSet.contains(row['entry_id']))
                  .map((row) => BackupHistoryItem.fromRow(row))
                  .toList(growable: false) ??
              const <BackupHistoryItem>[]
        : const <BackupHistoryItem>[];

    return _buildBackup(
      meta: meta,
      items: items,
      blobs: blobs,
      historyItems: historyItems,
      scope: _backupScopeSelected,
    );
  }

  /// Creates a LAN-only selected export using a fresh transfer DEK.
  ///
  /// The source vault DEK and its persisted wrapping material are never
  /// serialized; selected data is re-encrypted under the transfer DEK, which is
  /// wrapped with a one-time LAN package password for the receiver. The source
  /// master password is used only to reauthenticate this local export.
  Future<VaultBackup> exportLanTransferBackup({
    required List<String> itemIds,
    bool includeBlobs = true,
    bool includeHistory = false,
    required String sourceMasterPassword,
    required String lanPackagePassword,
  }) async {
    if (itemIds.isEmpty) {
      throw ArgumentError.value(
        itemIds,
        'itemIds',
        'At least one item must be selected',
      );
    }
    if (await repository.metaDao.get() == null) {
      throw StateError('Vault has not been created');
    }

    final selectedIds = LinkedHashSet<String>.from(itemIds).toList();
    final items = <EncryptedVaultItem>[];
    for (final itemId in selectedIds) {
      final item = await repository.itemsDao.byId(itemId);
      if (item == null || item.deletedAt != null) {
        throw VaultItemNotFoundException(itemId);
      }
      items.add(item);
    }
    final selectedIdSet = selectedIds.toSet();
    final blobs = includeBlobs
        ? (await repository.blobsDao.allForManifest())
              .where(
                (blob) =>
                    blob.deletedAt == null &&
                    selectedIdSet.contains(blob.itemId),
              )
              .toList(growable: false)
        : const <EncryptedVaultBlob>[];
    final historyItems = includeHistory
        ? (await repository.historyDao?.allRowsForManifest())
                  ?.where((row) => selectedIdSet.contains(row['entry_id']))
                  .map((row) => BackupHistoryItem.fromRow(row))
                  .toList(growable: false) ??
              const <BackupHistoryItem>[]
        : const <BackupHistoryItem>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    final export = await vaultService.createPasswordWrappedExport(
      exportPassword: lanPackagePassword,
      verificationPassword: sourceMasterPassword,
      items: items,
      blobs: blobs,
      historyRecords: historyItems
          .map((item) => item.toJson())
          .toList(growable: false),
      exportVaultId: _uuid.v4(),
      createdAt: now,
      updatedAt: now,
    );
    return _buildBackupFromPasswordWrappedExport(
      export: export,
      scope: _backupScopeSelected,
    );
  }

  Future<VaultBackup> _buildBackup({
    required VaultMeta meta,
    required List<EncryptedVaultItem> items,
    required List<EncryptedVaultBlob> blobs,
    required List<BackupHistoryItem> historyItems,
    required String scope,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final manifest = await vaultService.createVerifiedManifestForBackup(
      items: items,
      blobs: blobs,
      historyRecords: historyItems.map((item) => item.toJson()).toList(),
      updatedAt: now,
    );
    return VaultBackup(
      version: _currentBackupVersion,
      magic: _backupMagic,
      createdAt: now,
      scope: scope,
      itemCount: items.length,
      historyCount: historyItems.length,
      blobCount: blobs.length,
      vaultId: meta.id,
      vaultCreatedAt: meta.createdAt,
      vaultUpdatedAt: meta.updatedAt,
      biometricEnabled: meta.biometricEnabled,
      encryptedDekByBiometric: meta.encryptedDekByBiometric,
      encryptedDekByBiometricNonce: meta.encryptedDekByBiometricNonce,
      encryptedDekByBiometricMac: meta.encryptedDekByBiometricMac,
      manifest: BackupManifest.fromVaultManifest(manifest),
      kdf: meta.kdf,
      kdfParams: meta.kdfParams.toJson(),
      salt: meta.salt,
      encryptedDekByMaster: meta.encryptedDekByMaster,
      encryptedDekByMasterNonce: meta.encryptedDekByMasterNonce,
      encryptedDekByMasterMac: meta.encryptedDekByMasterMac,
      historyItems: historyItems,
      blobs: blobs
          .map(
            (blob) => BackupBlob(
              blobId: blob.blobId,
              itemId: blob.itemId,
              metadataNonce: blob.metadataNonce,
              metadataCiphertext: blob.metadataCiphertext,
              metadataMac: blob.metadataMac,
              nonce: blob.nonce,
              ciphertext: blob.ciphertext,
              mac: blob.mac,
              createdAt: blob.createdAt,
              updatedAt: blob.updatedAt,
              deletedAt: blob.deletedAt,
            ),
          )
          .toList(growable: false),
      items: items
          .map(
            (item) => BackupItem(
              id: item.id,
              nonce: item.nonce,
              ciphertext: item.ciphertext,
              mac: item.mac,
              createdAt: item.createdAt,
              updatedAt: item.updatedAt,
              deletedAt: item.deletedAt,
            ),
          )
          .toList(growable: false),
    );
  }

  VaultBackup _buildBackupFromPasswordWrappedExport({
    required PasswordWrappedVaultExport export,
    required String scope,
  }) {
    return VaultBackup(
      version: _currentBackupVersion,
      magic: _backupMagic,
      createdAt: export.meta.updatedAt,
      scope: scope,
      itemCount: export.items.length,
      historyCount: export.historyRecords.length,
      blobCount: export.blobs.length,
      vaultId: export.meta.id,
      vaultCreatedAt: export.meta.createdAt,
      vaultUpdatedAt: export.meta.updatedAt,
      biometricEnabled: false,
      encryptedDekByBiometric: null,
      encryptedDekByBiometricNonce: null,
      encryptedDekByBiometricMac: null,
      manifest: BackupManifest.fromVaultManifest(export.manifest),
      kdf: export.meta.kdf,
      kdfParams: export.meta.kdfParams.toJson(),
      salt: export.meta.salt,
      encryptedDekByMaster: export.meta.encryptedDekByMaster,
      encryptedDekByMasterNonce: export.meta.encryptedDekByMasterNonce,
      encryptedDekByMasterMac: export.meta.encryptedDekByMasterMac,
      historyItems: export.historyRecords
          .map((row) => BackupHistoryItem.fromRow(row))
          .toList(growable: false),
      blobs: export.blobs
          .map(
            (blob) => BackupBlob(
              blobId: blob.blobId,
              itemId: blob.itemId,
              metadataNonce: blob.metadataNonce,
              metadataCiphertext: blob.metadataCiphertext,
              metadataMac: blob.metadataMac,
              nonce: blob.nonce,
              ciphertext: blob.ciphertext,
              mac: blob.mac,
              createdAt: blob.createdAt,
              updatedAt: blob.updatedAt,
              deletedAt: blob.deletedAt,
            ),
          )
          .toList(growable: false),
      items: export.items
          .map(
            (item) => BackupItem(
              id: item.id,
              nonce: item.nonce,
              ciphertext: item.ciphertext,
              mac: item.mac,
              createdAt: item.createdAt,
              updatedAt: item.updatedAt,
              deletedAt: item.deletedAt,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<int> importBackup({
    required Map<String, Object?> json,
    required String masterPassword,
    required BackupImportMode mode,
    bool allowLegacyBackups = false,
  }) async {
    final backup = VaultBackup.fromJson(json);
    if (backup.version == _legacyBackupVersion && !allowLegacyBackups) {
      throw const BackupFormatException(
        'Legacy version 1 backups are disabled by default because they do not include a vault manifest.',
      );
    }
    if (mode == BackupImportMode.overwrite &&
        backup.version == _currentBackupVersion &&
        (backup.scope == _backupScopeItem ||
            backup.scope == _backupScopeSelected)) {
      throw const BackupFormatException(
        'Item and selected backups cannot be imported with overwrite mode.',
      );
    }
    final backupMeta = _backupMetaForVerification(backup);
    await vaultService.verifyMasterPassword(
      masterPassword: masterPassword,
      meta: backupMeta,
    );
    if (backup.version == _currentBackupVersion) {
      await vaultService.verifyBackupManifest(
        masterPassword: masterPassword,
        meta: backupMeta,
        items: _manifestItemsFromBackup(backup.items),
        blobs: _manifestBlobsFromBackup(backup.blobs),
        historyRecords: _manifestHistoryFromBackup(backup.historyItems),
        manifest: backup.manifest!.toVaultManifest(),
      );
    }

    final result = await vaultService.runSerializedManifestCommit(() async {
      final transactionResult = await repository.transaction<_BackupImportResult>((
        txn,
      ) async {
        final existingMeta = await txn.metaDao.get();
        final existingManifest = await txn.manifestDao.get();
        final now = DateTime.now().millisecondsSinceEpoch;
        final hasExistingVault = existingMeta != null;
        final preserveExistingMeta =
            mode != BackupImportMode.overwrite && hasExistingVault;
        final needsReencryption =
            preserveExistingMeta &&
            !_hasSameEncryptionEnvelope(existingMeta, backupMeta);

        final importedMeta = _buildImportedMeta(
          backup: backup,
          existingMeta: existingMeta,
          preserveExistingId: preserveExistingMeta,
          now: now,
        );

        switch (mode) {
          case BackupImportMode.overwrite:
            if (hasExistingVault) {
              await _verifyExistingManifestBeforeImportMutation(
                txn: txn,
                masterPassword: masterPassword,
                meta: existingMeta,
                manifest: existingManifest,
              );
            }
            final importedItems = backup.items
                .map(
                  (item) => _buildImportedItem(
                    item,
                    createdAt: item.createdAt ?? now,
                    updatedAt: item.updatedAt ?? now,
                  ),
                )
                .toList(growable: false);
            final importedBlobs = backup.blobs
                .map(
                  (blob) => _buildImportedBlob(
                    blob,
                    createdAt: blob.createdAt,
                    updatedAt: blob.updatedAt,
                  ),
                )
                .toList(growable: false);
            final manifest = await vaultService.createManifestForImportedVault(
              masterPassword: masterPassword,
              meta: importedMeta,
              items: importedItems,
              blobs: importedBlobs,
              historyRecords: _manifestHistoryFromBackup(backup.historyItems),
              previous: null,
              updatedAt: now,
            );
            await vaultService.verifyManifestAgainstAnchor(
              meta: importedMeta,
              manifest: manifest,
              allowMissingAnchor: true,
              allowNewerManifest: true,
            );
            await txn.metaDao.save(importedMeta);
            await txn.historyDao?.deleteAll();
            await txn.blobsDao.deleteAll();
            await txn.itemsDao.deleteAll();
            for (final importedItem in importedItems) {
              await txn.itemsDao.upsert(importedItem);
            }
            for (final importedBlob in importedBlobs) {
              await txn.blobsDao.upsert(importedBlob);
            }
            for (final historyItem in backup.historyItems) {
              await txn.historyDao?.insertRaw(historyItem.toJson());
            }
            await vaultService.stagePendingAnchorForImportedManifest(
              repository: txn,
              meta: importedMeta,
              manifest: manifest,
            );
            await txn.manifestDao.save(manifest);
            vaultService.lock();
            return _BackupImportResult(
              importedCount: backup.items.length,
              dataChanged: true,
              meta: importedMeta,
              manifest: manifest,
            );
          case BackupImportMode.skip:
            if (!preserveExistingMeta) {
              await txn.metaDao.save(importedMeta);
            }
            final pendingItems = <EncryptedVaultItem>[];
            for (final item in backup.items) {
              final existingItem = await txn.itemsDao.byId(item.id);
              if (existingItem != null) {
                continue;
              }
              pendingItems.add(
                _buildImportedItem(
                  item,
                  createdAt: existingItem?.createdAt ?? item.createdAt ?? now,
                  updatedAt: item.updatedAt ?? now,
                ),
              );
            }
            final pendingItemIds = pendingItems.map((item) => item.id).toSet();
            final existingActiveItemIds =
                (await txn.itemsDao.allItemsForManifest())
                    .where((item) => item.deletedAt == null)
                    .map((item) => item.id)
                    .toSet();
            final importableBlobItemIds = {
              ...existingActiveItemIds,
              ...pendingItemIds,
            };
            final pendingBlobs = <EncryptedVaultBlob>[];
            for (final blob in backup.blobs) {
              if (!importableBlobItemIds.contains(blob.itemId)) {
                continue;
              }
              final existingBlob = await txn.blobsDao.byBlobId(blob.blobId);
              if (existingBlob != null) {
                continue;
              }
              pendingBlobs.add(
                _buildImportedBlob(
                  blob,
                  createdAt: blob.createdAt,
                  updatedAt: blob.updatedAt,
                ),
              );
            }
            final needsPendingReencryption =
                needsReencryption &&
                (pendingItems.isNotEmpty || pendingBlobs.isNotEmpty);
            if (needsPendingReencryption && !vaultService.isUnlocked) {
              throw StateError(
                'Skip and merge imports into an existing vault with a different encrypted DEK envelope must already be unlocked so imported items can be re-encrypted under the current vault key.',
              );
            }
            if (preserveExistingMeta) {
              if (pendingItems.isNotEmpty) {
                await _verifyExistingManifestBeforeImportMutation(
                  txn: txn,
                  masterPassword: masterPassword,
                  meta: existingMeta,
                  manifest: existingManifest,
                );
              } else {
                if (vaultService.isUnlocked) {
                  await vaultService.verifyCurrentManifestForImport(txn: txn);
                } else if (needsReencryption) {
                  throw StateError(
                    'Skip imports into an existing vault with a different encrypted DEK envelope must already be unlocked so the current vault integrity can be verified.',
                  );
                } else {
                  await _verifyExistingManifestBeforeImportMutation(
                    txn: txn,
                    masterPassword: masterPassword,
                    meta: existingMeta,
                    manifest: existingManifest,
                  );
                }
              }
            }
            final itemsToInsert = await _prepareImportedItems(
              items: pendingItems,
              backupMeta: backupMeta,
              masterPassword: masterPassword,
              needsReencryption: needsPendingReencryption,
            );
            final blobsToInsert = await _prepareImportedBlobs(
              blobs: pendingBlobs,
              backupMeta: backupMeta,
              masterPassword: masterPassword,
              needsReencryption: needsPendingReencryption,
            );
            final historyToInsert = await _prepareImportedHistoryRows(
              historyItems: backup.historyItems,
              entryIds: itemsToInsert.map((item) => item.id).toSet(),
              backupMeta: backupMeta,
              masterPassword: masterPassword,
              needsReencryption: needsPendingReencryption,
            );
            for (final item in itemsToInsert) {
              await txn.itemsDao.upsert(item);
            }
            for (final blob in blobsToInsert) {
              await txn.blobsDao.upsert(blob);
            }
            for (final historyItem in historyToInsert) {
              await txn.historyDao?.insertRaw(
                historyItem,
                preserveId: !preserveExistingMeta,
              );
            }
            final manifest = await _rewriteManifestAfterImport(
              txn: txn,
              backup: backup,
              masterPassword: masterPassword,
              preserveExistingMeta: preserveExistingMeta,
              dataChanged:
                  itemsToInsert.isNotEmpty ||
                  blobsToInsert.isNotEmpty ||
                  historyToInsert.isNotEmpty,
              previous: existingManifest,
              updatedAt: now,
            );
            final targetMeta = await txn.metaDao.get();
            return _BackupImportResult(
              importedCount: itemsToInsert.length,
              dataChanged: manifest != null,
              meta: targetMeta,
              manifest: manifest,
            );
          case BackupImportMode.merge:
            if (!preserveExistingMeta) {
              await txn.metaDao.save(importedMeta);
            }
            final pendingItems = <EncryptedVaultItem>[];
            for (final item in backup.items) {
              final existingItem = await txn.itemsDao.byId(item.id);
              pendingItems.add(
                _buildImportedItem(
                  item,
                  createdAt: existingItem?.createdAt ?? item.createdAt ?? now,
                  updatedAt: item.updatedAt ?? now,
                ),
              );
            }
            final pendingBlobs = backup.blobs
                .map(
                  (blob) => _buildImportedBlob(
                    blob,
                    createdAt: blob.createdAt,
                    updatedAt: blob.updatedAt,
                  ),
                )
                .toList(growable: false);
            final needsPendingReencryption =
                needsReencryption &&
                (pendingItems.isNotEmpty || pendingBlobs.isNotEmpty);
            if (needsPendingReencryption && !vaultService.isUnlocked) {
              throw StateError(
                'Skip and merge imports into an existing vault with a different encrypted DEK envelope must already be unlocked so imported items can be re-encrypted under the current vault key.',
              );
            }
            if (preserveExistingMeta &&
                (pendingItems.isNotEmpty ||
                    pendingBlobs.isNotEmpty ||
                    backup.historyItems.isNotEmpty)) {
              await _verifyExistingManifestBeforeImportMutation(
                txn: txn,
                masterPassword: masterPassword,
                meta: existingMeta,
                manifest: existingManifest,
              );
            }
            final itemsToInsert = await _prepareImportedItems(
              items: pendingItems,
              backupMeta: backupMeta,
              masterPassword: masterPassword,
              needsReencryption: needsPendingReencryption,
            );
            final blobsToInsert = await _prepareImportedBlobs(
              blobs: pendingBlobs,
              backupMeta: backupMeta,
              masterPassword: masterPassword,
              needsReencryption: needsPendingReencryption,
            );
            final existingIds = <String>{};
            for (final item in backup.items) {
              final existingItem = await txn.itemsDao.byId(item.id);
              if (existingItem != null) {
                existingIds.add(item.id);
              }
            }
            final historyToInsert = await _prepareImportedHistoryRows(
              historyItems: backup.historyItems,
              entryIds: itemsToInsert
                  .map((item) => item.id)
                  .where((id) => !existingIds.contains(id))
                  .toSet(),
              backupMeta: backupMeta,
              masterPassword: masterPassword,
              needsReencryption: needsPendingReencryption,
            );
            for (final item in itemsToInsert) {
              await txn.itemsDao.upsert(item);
            }
            for (final blob in blobsToInsert) {
              await txn.blobsDao.upsert(blob);
            }
            for (final historyItem in historyToInsert) {
              await txn.historyDao?.insertRaw(
                historyItem,
                preserveId: !preserveExistingMeta,
              );
            }
            final manifest = await _rewriteManifestAfterImport(
              txn: txn,
              backup: backup,
              masterPassword: masterPassword,
              preserveExistingMeta: preserveExistingMeta,
              dataChanged:
                  itemsToInsert.isNotEmpty ||
                  blobsToInsert.isNotEmpty ||
                  historyToInsert.isNotEmpty,
              previous: existingManifest,
              updatedAt: now,
            );
            final targetMeta = await txn.metaDao.get();
            return _BackupImportResult(
              importedCount: backup.items.length,
              dataChanged: manifest != null,
              meta: targetMeta,
              manifest: manifest,
            );
        }
      });
      final targetMeta = transactionResult.meta;
      final targetManifest = transactionResult.manifest;
      if (transactionResult.dataChanged &&
          targetMeta != null &&
          targetManifest != null) {
        await vaultService.acceptManifestForCurrentStateDuringSerializedCommit(
          meta: targetMeta,
          manifest: targetManifest,
          pendingAnchorAlreadyStaged: true,
        );
      }
      return transactionResult;
    });
    return result.importedCount;
  }

  Future<ConflictAwareBackupImportResult>
  importBackupSkippingIdentityConflicts({
    required Map<String, Object?> json,
    required String masterPassword,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final backup = VaultBackup.fromJson(json);
    if (backup.version != _currentBackupVersion) {
      throw const BackupFormatException(
        'Conflict-aware imports require a version 2 backup manifest.',
      );
    }

    final existingMetaBeforeImport = await repository.metaDao.get();
    if (existingMetaBeforeImport == null) {
      throw StateError(
        'Conflict-aware imports require an existing target vault so imported rows can remain encrypted under the receiver vault key.',
      );
    }
    if (!vaultService.isUnlocked) {
      throw StateError(
        'Conflict-aware imports require an unlocked target vault so local identities can be checked safely.',
      );
    }

    final backupMeta = _backupMetaForVerification(backup);
    cancellationToken?.throwIfCancelled();
    await vaultService.verifyMasterPassword(
      masterPassword: masterPassword,
      meta: backupMeta,
    );
    cancellationToken?.throwIfCancelled();
    await vaultService.verifyBackupManifest(
      masterPassword: masterPassword,
      meta: backupMeta,
      items: _manifestItemsFromBackup(backup.items),
      blobs: _manifestBlobsFromBackup(backup.blobs),
      historyRecords: _manifestHistoryFromBackup(backup.historyItems),
      manifest: backup.manifest!.toVaultManifest(),
      cancellationToken: cancellationToken,
    );
    cancellationToken?.throwIfCancelled();

    final localKeys = <String>{};
    final localIdentities = await vaultService.listActiveItemIdentities();
    for (final item in localIdentities) {
      localKeys.add(
        backupIdentityConflictKey(
          title: item.title,
          website: item.website,
          username: item.username,
        ),
      );
    }

    final incomingIdentities = await vaultService
        .decryptImportedItemIdentitiesForBackupImport(
          items: _manifestItemsFromBackup(backup.items),
          sourceMeta: backupMeta,
          sourcePassword: masterPassword,
          cancellationToken: cancellationToken,
        );
    cancellationToken?.throwIfCancelled();

    final ambiguousIncomingItemIds = <String>{};
    final seenIncomingItemIds = <String>{};
    for (final item in backup.items) {
      if (!seenIncomingItemIds.add(item.id)) {
        ambiguousIncomingItemIds.add(item.id);
      }
    }

    final acceptedItemIndexes = <int>{};
    final duplicateKeys = <String>{};
    final seenItemIds = <String>{};
    final conflicts = <BackupImportConflict>[];
    for (final entry in incomingIdentities.asMap().entries) {
      final identity = entry.value;
      final key = backupIdentityConflictKey(
        title: identity.title,
        website: identity.website,
        username: identity.username,
      );
      BackupImportConflictReason? reason;
      if (localKeys.contains(key)) {
        reason = BackupImportConflictReason.existingLocalEntry;
      } else if (duplicateKeys.contains(key) ||
          seenItemIds.contains(identity.id)) {
        reason = BackupImportConflictReason.duplicateIncomingEntry;
      }

      if (reason != null) {
        conflicts.add(
          BackupImportConflict(
            itemId: identity.id,
            title: identity.title,
            website: identity.website,
            username: identity.username,
            reason: reason,
          ),
        );
        continue;
      }

      acceptedItemIndexes.add(entry.key);
      duplicateKeys.add(key);
      seenItemIds.add(identity.id);
    }

    final transactionResult = await vaultService.runSerializedManifestCommit(
      () async {
        final transactionResult = await repository
            .transaction<_ConflictAwareImportTransactionResult>((txn) async {
              cancellationToken?.throwIfCancelled();
              final existingMeta = await txn.metaDao.get();
              final existingManifest = await txn.manifestDao.get();
              final now = DateTime.now().millisecondsSinceEpoch;
              if (existingMeta == null) {
                throw StateError(
                  'Conflict-aware imports require an existing target vault.',
                );
              }
              final needsReencryption = !_hasSameEncryptionEnvelope(
                existingMeta,
                backupMeta,
              );
              if (needsReencryption && !vaultService.isUnlocked) {
                throw StateError(
                  'Conflict-aware imports into an existing vault with a different encrypted DEK envelope must already be unlocked so imported items can be re-encrypted under the current vault key.',
                );
              }

              await _verifyExistingManifestBeforeImportMutation(
                txn: txn,
                masterPassword: masterPassword,
                meta: existingMeta,
                manifest: existingManifest,
              );

              final existingIds = <String>{};
              for (final entry in backup.items.asMap().entries) {
                final index = entry.key;
                final item = entry.value;
                if (!acceptedItemIndexes.contains(index)) {
                  continue;
                }
                final existingItem = await txn.itemsDao.byId(item.id);
                if (existingItem != null) {
                  acceptedItemIndexes.remove(index);
                  existingIds.add(item.id);
                  final identity = incomingIdentities[index];
                  conflicts.add(
                    BackupImportConflict(
                      itemId: identity.id,
                      title: identity.title,
                      website: identity.website,
                      username: identity.username,
                      reason: BackupImportConflictReason.existingLocalEntry,
                    ),
                  );
                }
              }

              final pendingItems = <EncryptedVaultItem>[];
              for (final entry in backup.items.asMap().entries) {
                if (!acceptedItemIndexes.contains(entry.key)) {
                  continue;
                }
                final item = entry.value;
                pendingItems.add(
                  _buildImportedItem(
                    item,
                    createdAt: item.createdAt ?? now,
                    updatedAt: item.updatedAt ?? now,
                  ),
                );
              }
              final pendingItemIds = pendingItems
                  .map((item) => item.id)
                  .toSet();
              final pendingChildItemIds = pendingItemIds.difference(
                ambiguousIncomingItemIds,
              );
              final pendingBlobs = backup.blobs
                  .where((blob) => pendingChildItemIds.contains(blob.itemId))
                  .map(
                    (blob) => _buildImportedBlob(
                      blob,
                      createdAt: blob.createdAt,
                      updatedAt: blob.updatedAt,
                    ),
                  )
                  .toList(growable: false);
              final pendingBlobIds = <String>{};
              final uniquePendingBlobs = <EncryptedVaultBlob>[];
              for (final blob in pendingBlobs) {
                if (!pendingBlobIds.add(blob.blobId)) {
                  continue;
                }
                if ((await txn.blobsDao.byBlobId(blob.blobId)) != null) {
                  continue;
                }
                uniquePendingBlobs.add(blob);
              }

              final needsPendingReencryption =
                  needsReencryption &&
                  (pendingItems.isNotEmpty || uniquePendingBlobs.isNotEmpty);
              final itemsToInsert = await _prepareImportedItems(
                items: pendingItems,
                backupMeta: backupMeta,
                masterPassword: masterPassword,
                needsReencryption: needsPendingReencryption,
                cancellationToken: cancellationToken,
              );
              cancellationToken?.throwIfCancelled();
              final blobsToInsert = await _prepareImportedBlobs(
                blobs: uniquePendingBlobs,
                backupMeta: backupMeta,
                masterPassword: masterPassword,
                needsReencryption: needsPendingReencryption,
                cancellationToken: cancellationToken,
              );
              cancellationToken?.throwIfCancelled();
              final historyToInsert = await _prepareImportedHistoryRows(
                historyItems: backup.historyItems,
                entryIds: pendingChildItemIds.difference(existingIds),
                backupMeta: backupMeta,
                masterPassword: masterPassword,
                needsReencryption: needsPendingReencryption,
                cancellationToken: cancellationToken,
              );
              cancellationToken?.throwIfCancelled();

              for (final item in itemsToInsert) {
                cancellationToken?.throwIfCancelled();
                await txn.itemsDao.upsert(item);
              }
              for (final blob in blobsToInsert) {
                cancellationToken?.throwIfCancelled();
                await txn.blobsDao.upsert(blob);
              }
              for (final historyItem in historyToInsert) {
                cancellationToken?.throwIfCancelled();
                await txn.historyDao?.insertRaw(historyItem, preserveId: false);
              }

              final manifest = await _rewriteManifestAfterImport(
                txn: txn,
                backup: backup,
                masterPassword: masterPassword,
                preserveExistingMeta: true,
                dataChanged:
                    itemsToInsert.isNotEmpty ||
                    blobsToInsert.isNotEmpty ||
                    historyToInsert.isNotEmpty,
                previous: existingManifest,
                updatedAt: now,
              );
              cancellationToken?.throwIfCancelled();
              final targetMeta = await txn.metaDao.get();
              return _ConflictAwareImportTransactionResult(
                result: ConflictAwareBackupImportResult(
                  importedCount: itemsToInsert.length,
                  skippedCount: conflicts.length,
                  conflicts: List.unmodifiable(conflicts),
                ),
                dataChanged: manifest != null,
                meta: targetMeta,
                manifest: manifest,
              );
            });

        final targetMeta = transactionResult.meta;
        final targetManifest = transactionResult.manifest;
        if (transactionResult.dataChanged &&
            targetMeta != null &&
            targetManifest != null) {
          await vaultService
              .acceptManifestForCurrentStateDuringSerializedCommit(
                meta: targetMeta,
                manifest: targetManifest,
                pendingAnchorAlreadyStaged: true,
              );
        }
        return transactionResult;
      },
    );
    return transactionResult.result;
  }

  VaultMeta _backupMetaForVerification(VaultBackup backup) {
    return VaultMeta(
      id: backup.vaultId ?? 'backup-verification',
      version: 1,
      kdf: backup.kdf,
      kdfParams: backup.parsedKdfParams,
      salt: backup.salt,
      encryptedDekByMaster: backup.encryptedDekByMaster,
      encryptedDekByMasterNonce: backup.encryptedDekByMasterNonce,
      encryptedDekByMasterMac: backup.encryptedDekByMasterMac,
      biometricEnabled: backup.biometricEnabled ?? false,
      createdAt: backup.vaultCreatedAt ?? 0,
      updatedAt: backup.vaultUpdatedAt ?? 0,
      encryptedDekByBiometric: backup.encryptedDekByBiometric,
      encryptedDekByBiometricNonce: backup.encryptedDekByBiometricNonce,
      encryptedDekByBiometricMac: backup.encryptedDekByBiometricMac,
    );
  }

  VaultMeta _buildImportedMeta({
    required VaultBackup backup,
    required VaultMeta? existingMeta,
    required bool preserveExistingId,
    required int now,
  }) {
    return VaultMeta(
      id: preserveExistingId ? existingMeta!.id : backup.vaultId ?? _uuid.v4(),
      version: 1,
      kdf: backup.kdf,
      kdfParams: backup.parsedKdfParams,
      salt: backup.salt,
      encryptedDekByMaster: backup.encryptedDekByMaster,
      encryptedDekByMasterNonce: backup.encryptedDekByMasterNonce,
      encryptedDekByMasterMac: backup.encryptedDekByMasterMac,
      biometricEnabled: false,
      createdAt: preserveExistingId
          ? existingMeta!.createdAt
          : backup.vaultCreatedAt ?? now,
      updatedAt: preserveExistingId ? now : backup.vaultUpdatedAt ?? now,
      encryptedDekByBiometric: null,
      encryptedDekByBiometricNonce: null,
      encryptedDekByBiometricMac: null,
    );
  }

  EncryptedVaultItem _buildImportedItem(
    BackupItem item, {
    required int createdAt,
    required int updatedAt,
  }) {
    return EncryptedVaultItem(
      id: item.id,
      nonce: item.nonce,
      ciphertext: item.ciphertext,
      mac: item.mac,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: item.deletedAt,
    );
  }

  EncryptedVaultBlob _buildImportedBlob(
    BackupBlob blob, {
    required int createdAt,
    required int updatedAt,
  }) {
    return EncryptedVaultBlob(
      blobId: blob.blobId,
      itemId: blob.itemId,
      metadataNonce: blob.metadataNonce,
      metadataCiphertext: blob.metadataCiphertext,
      metadataMac: blob.metadataMac,
      nonce: blob.nonce,
      ciphertext: blob.ciphertext,
      mac: blob.mac,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: blob.deletedAt,
    );
  }

  Future<List<EncryptedVaultItem>> _prepareImportedItems({
    required List<EncryptedVaultItem> items,
    required VaultMeta backupMeta,
    required String masterPassword,
    required bool needsReencryption,
    CancellationToken? cancellationToken,
  }) async {
    if (!needsReencryption || items.isEmpty) {
      return items;
    }

    return vaultService.reencryptItemsForCurrentVault(
      items: items,
      sourceMeta: backupMeta,
      sourcePassword: masterPassword,
      cancellationToken: cancellationToken,
    );
  }

  Future<List<Map<String, Object?>>> _prepareImportedHistoryRows({
    required List<BackupHistoryItem> historyItems,
    required Set<String> entryIds,
    required VaultMeta backupMeta,
    required String masterPassword,
    required bool needsReencryption,
    CancellationToken? cancellationToken,
  }) async {
    if (historyItems.isEmpty || entryIds.isEmpty) {
      return const [];
    }
    final rows = historyItems
        .where((item) => entryIds.contains(item.entryId))
        .map((item) => Map<String, Object?>.from(item.toJson()))
        .toList(growable: false);
    if (!needsReencryption || rows.isEmpty) {
      return rows;
    }

    return vaultService.reencryptHistoryForCurrentVault(
      records: rows,
      sourceMeta: backupMeta,
      sourcePassword: masterPassword,
      cancellationToken: cancellationToken,
    );
  }

  Future<List<EncryptedVaultBlob>> _prepareImportedBlobs({
    required List<EncryptedVaultBlob> blobs,
    required VaultMeta backupMeta,
    required String masterPassword,
    required bool needsReencryption,
    CancellationToken? cancellationToken,
  }) async {
    if (!needsReencryption || blobs.isEmpty) {
      return blobs;
    }

    return vaultService.reencryptBlobsForCurrentVault(
      blobs: blobs,
      sourceMeta: backupMeta,
      sourcePassword: masterPassword,
      cancellationToken: cancellationToken,
    );
  }

  Future<VaultManifest> _writeManifestForImportedEnvelope({
    required VaultRepository txn,
    required VaultBackup backup,
    required String masterPassword,
    required VaultMeta meta,
    required List<EncryptedVaultItem> items,
    required VaultManifest? previous,
    required int updatedAt,
  }) async {
    final manifest = await vaultService.createManifestForImportedVault(
      masterPassword: masterPassword,
      meta: meta,
      items: items,
      blobs: await txn.blobsDao.allForManifest(),
      historyRecords:
          (await txn.historyDao?.allRowsForManifest())
              ?.map((row) => Map<String, Object?>.from(row))
              .toList(growable: false) ??
          const <Map<String, Object?>>[],
      previous: previous,
      updatedAt: updatedAt,
    );
    await vaultService.stagePendingAnchorForImportedManifest(
      repository: txn,
      meta: meta,
      manifest: manifest,
    );
    await txn.manifestDao.save(manifest);
    return manifest;
  }

  Future<VaultManifest?> _rewriteManifestAfterImport({
    required VaultRepository txn,
    required VaultBackup backup,
    required String masterPassword,
    required bool preserveExistingMeta,
    required bool dataChanged,
    required VaultManifest? previous,
    required int updatedAt,
  }) async {
    if (!preserveExistingMeta) {
      final meta = await txn.metaDao.get();
      if (meta == null) {
        throw StateError('Vault has not been created');
      }
      final items = await txn.itemsDao.allItemsForManifest();
      return _writeManifestForImportedEnvelope(
        txn: txn,
        backup: backup,
        masterPassword: masterPassword,
        meta: meta,
        items: items,
        previous: null,
        updatedAt: updatedAt,
      );
    }
    if (!dataChanged) {
      return null;
    }
    if (vaultService.isUnlocked) {
      if (previous == null) {
        throw const VaultIntegrityException();
      }
      return vaultService.rewriteManifestForCurrentVaultAfterImport(
        txn: txn,
        previous: previous,
        updatedAt: updatedAt,
      );
    }

    final meta = await txn.metaDao.get();
    if (meta == null) {
      throw StateError('Vault has not been created');
    }
    final items = await txn.itemsDao.allItemsForManifest();
    final historyRecords =
        (await txn.historyDao?.allRowsForManifest())
            ?.map((row) => Map<String, Object?>.from(row))
            .toList(growable: false) ??
        const <Map<String, Object?>>[];
    final manifest = await vaultService.createManifestForImportedVault(
      masterPassword: masterPassword,
      meta: meta,
      items: items,
      blobs: await txn.blobsDao.allForManifest(),
      historyRecords: historyRecords,
      previous: previous,
      updatedAt: updatedAt,
    );
    await vaultService.stagePendingAnchorForImportedManifest(
      repository: txn,
      meta: meta,
      manifest: manifest,
    );
    await txn.manifestDao.save(manifest);
    return manifest;
  }

  Future<void> _verifyExistingManifestBeforeImportMutation({
    required VaultRepository txn,
    required String masterPassword,
    required VaultMeta meta,
    required VaultManifest? manifest,
  }) async {
    if (manifest == null) {
      throw const VaultIntegrityException();
    }
    if (vaultService.isUnlocked) {
      await vaultService.verifyCurrentManifestForImport(txn: txn);
      return;
    }
    await vaultService.verifyBackupManifest(
      masterPassword: masterPassword,
      meta: meta,
      items: await txn.itemsDao.allItemsForManifest(),
      blobs: await txn.blobsDao.allForManifest(),
      historyRecords:
          (await txn.historyDao?.allRowsForManifest())
              ?.map((row) => Map<String, Object?>.from(row))
              .toList(growable: false) ??
          const <Map<String, Object?>>[],
      manifest: manifest,
    );
    await vaultService.verifyManifestAgainstAnchor(
      meta: meta,
      manifest: manifest,
    );
  }

  List<EncryptedVaultItem> _manifestItemsFromBackup(List<BackupItem> items) {
    return items
        .map(
          (item) => _buildImportedItem(
            item,
            createdAt: item.createdAt!,
            updatedAt: item.updatedAt!,
          ),
        )
        .toList(growable: false);
  }

  List<EncryptedVaultBlob> _manifestBlobsFromBackup(List<BackupBlob> blobs) {
    return blobs
        .map(
          (blob) => _buildImportedBlob(
            blob,
            createdAt: blob.createdAt,
            updatedAt: blob.updatedAt,
          ),
        )
        .toList(growable: false);
  }

  List<Map<String, Object?>> _manifestHistoryFromBackup(
    List<BackupHistoryItem> items,
  ) {
    return items
        .map((item) => Map<String, Object?>.from(item.toJson()))
        .toList(growable: false);
  }

  bool _hasSameEncryptionEnvelope(
    VaultMeta existingMeta,
    VaultMeta backupMeta,
  ) {
    return existingMeta.kdf == backupMeta.kdf &&
        existingMeta.kdfParams.name == backupMeta.kdfParams.name &&
        existingMeta.kdfParams.iterations == backupMeta.kdfParams.iterations &&
        existingMeta.kdfParams.bits == backupMeta.kdfParams.bits &&
        existingMeta.kdfParams.memoryKiB == backupMeta.kdfParams.memoryKiB &&
        existingMeta.kdfParams.parallelism ==
            backupMeta.kdfParams.parallelism &&
        existingMeta.salt == backupMeta.salt &&
        existingMeta.encryptedDekByMaster == backupMeta.encryptedDekByMaster &&
        existingMeta.encryptedDekByMasterNonce ==
            backupMeta.encryptedDekByMasterNonce &&
        existingMeta.encryptedDekByMasterMac ==
            backupMeta.encryptedDekByMasterMac;
  }
}

class _BackupImportResult {
  const _BackupImportResult({
    required this.importedCount,
    required this.dataChanged,
    required this.meta,
    required this.manifest,
  });

  final int importedCount;
  final bool dataChanged;
  final VaultMeta? meta;
  final VaultManifest? manifest;
}

class _ConflictAwareImportTransactionResult {
  const _ConflictAwareImportTransactionResult({
    required this.result,
    required this.dataChanged,
    required this.meta,
    required this.manifest,
  });

  final ConflictAwareBackupImportResult result;
  final bool dataChanged;
  final VaultMeta? meta;
  final VaultManifest? manifest;
}

String _readRequiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String) {
    throw BackupFormatException('Invalid "$field": expected a string');
  }

  return value;
}

int _readRequiredInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! int) {
    throw BackupFormatException('Invalid "$field": expected an int');
  }

  return value;
}

bool _readRequiredBool(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! bool) {
    throw BackupFormatException('Invalid "$field": expected a bool');
  }

  return value;
}

String? _readOptionalString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw BackupFormatException('Invalid "$field": expected a string');
  }

  return value;
}

int? _readOptionalInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw BackupFormatException('Invalid "$field": expected an int');
  }

  return value;
}

KdfParams _parseKdfParams({
  required String kdf,
  required Map<String, Object?> rawParams,
}) {
  final paramsJson = Map<String, Object?>.from(rawParams);
  paramsJson.putIfAbsent('name', () => kdf);
  final KdfParams params;
  try {
    params = KdfParams.fromJson(paramsJson);
  } on FormatException catch (error) {
    throw BackupFormatException(error.message, error.source, error.offset);
  }
  if (params.name != kdf) {
    throw BackupFormatException(
      'Invalid "kdf_params.name": expected "$kdf" but found "${params.name}"',
    );
  }
  _validateImportedKdfCost(params);
  return params;
}

void _validateImportedKdfCost(KdfParams params) {
  if (params.name == 'pbkdf2-hmac-sha256' &&
      params.iterations > _maximumImportedPbkdf2Iterations) {
    throw BackupFormatException(
      'Invalid "kdf_params.iterations": exceeds $_maximumImportedPbkdf2Iterations',
    );
  }
  if (params.name == 'argon2id') {
    final memoryKiB = params.memoryKiB;
    final parallelism = params.parallelism;
    if (memoryKiB == null ||
        memoryKiB > _maximumImportedArgon2MemoryKiB ||
        params.iterations > _maximumImportedArgon2Iterations ||
        parallelism == null ||
        parallelism > _maximumImportedArgon2Parallelism) {
      throw const BackupFormatException(
        'Invalid "kdf_params": Argon2id cost is outside the supported import range',
      );
    }
  }
}
