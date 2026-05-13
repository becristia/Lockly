import 'dart:collection';

import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/vault_meta.dart';
import 'package:uuid/uuid.dart';

const int _supportedBackupVersion = 1;

class BackupFormatException extends FormatException {
  const BackupFormatException(super.message, [super.source, super.offset]);
}

class BackupItem {
  const BackupItem({
    required this.id,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final String id;
  final String nonce;
  final String ciphertext;
  final String mac;

  Map<String, Object?> toJson() => {
    'id': id,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
  };

  factory BackupItem.fromJson(Map<String, Object?> json) {
    return BackupItem(
      id: _readRequiredString(json, 'id'),
      nonce: _readRequiredString(json, 'nonce'),
      ciphertext: _readRequiredString(json, 'ciphertext'),
      mac: _readRequiredString(json, 'mac'),
    );
  }
}

class VaultBackup {
  VaultBackup({
    required this.version,
    required this.kdf,
    required Map<String, Object?> kdfParams,
    required this.salt,
    required this.encryptedDekByMaster,
    required this.encryptedDekByMasterNonce,
    required this.encryptedDekByMasterMac,
    required List<BackupItem> items,
  }) : kdfParams = UnmodifiableMapView(Map<String, Object?>.from(kdfParams)),
       items = List.unmodifiable(items) {
    if (version != _supportedBackupVersion) {
      throw BackupFormatException('Unsupported backup version: $version');
    }
    _parseKdfParams(kdf: kdf, rawParams: this.kdfParams);
  }

  final int version;
  final String kdf;
  final Map<String, Object?> kdfParams;
  final String salt;
  final String encryptedDekByMaster;
  final String encryptedDekByMasterNonce;
  final String encryptedDekByMasterMac;
  final List<BackupItem> items;

  Map<String, Object?> toJson() => {
    'version': version,
    'kdf': kdf,
    'kdf_params': Map<String, Object?>.from(kdfParams),
    'salt': salt,
    'encrypted_dek_by_master': encryptedDekByMaster,
    'encrypted_dek_by_master_nonce': encryptedDekByMasterNonce,
    'encrypted_dek_by_master_mac': encryptedDekByMasterMac,
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };

  factory VaultBackup.fromJson(Map<String, Object?> json) {
    final version = _readRequiredInt(json, 'version');
    if (version != _supportedBackupVersion) {
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

    return VaultBackup(
      version: version,
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
    );
  }

  KdfParams get parsedKdfParams =>
      _parseKdfParams(kdf: kdf, rawParams: kdfParams);
}

enum BackupImportMode { overwrite, skip, merge }

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
    return VaultBackup(
      version: meta.version,
      kdf: meta.kdf,
      kdfParams: {
        'iterations': meta.kdfParams.iterations,
        'bits': meta.kdfParams.bits,
      },
      salt: meta.salt,
      encryptedDekByMaster: meta.encryptedDekByMaster,
      encryptedDekByMasterNonce: meta.encryptedDekByMasterNonce,
      encryptedDekByMasterMac: meta.encryptedDekByMasterMac,
      items: items
          .map(
            (item) => BackupItem(
              id: item.id,
              nonce: item.nonce,
              ciphertext: item.ciphertext,
              mac: item.mac,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<int> importBackup({
    required Map<String, Object?> json,
    required String masterPassword,
    required BackupImportMode mode,
  }) async {
    final backup = VaultBackup.fromJson(json);
    final backupMeta = _backupMetaForVerification(backup);
    await vaultService.verifyMasterPassword(
      masterPassword: masterPassword,
      meta: backupMeta,
    );

    return repository.transaction((txn) async {
      final existingMeta = await txn.metaDao.get();
      final now = DateTime.now().millisecondsSinceEpoch;
      final hasExistingVault = existingMeta != null;
      final preserveExistingMeta =
          mode != BackupImportMode.overwrite && hasExistingVault;
      final needsReencryption =
          preserveExistingMeta &&
          !_hasSameEncryptionEnvelope(existingMeta, backupMeta);

      if (needsReencryption && !vaultService.isUnlocked) {
        throw StateError(
          'Skip and merge imports into an existing vault with a different encrypted DEK envelope must already be unlocked so imported items can be re-encrypted under the current vault key.',
        );
      }

      final importedMeta = _buildImportedMeta(
        backup: backup,
        existingMeta: existingMeta,
        now: now,
      );

      switch (mode) {
        case BackupImportMode.overwrite:
          await txn.metaDao.save(importedMeta);
          await txn.itemsDao.executor.delete('vault_items');
          for (final item in backup.items) {
            await txn.itemsDao.upsert(
              _buildImportedItem(item, createdAt: now, updatedAt: now),
            );
          }
          return backup.items.length;
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
              _buildImportedItem(item, createdAt: now, updatedAt: now),
            );
          }
          final itemsToInsert = await _prepareImportedItems(
            items: pendingItems,
            backupMeta: backupMeta,
            masterPassword: masterPassword,
            needsReencryption: needsReencryption,
          );
          for (final item in itemsToInsert) {
            await txn.itemsDao.upsert(item);
          }
          return itemsToInsert.length;
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
                createdAt: existingItem?.createdAt ?? now,
                updatedAt: now,
              ),
            );
          }
          final itemsToInsert = await _prepareImportedItems(
            items: pendingItems,
            backupMeta: backupMeta,
            masterPassword: masterPassword,
            needsReencryption: needsReencryption,
          );
          for (final item in itemsToInsert) {
            await txn.itemsDao.upsert(item);
          }
          return backup.items.length;
      }
    });
  }

