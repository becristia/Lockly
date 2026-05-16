import 'dart:collection';

import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:secure_box/data/models/vault_meta.dart';
import 'package:uuid/uuid.dart';

const int _legacyBackupVersion = 1;
const int _currentBackupVersion = 2;
const String _backupMagic = 'secure-box-backup';

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
  });

  final String id;
  final String nonce;
  final String ciphertext;
  final String mac;
  final int? createdAt;
  final int? updatedAt;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'nonce': nonce,
      'ciphertext': ciphertext,
      'mac': mac,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
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
    this.itemCount,
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
  }) : kdfParams = UnmodifiableMapView(Map<String, Object?>.from(kdfParams)),
       items = List.unmodifiable(items) {
    if (version != _legacyBackupVersion && version != _currentBackupVersion) {
      throw BackupFormatException('Unsupported backup version: $version');
    }
    _parseKdfParams(kdf: kdf, rawParams: this.kdfParams);
    if (version == _currentBackupVersion) {
      if (magic != _backupMagic ||
          createdAt == null ||
          itemCount != this.items.length ||
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
  final int? itemCount;
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

  Map<String, Object?> toJson() {
    return {
      'version': version,
      if (version == _currentBackupVersion) ...{
        'magic': magic,
        'created_at': createdAt,
        'item_count': itemCount,
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
    if (version == _currentBackupVersion) {
      final rawManifest = json['manifest'];
      if (rawManifest is! Map<Object?, Object?>) {
        throw const BackupFormatException('Invalid backup format');
      }
      manifest = BackupManifest.fromJson(
        Map<String, Object?>.from(rawManifest),
      );
    }

    return VaultBackup(
      version: version,
      magic: version == _currentBackupVersion
          ? _readRequiredString(json, 'magic')
          : null,
      createdAt: version == _currentBackupVersion
          ? _readRequiredInt(json, 'created_at')
          : null,
      itemCount: version == _currentBackupVersion
          ? _readRequiredInt(json, 'item_count')
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final manifest = await vaultService.createVerifiedManifestForBackup(
      items: items,
      updatedAt: now,
    );
    return VaultBackup(
      version: _currentBackupVersion,
      magic: _backupMagic,
      createdAt: now,
      itemCount: items.length,
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
      items: items
          .map(
            (item) => BackupItem(
              id: item.id,
              nonce: item.nonce,
              ciphertext: item.ciphertext,
              mac: item.mac,
              createdAt: item.createdAt,
              updatedAt: item.updatedAt,
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
    if (backup.version == _currentBackupVersion) {
      await vaultService.verifyBackupManifest(
        masterPassword: masterPassword,
        meta: backupMeta,
        items: _manifestItemsFromBackup(backup.items),
        manifest: backup.manifest!.toVaultManifest(),
      );
    }

    final result = await repository.transaction<_BackupImportResult>((
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
          final manifest = await vaultService.createManifestForImportedVault(
            masterPassword: masterPassword,
            meta: importedMeta,
            items: importedItems,
            previous: null,
            updatedAt: now,
          );
          await vaultService.verifyManifestAgainstAnchor(
            meta: importedMeta,
            manifest: manifest,
            allowMissingAnchor: true,
          );
          await txn.metaDao.save(importedMeta);
          await txn.itemsDao.deleteAll();
          for (final importedItem in importedItems) {
            await txn.itemsDao.upsert(importedItem);
          }
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
                createdAt: item.createdAt ?? now,
                updatedAt: item.updatedAt ?? now,
              ),
            );
          }
          final needsPendingReencryption =
              needsReencryption && pendingItems.isNotEmpty;
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
              await _verifyExistingAnchorBeforeImportNoop(
                meta: existingMeta,
                manifest: existingManifest,
              );
            }
          }
          final itemsToInsert = await _prepareImportedItems(
            items: pendingItems,
            backupMeta: backupMeta,
            masterPassword: masterPassword,
            needsReencryption: needsPendingReencryption,
          );
          for (final item in itemsToInsert) {
            await txn.itemsDao.upsert(item);
          }
          final manifest = await _rewriteManifestAfterImport(
            txn: txn,
            backup: backup,
            masterPassword: masterPassword,
            preserveExistingMeta: preserveExistingMeta,
            dataChanged: itemsToInsert.isNotEmpty,
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
          final needsPendingReencryption =
              needsReencryption && pendingItems.isNotEmpty;
          if (needsPendingReencryption && !vaultService.isUnlocked) {
            throw StateError(
              'Skip and merge imports into an existing vault with a different encrypted DEK envelope must already be unlocked so imported items can be re-encrypted under the current vault key.',
            );
          }
          if (preserveExistingMeta && pendingItems.isNotEmpty) {
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
          for (final item in itemsToInsert) {
            await txn.itemsDao.upsert(item);
          }
          final manifest = await _rewriteManifestAfterImport(
            txn: txn,
            backup: backup,
            masterPassword: masterPassword,
            preserveExistingMeta: preserveExistingMeta,
            dataChanged: itemsToInsert.isNotEmpty,
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
    final targetMeta = result.meta;
    final targetManifest = result.manifest;
    if (result.dataChanged && targetMeta != null && targetManifest != null) {
      await vaultService.acceptManifestForCurrentState(
        meta: targetMeta,
        manifest: targetManifest,
      );
    }
    return result.importedCount;
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
      previous: previous,
      updatedAt: updatedAt,
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
    final manifest = await vaultService.createManifestForImportedVault(
      masterPassword: masterPassword,
      meta: meta,
      items: items,
      previous: previous,
      updatedAt: updatedAt,
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
      manifest: manifest,
    );
    await vaultService.verifyManifestAgainstAnchor(
      meta: meta,
      manifest: manifest,
    );
  }

  Future<void> _verifyExistingAnchorBeforeImportNoop({
    required VaultMeta meta,
    required VaultManifest? manifest,
  }) async {
    if (manifest == null) {
      throw const VaultIntegrityException();
    }
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
  return params;
}