  VaultMeta _backupMetaForVerification(VaultBackup backup) {
    return VaultMeta(
      id: 'backup-verification',
      version: backup.version,
      kdf: backup.kdf,
      kdfParams: backup.parsedKdfParams,
      salt: backup.salt,
      encryptedDekByMaster: backup.encryptedDekByMaster,
      encryptedDekByMasterNonce: backup.encryptedDekByMasterNonce,
      encryptedDekByMasterMac: backup.encryptedDekByMasterMac,
      biometricEnabled: false,
      createdAt: 0,
      updatedAt: 0,
      encryptedDekByBiometric: null,
      encryptedDekByBiometricNonce: null,
      encryptedDekByBiometricMac: null,
    );
  }

  VaultMeta _buildImportedMeta({
    required VaultBackup backup,
    required VaultMeta? existingMeta,
    required int now,
  }) {
    return VaultMeta(
      id: existingMeta?.id ?? _uuid.v4(),
      version: backup.version,
      kdf: backup.kdf,
      kdfParams: backup.parsedKdfParams,
      salt: backup.salt,
      encryptedDekByMaster: backup.encryptedDekByMaster,
      encryptedDekByMasterNonce: backup.encryptedDekByMasterNonce,
      encryptedDekByMasterMac: backup.encryptedDekByMasterMac,
      biometricEnabled: false,
      createdAt: existingMeta?.createdAt ?? now,
      updatedAt: now,
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
    );
  }

  Future<List<EncryptedVaultItem>> _prepareImportedItems({
    required List<EncryptedVaultItem> items,
    required VaultMeta backupMeta,
    required String masterPassword,
    required bool needsReencryption,
  }) async {
    if (!needsReencryption || items.isEmpty) {
      return items;
    }

    return vaultService.reencryptItemsForCurrentVault(
      items: items,
      sourceMeta: backupMeta,
      sourcePassword: masterPassword,
    );
  }

  bool _hasSameEncryptionEnvelope(
    VaultMeta existingMeta,
    VaultMeta backupMeta,
  ) {
    return existingMeta.kdf == backupMeta.kdf &&
        existingMeta.kdfParams.name == backupMeta.kdfParams.name &&
        existingMeta.kdfParams.iterations == backupMeta.kdfParams.iterations &&
        existingMeta.kdfParams.bits == backupMeta.kdfParams.bits &&
        existingMeta.salt == backupMeta.salt &&
        existingMeta.encryptedDekByMaster == backupMeta.encryptedDekByMaster &&
        existingMeta.encryptedDekByMasterNonce ==
            backupMeta.encryptedDekByMasterNonce &&
        existingMeta.encryptedDekByMasterMac ==
            backupMeta.encryptedDekByMasterMac;
  }
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

KdfParams _parseKdfParams({
  required String kdf,
  required Map<String, Object?> rawParams,
}) {
  final iterations = rawParams['iterations'];
  if (iterations is! int) {
    throw const BackupFormatException(
      'Invalid "kdf_params.iterations": expected an int',
    );
  }

  final bits = rawParams['bits'];
  if (bits is! int) {
    throw const BackupFormatException(
      'Invalid "kdf_params.bits": expected an int',
    );
  }

  return KdfParams(name: kdf, iterations: iterations, bits: bits);
}
