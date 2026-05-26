import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Hkdf, Hmac, SecretKey;
import 'package:secure_box/core/biometric/biometric_service.dart';
import 'package:secure_box/core/cancellation/cancellation_token.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/encoding.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/core/vault/vault_anchor_service.dart';
import 'package:secure_box/core/vault/vault_anchor_store.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_session.dart';
import 'package:secure_box/data/models/encrypted_vault_blob.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:secure_box/data/models/vault_meta.dart';
import 'package:uuid/uuid.dart';

const _blobKeyLength = 32;
const _blobKeyInfoPrefix = 'lockly:vault-blob:v1:';
const maxVaultBlobBytes = 1024 * 1024;

class VaultUnlockException implements Exception {
  const VaultUnlockException(this.message);

  final String message;

  @override
  String toString() => 'VaultUnlockException: $message';
}

class VaultItemNotFoundException implements Exception {
  const VaultItemNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'VaultItemNotFoundException: $id';
}

class VaultBlobTooLargeException implements Exception {
  const VaultBlobTooLargeException(this.sizeBytes);

  final int sizeBytes;

  @override
  String toString() => 'VaultBlobTooLargeException: $sizeBytes';
}

class VaultListItem {
  VaultListItem({
    required this.id,
    required this.title,
    required this.website,
    required this.username,
    required List<String> tags,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  }) : tags = List.unmodifiable(tags);

  final String id;
  final String title;
  final String website;
  final String username;
  final List<String> tags;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
}

class VaultItemImportIdentity {
  const VaultItemImportIdentity({
    required this.id,
    required this.title,
    required this.website,
    required this.username,
  });

  final String id;
  final String title;
  final String website;
  final String username;
}

class TotpListItem {
  TotpListItem({
    required this.id,
    required this.title,
    required this.username,
    required this.totpSecret,
  });
  final String id;
  final String title;
  final String username;
  final String totpSecret;
}

class VaultBlobListItem {
  VaultBlobListItem({
    required this.blobId,
    required this.itemId,
    required this.displayName,
    required this.mediaType,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String blobId;
  final String itemId;
  final String displayName;
  final String mediaType;
  final int sizeBytes;
  final int createdAt;
  final int updatedAt;
}

class DecryptedVaultBlob {
  DecryptedVaultBlob({
    required this.blobId,
    required this.itemId,
    required this.displayName,
    required this.mediaType,
    required this.bytes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String blobId;
  final String itemId;
  final String displayName;
  final String mediaType;
  final Uint8List bytes;
  final int createdAt;
  final int updatedAt;
}

class VerifiedEncryptedVaultSyncSnapshot {
  VerifiedEncryptedVaultSyncSnapshot({
    required this.meta,
    required this.manifest,
    required List<EncryptedVaultItem> items,
    required List<EncryptedVaultBlob> blobs,
  }) : items = List.unmodifiable(items),
       blobs = List.unmodifiable(blobs);

  final VaultMeta meta;
  final VaultManifest manifest;
  final List<EncryptedVaultItem> items;
  final List<EncryptedVaultBlob> blobs;
}

class PasswordWrappedVaultExport {
  PasswordWrappedVaultExport({
    required this.meta,
    required this.manifest,
    required List<EncryptedVaultItem> items,
    required List<EncryptedVaultBlob> blobs,
    required List<Map<String, Object?>> historyRecords,
  }) : items = List.unmodifiable(items),
       blobs = List.unmodifiable(blobs),
       historyRecords = List.unmodifiable(
         historyRecords.map(Map<String, Object?>.from),
       );

  final VaultMeta meta;
  final VaultManifest manifest;
  final List<EncryptedVaultItem> items;
  final List<EncryptedVaultBlob> blobs;
  final List<Map<String, Object?>> historyRecords;
}

class VaultService {
  VaultService({
    required this.repository,
    required SecureRandom random,
    required KdfService kdf,
    required CryptoService crypto,
    VaultSession? session,
    Uuid? uuid,
    VaultManifestService? manifestService,
    VaultAnchorService? anchorService,
  }) : _random = random,
       _kdf = kdf,
       _crypto = crypto,
       _session = session ?? VaultSession(),
       _uuid = uuid ?? const Uuid(),
       _manifestService =
           manifestService ?? VaultManifestService(crypto: crypto),
       _anchorService =
           anchorService ?? VaultAnchorService(store: MemoryVaultAnchorStore());

  final VaultRepository repository;
  final SecureRandom _random;
  final KdfService _kdf;
  final CryptoService _crypto;
  final VaultSession _session;
  final Uuid _uuid;
  final VaultManifestService _manifestService;
  final VaultAnchorService _anchorService;
  final Hkdf _blobHkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: _blobKeyLength,
  );

  bool get isUnlocked => _session.isUnlocked;

  void lock() {
    _session.lock();
  }

  Future<bool> isBiometricUnlockEnabled() async {
    final meta = await repository.metaDao.get();
    return meta?.biometricEnabled ?? false;
  }

  Future<void> createVault({required String masterPassword}) async {
    if (await repository.metaDao.get() != null) {
      throw StateError('Vault already exists');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final salt = _random.bytes(16);
    final kdfParams = KdfParams.argon2id();
    Uint8List? kek;
    Uint8List? dek;
    VaultMeta? createdMeta;
    VaultManifest? createdManifest;
    try {
      kek = await _kdf.deriveKey(
        password: masterPassword,
        salt: salt,
        params: kdfParams,
      );
      dek = _random.bytes(32);
      final encryptedDek = await _crypto.encryptBytes(key: kek, plaintext: dek);
      final meta = VaultMeta(
        id: _uuid.v4(),
        version: 1,
        kdf: kdfParams.name,
        kdfParams: kdfParams,
        salt: b64(salt),
        encryptedDekByMaster: b64(encryptedDek.ciphertext),
        encryptedDekByMasterNonce: b64(encryptedDek.nonce),
        encryptedDekByMasterMac: b64(encryptedDek.mac),
        biometricEnabled: false,
        createdAt: now,
        updatedAt: now,
        encryptedDekByBiometric: null,
        encryptedDekByBiometricNonce: null,
        encryptedDekByBiometricMac: null,
      );

      await repository.transaction((txn) async {
        await txn.metaDao.save(meta);
        await txn.settingsDao.setValue('clipboard_clear_seconds', '30');
        final manifest = await _manifestService.createManifest(
          dek: dek!,
          meta: meta,
          items: const [],
          historyRecords: const [],
          previous: null,
          updatedAt: now,
        );
        await txn.manifestDao.save(manifest);
        createdMeta = meta;
        createdManifest = manifest;
      });
      await _writeAnchorForManifest(
        meta: createdMeta!,
        manifest: createdManifest!,
      );
      _session.lock();
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    } finally {
      _zeroBytes(kek);
      _zeroBytes(dek);
    }
  }

  Future<VaultSession> unlock({required String masterPassword}) async {
    final meta = await _requireVaultMeta();
    Uint8List? dek;

    try {
      dek = await _decryptDek(meta: meta, password: masterPassword);
      final manifest = await _verifyExistingManifest(meta: meta, dek: dek);
      await _verifyAnchorForManifest(
        meta: meta,
        manifest: manifest,
        allowMissingAnchor: true,
      );
      await _writeAnchorForManifest(meta: meta, manifest: manifest);
      _session.unlock(dek);
      return _session;
    } on CryptoException {
      _session.lock();
      throw const VaultUnlockException('Invalid master password');
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    } finally {
      _zeroBytes(dek);
    }
  }

  Future<bool> unlockWithBiometrics({
    required BiometricService biometricService,
  }) async {
    final meta = await _requireVaultMeta();
    if (!meta.biometricEnabled) {
      return false;
    }

    final result = await biometricService.unlock();
    final dek = result.dek;
    if (result.status != BiometricUnlockStatus.unlocked || dek == null) {
      _zeroBytes(dek);
      _session.lock();
      return false;
    }

    try {
      final manifest = await _readManifestForIntegrity(repository);
      if (manifest == null) {
        _session.lock();
        return false;
      }
      final items = await _readItemsForManifest(repository);
      final blobs = await _readBlobsForManifest(repository);
      final historyRecords = await _readHistoryForManifest(repository);
      await _manifestService.verifyManifest(
        dek: dek,
        meta: meta,
        items: items,
        blobs: blobs,
        historyRecords: historyRecords,
        manifest: manifest,
      );
      await _verifyAnchorForManifest(
        meta: meta,
        manifest: manifest,
        allowMissingAnchor: false,
      );
      _session.unlock(dek);
      return true;
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    } finally {
      _zeroBytes(dek);
    }
  }

  Future<void> enableBiometricUnlock({
    required String masterPassword,
    required BiometricService biometricService,
  }) async {
    final meta = await _requireVaultMeta();
    Uint8List? dek;
    var biometricEnabled = false;
    try {
      dek = await _decryptDekWithUnlockError(
        meta: meta,
        password: masterPassword,
      );
      final currentManifest = await _verifyExistingManifest(
        meta: meta,
        dek: dek,
      );
      await _verifyAnchorForManifest(
        meta: meta,
        manifest: currentManifest,
        allowMissingAnchor: false,
      );
      await biometricService.enable(dek);
      biometricEnabled = true;
      final updatedAt = DateTime.now().millisecondsSinceEpoch;
      final updatedMeta = VaultMeta(
        id: meta.id,
        version: meta.version,
        kdf: meta.kdf,
        kdfParams: meta.kdfParams,
        salt: meta.salt,
        encryptedDekByMaster: meta.encryptedDekByMaster,
        encryptedDekByMasterNonce: meta.encryptedDekByMasterNonce,
        encryptedDekByMasterMac: meta.encryptedDekByMasterMac,
        biometricEnabled: true,
        createdAt: meta.createdAt,
        updatedAt: updatedAt,
        encryptedDekByBiometric: null,
        encryptedDekByBiometricNonce: null,
        encryptedDekByBiometricMac: null,
      );
      final manifest = await repository.transaction((txn) async {
        final manifest = await _saveManifestForMetadataUpdate(
          txn: txn,
          dek: dek!,
          currentMeta: meta,
          updatedMeta: updatedMeta,
          updatedAt: updatedAt,
        );
        await txn.metaDao.save(updatedMeta);
        return manifest;
      });
      await _writeAnchorForManifest(meta: updatedMeta, manifest: manifest);
    } catch (error) {
      if (biometricEnabled) {
        await biometricService.disable();
      }
      if (_isIntegrityReadFailure(error)) {
        _session.lock();
      }
      rethrow;
    } finally {
      _zeroBytes(dek);
    }
  }

  Future<void> disableBiometricUnlock({
    required BiometricService biometricService,
  }) async {
    final meta = await _requireVaultMeta();
    if (!meta.biometricEnabled) {
      await biometricService.disable();
      return;
    }

    try {
      await _withDekForBiometricDisable(
        biometricService: biometricService,
        action: (dek) async {
          await _verifyExistingManifest(meta: meta, dek: dek);
          final updatedAt = DateTime.now().millisecondsSinceEpoch;
          final updatedMeta = VaultMeta(
            id: meta.id,
            version: meta.version,
            kdf: meta.kdf,
            kdfParams: meta.kdfParams,
            salt: meta.salt,
            encryptedDekByMaster: meta.encryptedDekByMaster,
            encryptedDekByMasterNonce: meta.encryptedDekByMasterNonce,
            encryptedDekByMasterMac: meta.encryptedDekByMasterMac,
            biometricEnabled: false,
            createdAt: meta.createdAt,
            updatedAt: updatedAt,
            encryptedDekByBiometric: null,
            encryptedDekByBiometricNonce: null,
            encryptedDekByBiometricMac: null,
          );
          await biometricService.disable();
          final manifest = await repository.transaction((txn) async {
            final manifest = await _saveManifestForMetadataUpdate(
              txn: txn,
              dek: dek,
              currentMeta: meta,
              updatedMeta: updatedMeta,
              updatedAt: updatedAt,
            );
            await txn.metaDao.save(updatedMeta);
            return manifest;
          });
          await _writeAnchorForManifest(meta: updatedMeta, manifest: manifest);
        },
      );
    } catch (error) {
      if (_isIntegrityReadFailure(error)) {
        _session.lock();
      }
      rethrow;
    }
  }

  Future<void> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
    BiometricService? biometricService,
    Future<void> Function()? beforePersist,
  }) async {
    final meta = await _requireVaultMeta();
    Uint8List? dek;
    Uint8List? newKek;
    try {
      dek = await _decryptDekWithUnlockError(meta: meta, password: oldPassword);
      final currentManifest = await _verifyExistingManifest(
        meta: meta,
        dek: dek,
      );
      await _verifyAnchorForManifest(
        meta: meta,
        manifest: currentManifest,
        allowMissingAnchor: false,
      );
      final newSalt = _random.bytes(16);
      final newKdfParams = KdfParams.argon2id();
      newKek = await _kdf.deriveKey(
        password: newPassword,
        salt: newSalt,
        params: newKdfParams,
      );
      final wrappedDek = await _crypto.encryptBytes(
        key: newKek,
        plaintext: dek,
      );
      final updatedAt = DateTime.now().millisecondsSinceEpoch;
      final updatedMeta = VaultMeta(
        id: meta.id,
        version: meta.version,
        kdf: newKdfParams.name,
        kdfParams: newKdfParams,
        salt: b64(newSalt),
        encryptedDekByMaster: b64(wrappedDek.ciphertext),
        encryptedDekByMasterNonce: b64(wrappedDek.nonce),
        encryptedDekByMasterMac: b64(wrappedDek.mac),
        biometricEnabled: false,
        createdAt: meta.createdAt,
        updatedAt: updatedAt,
        encryptedDekByBiometric: null,
        encryptedDekByBiometricNonce: null,
        encryptedDekByBiometricMac: null,
      );

      final service = biometricService;
      if (service == null) {
        throw StateError(
          'A biometric service is required when changing the master password so any biometric DEK copy can be cleared.',
        );
      }
      await service.disable();
      await beforePersist?.call();
      final manifest = await repository.transaction((txn) async {
        final manifest = await _saveManifestForMetadataUpdate(
          txn: txn,
          dek: dek!,
          currentMeta: meta,
          updatedMeta: updatedMeta,
          updatedAt: updatedAt,
        );
        await txn.metaDao.save(updatedMeta);
        return manifest;
      });
      await _writeAnchorForManifest(meta: updatedMeta, manifest: manifest);
      _session.unlock(dek);
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    } finally {
      _zeroBytes(newKek);
      _zeroBytes(dek);
    }
  }

  Future<void> verifyMasterPassword({
    required String masterPassword,
    VaultMeta? meta,
  }) async {
    Uint8List? dek;
    try {
      dek = await _decryptDekWithUnlockError(
        meta: meta ?? await _requireVaultMeta(),
        password: masterPassword,
      );
    } finally {
      _zeroBytes(dek);
    }
  }

  Future<VaultManifest> createVerifiedManifestForBackup({
    required List<EncryptedVaultItem> items,
    List<EncryptedVaultBlob> blobs = const [],
    List<Map<String, Object?>> historyRecords = const [],
    required int updatedAt,
  }) async {
    _ensureUnlocked();
    try {
      return await _session.withDekCopy((dek) async {
        final meta = await _requireVaultMeta();
        final manifest = await _readManifestForIntegrity(repository);
        if (manifest == null) {
          throw const VaultIntegrityException();
        }
        final currentItems = await _readItemsForManifest(repository);
        final currentBlobs = await _readBlobsForManifest(repository);
        final currentHistoryRecords = await _readHistoryForManifest(repository);
        await _manifestService.verifyManifest(
          dek: dek,
          meta: meta,
          items: currentItems,
          blobs: currentBlobs,
          historyRecords: currentHistoryRecords,
          manifest: manifest,
        );
        await _verifyAnchorForManifest(
          meta: meta,
          manifest: manifest,
          allowMissingAnchor: false,
        );
        return _manifestService.createManifest(
          dek: dek,
          meta: meta,
          items: items,
          blobs: blobs,
          historyRecords: historyRecords,
          previous: manifest,
          updatedAt: updatedAt,
        );
      });
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  Future<PasswordWrappedVaultExport> createPasswordWrappedExport({
    required String exportPassword,
    required List<EncryptedVaultItem> items,
    List<EncryptedVaultBlob> blobs = const [],
    List<Map<String, Object?>> historyRecords = const [],
    required String exportVaultId,
    required int createdAt,
    required int updatedAt,
  }) async {
    final currentMeta = await _requireVaultMeta();
    await verifyMasterPassword(
      masterPassword: exportPassword,
      meta: currentMeta,
    );
    _ensureUnlocked();

    Uint8List? kek;
    Uint8List? packageDek;
    try {
      return await _session.withDekCopy((sourceDek) async {
        final manifest = await _readManifestForIntegrity(repository);
        if (manifest == null) {
          throw const VaultIntegrityException();
        }
        final currentItems = await _readItemsForManifest(repository);
        final currentBlobs = await _readBlobsForManifest(repository);
        final currentHistoryRecords = await _readHistoryForManifest(repository);
        await _manifestService.verifyManifest(
          dek: sourceDek,
          meta: currentMeta,
          items: currentItems,
          blobs: currentBlobs,
          historyRecords: currentHistoryRecords,
          manifest: manifest,
        );
        await _verifyAnchorForManifest(
          meta: currentMeta,
          manifest: manifest,
          allowMissingAnchor: false,
        );

        final salt = _random.bytes(16);
        final kdfParams = KdfParams.argon2id();
        kek = await _kdf.deriveKey(
          password: exportPassword,
          salt: salt,
          params: kdfParams,
        );
        packageDek = _random.bytes(32);
        final wrappedDek = await _crypto.encryptBytes(
          key: kek!,
          plaintext: packageDek!,
        );
        final exportMeta = VaultMeta(
          id: exportVaultId,
          version: 1,
          kdf: kdfParams.name,
          kdfParams: kdfParams,
          salt: b64(salt),
          encryptedDekByMaster: b64(wrappedDek.ciphertext),
          encryptedDekByMasterNonce: b64(wrappedDek.nonce),
          encryptedDekByMasterMac: b64(wrappedDek.mac),
          biometricEnabled: false,
          createdAt: createdAt,
          updatedAt: updatedAt,
          encryptedDekByBiometric: null,
          encryptedDekByBiometricNonce: null,
          encryptedDekByBiometricMac: null,
        );
        final exportItems = await _reencryptItemsBetweenDeks(
          items: items,
          sourceDek: sourceDek,
          targetDek: packageDek!,
        );
        final exportBlobs = await _reencryptBlobsBetweenDeks(
          blobs: blobs,
          sourceDek: sourceDek,
          targetDek: packageDek!,
        );
        final exportHistoryRecords = await _reencryptHistoryBetweenDeks(
          records: historyRecords,
          sourceDek: sourceDek,
          targetDek: packageDek!,
        );
        final exportManifest = await _manifestService.createManifest(
          dek: packageDek!,
          meta: exportMeta,
          items: exportItems,
          blobs: exportBlobs,
          historyRecords: exportHistoryRecords,
          previous: null,
          updatedAt: updatedAt,
        );
        return PasswordWrappedVaultExport(
          meta: exportMeta,
          manifest: exportManifest,
          items: exportItems,
          blobs: exportBlobs,
          historyRecords: exportHistoryRecords,
        );
      });
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    } finally {
      _zeroBytes(kek);
      _zeroBytes(packageDek);
    }
  }

  Future<VerifiedEncryptedVaultSyncSnapshot>
  createVerifiedEncryptedSyncSnapshot() async {
    _ensureUnlocked();
    try {
      return await _session.withDekCopy((dek) async {
        return repository.transaction((txn) async {
          final meta = await txn.metaDao.get();
          if (meta == null) {
            throw StateError('Vault has not been created');
          }
          final manifest = await _readManifestForIntegrity(txn);
          if (manifest == null) {
            throw const VaultIntegrityException();
          }
          final items = await _readItemsForManifest(txn);
          final blobs = await _readBlobsForManifest(txn);
          final historyRecords = await _readHistoryForManifest(txn);
          await _manifestService.verifyManifest(
            dek: dek,
            meta: meta,
            items: items,
            blobs: blobs,
            historyRecords: historyRecords,
            manifest: manifest,
          );
          await _verifyAnchorForManifest(
            meta: meta,
            manifest: manifest,
            allowMissingAnchor: false,
          );
          return VerifiedEncryptedVaultSyncSnapshot(
            meta: meta,
            manifest: manifest,
            items: items,
            blobs: blobs,
          );
        });
      });
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  Future<void> verifyBackupManifest({
    required String masterPassword,
    required VaultMeta meta,
    required List<EncryptedVaultItem> items,
    required VaultManifest manifest,
    List<EncryptedVaultBlob> blobs = const [],
    List<Map<String, Object?>> historyRecords = const [],
    CancellationToken? cancellationToken,
  }) async {
    Uint8List? dek;
    try {
      cancellationToken?.throwIfCancelled();
      dek = await _decryptDekWithUnlockError(
        meta: meta,
        password: masterPassword,
      );
      cancellationToken?.throwIfCancelled();
      await _manifestService.verifyManifest(
        dek: dek,
        meta: meta,
        items: items,
        blobs: blobs,
        historyRecords: historyRecords,
        manifest: manifest,
      );
      cancellationToken?.throwIfCancelled();
    } finally {
      _zeroBytes(dek);
    }
  }

  Future<VaultManifest> createManifestForImportedVault({
    required String masterPassword,
    required VaultMeta meta,
    required List<EncryptedVaultItem> items,
    List<EncryptedVaultBlob> blobs = const [],
    List<Map<String, Object?>> historyRecords = const [],
    required VaultManifest? previous,
    required int updatedAt,
  }) async {
    Uint8List? dek;
    try {
      dek = await _decryptDekWithUnlockError(
        meta: meta,
        password: masterPassword,
      );
      return await _manifestService.createManifest(
        dek: dek,
        meta: meta,
        items: items,
        blobs: blobs,
        historyRecords: historyRecords,
        previous: previous,
        updatedAt: updatedAt,
      );
    } finally {
      _zeroBytes(dek);
    }
  }

  Future<void> verifyCurrentManifestForImport({
    required VaultRepository txn,
  }) async {
    _ensureUnlocked();
    try {
      await _session.withDekCopy((dek) async {
        final currentMeta = await txn.metaDao.get();
        if (currentMeta == null) {
          throw StateError('Vault has not been created');
        }
        final previous = await _readManifestForIntegrity(txn);
        if (previous == null) {
          throw const VaultIntegrityException();
        }
        final items = await _readItemsForManifest(txn);
        final blobs = await _readBlobsForManifest(txn);
        final historyRecords = await _readHistoryForManifest(txn);
        await _manifestService.verifyManifest(
          dek: dek,
          meta: currentMeta,
          items: items,
          blobs: blobs,
          historyRecords: historyRecords,
          manifest: previous,
        );
        await _verifyAnchorForManifest(
          meta: currentMeta,
          manifest: previous,
          allowMissingAnchor: false,
        );
      });
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  Future<VaultManifest> rewriteManifestForCurrentVaultAfterImport({
    required VaultRepository txn,
    required VaultManifest previous,
    required int updatedAt,
  }) async {
    _ensureUnlocked();
    try {
      return await _session.withDekCopy((dek) async {
        final currentMeta = await txn.metaDao.get();
        if (currentMeta == null) {
          throw StateError('Vault has not been created');
        }
        final items = await _readItemsForManifest(txn);
        final blobs = await _readBlobsForManifest(txn);
        final historyRecords = await _readHistoryForManifest(txn);
        final manifest = await _manifestService.createManifest(
          dek: dek,
          meta: currentMeta,
          items: items,
          blobs: blobs,
          historyRecords: historyRecords,
          previous: previous,
          updatedAt: updatedAt,
        );
        await txn.manifestDao.save(manifest);
        return manifest;
      });
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  Future<void> acceptManifestForCurrentState({
    required VaultMeta meta,
    required VaultManifest manifest,
  }) async {
    try {
      await _verifyAnchorForManifest(
        meta: meta,
        manifest: manifest,
        allowMissingAnchor: true,
        allowNewerManifest: true,
      );
      await _writeAnchorForManifest(meta: meta, manifest: manifest);
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  Future<void> verifyManifestAgainstAnchor({
    required VaultMeta meta,
    required VaultManifest manifest,
    bool allowMissingAnchor = false,
    bool allowNewerManifest = false,
  }) {
    return _verifyAnchorForManifest(
      meta: meta,
      manifest: manifest,
      allowMissingAnchor: allowMissingAnchor,
      allowNewerManifest: allowNewerManifest,
    );
  }

  Future<void> clearLocalVault() async {
    final meta = await repository.metaDao.get();
    try {
      await repository.transaction((txn) async {
        await txn.historyDao?.deleteAll();
        await txn.blobsDao.deleteAll();
        await txn.itemsDao.deleteAll();
        await txn.manifestDao.deleteAll();
        await txn.metaDao.deleteAll();
        await txn.settingsDao.deleteAll();
      });
      await _deleteAnchorForMeta(meta);
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
    _session.lock();
  }

  Future<List<EncryptedVaultItem>> _reencryptItemsBetweenDeks({
    required List<EncryptedVaultItem> items,
    required Uint8List sourceDek,
    required Uint8List targetDek,
  }) async {
    final reencryptedItems = <EncryptedVaultItem>[];
    for (final item in items) {
      Uint8List? plaintext;
      try {
        plaintext = await _crypto.decryptBytes(
          key: sourceDek,
          payload: EncryptedPayload(
            nonce: fromB64(item.nonce),
            ciphertext: fromB64(item.ciphertext),
            mac: fromB64(item.mac),
          ),
        );
        final encryptedPayload = await _crypto.encryptBytes(
          key: targetDek,
          plaintext: plaintext,
        );
        reencryptedItems.add(
          EncryptedVaultItem(
            id: item.id,
            nonce: b64(encryptedPayload.nonce),
            ciphertext: b64(encryptedPayload.ciphertext),
            mac: b64(encryptedPayload.mac),
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            deletedAt: item.deletedAt,
          ),
        );
      } finally {
        _zeroBytes(plaintext);
      }
    }
    return List.unmodifiable(reencryptedItems);
  }

  Future<List<Map<String, Object?>>> _reencryptHistoryBetweenDeks({
    required List<Map<String, Object?>> records,
    required Uint8List sourceDek,
    required Uint8List targetDek,
  }) async {
    final reencryptedRecords = <Map<String, Object?>>[];
    for (final record in records) {
      Uint8List? plaintext;
      try {
        plaintext = await _crypto.decryptBytes(
          key: sourceDek,
          payload: EncryptedPayload(
            nonce: fromB64(record['password_nonce'] as String),
            ciphertext: fromB64(record['encrypted_password'] as String),
            mac: fromB64(record['password_mac'] as String),
          ),
        );
        final encryptedPayload = await _crypto.encryptBytes(
          key: targetDek,
          plaintext: plaintext,
        );
        reencryptedRecords.add({
          'id': record['id'],
          'entry_id': record['entry_id'],
          'encrypted_password': b64(encryptedPayload.ciphertext),
          'password_nonce': b64(encryptedPayload.nonce),
          'password_mac': b64(encryptedPayload.mac),
          'recorded_at': record['recorded_at'],
        });
      } finally {
        _zeroBytes(plaintext);
      }
    }
    return List.unmodifiable(reencryptedRecords);
  }

  Future<List<EncryptedVaultBlob>> _reencryptBlobsBetweenDeks({
    required List<EncryptedVaultBlob> blobs,
    required Uint8List sourceDek,
    required Uint8List targetDek,
  }) async {
    final reencryptedBlobs = <EncryptedVaultBlob>[];
    for (final blob in blobs) {
      Uint8List? sourceBlobKey;
      Uint8List? targetBlobKey;
      Uint8List? metadataPlaintext;
      Uint8List? contentPlaintext;
      try {
        sourceBlobKey = await _deriveBlobKey(
          dek: sourceDek,
          blobId: blob.blobId,
        );
        metadataPlaintext = await _crypto.decryptBytes(
          key: sourceBlobKey,
          payload: EncryptedPayload(
            nonce: fromB64(blob.metadataNonce),
            ciphertext: fromB64(blob.metadataCiphertext),
            mac: fromB64(blob.metadataMac),
          ),
        );
        contentPlaintext = await _crypto.decryptBytes(
          key: sourceBlobKey,
          payload: EncryptedPayload(
            nonce: fromB64(blob.nonce),
            ciphertext: fromB64(blob.ciphertext),
            mac: fromB64(blob.mac),
          ),
        );
        targetBlobKey = await _deriveBlobKey(
          dek: targetDek,
          blobId: blob.blobId,
        );
        final encryptedMetadata = await _crypto.encryptBytes(
          key: targetBlobKey,
          plaintext: metadataPlaintext,
        );
        final encryptedContent = await _crypto.encryptBytes(
          key: targetBlobKey,
          plaintext: contentPlaintext,
        );
        reencryptedBlobs.add(
          EncryptedVaultBlob(
            blobId: blob.blobId,
            itemId: blob.itemId,
            metadataNonce: b64(encryptedMetadata.nonce),
            metadataCiphertext: b64(encryptedMetadata.ciphertext),
            metadataMac: b64(encryptedMetadata.mac),
            nonce: b64(encryptedContent.nonce),
            ciphertext: b64(encryptedContent.ciphertext),
            mac: b64(encryptedContent.mac),
            createdAt: blob.createdAt,
            updatedAt: blob.updatedAt,
            deletedAt: blob.deletedAt,
          ),
        );
      } finally {
        _zeroBytes(sourceBlobKey);
        _zeroBytes(targetBlobKey);
        _zeroBytes(metadataPlaintext);
        _zeroBytes(contentPlaintext);
      }
    }
    return List.unmodifiable(reencryptedBlobs);
  }

  Future<List<EncryptedVaultItem>> reencryptItemsForCurrentVault({
    required List<EncryptedVaultItem> items,
    required VaultMeta sourceMeta,
    required String sourcePassword,
    CancellationToken? cancellationToken,
  }) async {
    _ensureUnlocked();
    Uint8List? sourceDek;
    try {
      cancellationToken?.throwIfCancelled();
      sourceDek = await _decryptDekWithUnlockError(
        meta: sourceMeta,
        password: sourcePassword,
      );
      cancellationToken?.throwIfCancelled();
      final reencryptedItems = <EncryptedVaultItem>[];
      for (final item in items) {
        cancellationToken?.throwIfCancelled();
        Uint8List? plaintext;
        try {
          plaintext = await _crypto.decryptBytes(
            key: sourceDek,
            payload: EncryptedPayload(
              nonce: fromB64(item.nonce),
              ciphertext: fromB64(item.ciphertext),
              mac: fromB64(item.mac),
            ),
          );
          final encryptedPayload = await _session.encrypt(
            crypto: _crypto,
            plaintext: plaintext,
          );
          reencryptedItems.add(
            EncryptedVaultItem(
              id: item.id,
              nonce: b64(encryptedPayload.nonce),
              ciphertext: b64(encryptedPayload.ciphertext),
              mac: b64(encryptedPayload.mac),
              createdAt: item.createdAt,
              updatedAt: item.updatedAt,
              deletedAt: item.deletedAt,
            ),
          );
          cancellationToken?.throwIfCancelled();
        } finally {
          _zeroBytes(plaintext);
        }
      }

      return List.unmodifiable(reencryptedItems);
    } finally {
      _zeroBytes(sourceDek);
    }
  }

  Future<List<VaultItemImportIdentity>>
  decryptImportedItemIdentitiesForBackupImport({
    required List<EncryptedVaultItem> items,
    required VaultMeta sourceMeta,
    required String sourcePassword,
    CancellationToken? cancellationToken,
  }) async {
    Uint8List? sourceDek;
    try {
      cancellationToken?.throwIfCancelled();
      sourceDek = await _decryptDekWithUnlockError(
        meta: sourceMeta,
        password: sourcePassword,
      );
      cancellationToken?.throwIfCancelled();
      final identities = <VaultItemImportIdentity>[];
      for (final item in items) {
        cancellationToken?.throwIfCancelled();
        final entry = await _decryptEntryWithDek(item, sourceDek);
        cancellationToken?.throwIfCancelled();
        identities.add(
          VaultItemImportIdentity(
            id: item.id,
            title: entry.title,
            website: entry.website,
            username: entry.username,
          ),
        );
      }
      return List.unmodifiable(identities);
    } finally {
      _zeroBytes(sourceDek);
    }
  }

  Future<List<Map<String, Object?>>> reencryptHistoryForCurrentVault({
    required List<Map<String, Object?>> records,
    required VaultMeta sourceMeta,
    required String sourcePassword,
    CancellationToken? cancellationToken,
  }) async {
    _ensureUnlocked();
    Uint8List? sourceDek;
    try {
      cancellationToken?.throwIfCancelled();
      sourceDek = await _decryptDekWithUnlockError(
        meta: sourceMeta,
        password: sourcePassword,
      );
      cancellationToken?.throwIfCancelled();
      final reencryptedRecords = <Map<String, Object?>>[];
      for (final record in records) {
        cancellationToken?.throwIfCancelled();
        Uint8List? plaintext;
        try {
          plaintext = await _crypto.decryptBytes(
            key: sourceDek,
            payload: EncryptedPayload(
              nonce: fromB64(record['password_nonce'] as String),
              ciphertext: fromB64(record['encrypted_password'] as String),
              mac: fromB64(record['password_mac'] as String),
            ),
          );
          final encryptedPayload = await _session.encrypt(
            crypto: _crypto,
            plaintext: plaintext,
          );
          reencryptedRecords.add({
            'id': record['id'],
            'entry_id': record['entry_id'],
            'encrypted_password': b64(encryptedPayload.ciphertext),
            'password_nonce': b64(encryptedPayload.nonce),
            'password_mac': b64(encryptedPayload.mac),
            'recorded_at': record['recorded_at'],
          });
          cancellationToken?.throwIfCancelled();
        } finally {
          _zeroBytes(plaintext);
        }
      }

      return List.unmodifiable(reencryptedRecords);
    } finally {
      _zeroBytes(sourceDek);
    }
  }

  Future<List<EncryptedVaultBlob>> reencryptBlobsForCurrentVault({
    required List<EncryptedVaultBlob> blobs,
    required VaultMeta sourceMeta,
    required String sourcePassword,
    CancellationToken? cancellationToken,
  }) async {
    _ensureUnlocked();
    Uint8List? sourceDek;
    try {
      cancellationToken?.throwIfCancelled();
      sourceDek = await _decryptDekWithUnlockError(
        meta: sourceMeta,
        password: sourcePassword,
      );
      cancellationToken?.throwIfCancelled();
      return await _session.withDekCopy((targetDek) async {
        final reencryptedBlobs = <EncryptedVaultBlob>[];
        for (final blob in blobs) {
          cancellationToken?.throwIfCancelled();
          Uint8List? sourceBlobKey;
          Uint8List? targetBlobKey;
          Uint8List? metadataPlaintext;
          Uint8List? contentPlaintext;
          try {
            sourceBlobKey = await _deriveBlobKey(
              dek: sourceDek!,
              blobId: blob.blobId,
            );
            metadataPlaintext = await _crypto.decryptBytes(
              key: sourceBlobKey,
              payload: EncryptedPayload(
                nonce: fromB64(blob.metadataNonce),
                ciphertext: fromB64(blob.metadataCiphertext),
                mac: fromB64(blob.metadataMac),
              ),
            );
            contentPlaintext = await _crypto.decryptBytes(
              key: sourceBlobKey,
              payload: EncryptedPayload(
                nonce: fromB64(blob.nonce),
                ciphertext: fromB64(blob.ciphertext),
                mac: fromB64(blob.mac),
              ),
            );
            targetBlobKey = await _deriveBlobKey(
              dek: targetDek,
              blobId: blob.blobId,
            );
            final encryptedMetadata = await _crypto.encryptBytes(
              key: targetBlobKey,
              plaintext: metadataPlaintext,
            );
            final encryptedContent = await _crypto.encryptBytes(
              key: targetBlobKey,
              plaintext: contentPlaintext,
            );
            reencryptedBlobs.add(
              EncryptedVaultBlob(
                blobId: blob.blobId,
                itemId: blob.itemId,
                metadataNonce: b64(encryptedMetadata.nonce),
                metadataCiphertext: b64(encryptedMetadata.ciphertext),
                metadataMac: b64(encryptedMetadata.mac),
                nonce: b64(encryptedContent.nonce),
                ciphertext: b64(encryptedContent.ciphertext),
                mac: b64(encryptedContent.mac),
                createdAt: blob.createdAt,
                updatedAt: blob.updatedAt,
                deletedAt: blob.deletedAt,
              ),
            );
            cancellationToken?.throwIfCancelled();
          } finally {
            _zeroBytes(sourceBlobKey);
            _zeroBytes(targetBlobKey);
            _zeroBytes(metadataPlaintext);
            _zeroBytes(contentPlaintext);
          }
        }

        return List.unmodifiable(reencryptedBlobs);
      });
    } finally {
      _zeroBytes(sourceDek);
    }
  }

  Future<String> createItem(PasswordEntry entry) async {
    _ensureUnlocked();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();

    await _rewriteManifestForMutation(
      updatedAt: now,
      mutate: (txn, dek) async {
        final encryptedItem = await _encryptEntryWithDek(
          dek: dek,
          id: id,
          entry: entry,
          createdAt: now,
          updatedAt: now,
        );
        await txn.itemsDao.upsert(encryptedItem);
      },
    );
    return id;
  }

  Future<PasswordEntry> getItem(String id) async {
    _ensureUnlocked();
    await _verifyCurrentManifestWithActiveSession();
    final encryptedItem = await _requireActiveItem(id);
    return _decryptItem(encryptedItem);
  }

  Future<List<VaultListItem>> listItems({String query = ''}) async {
    _ensureUnlocked();
    await _verifyCurrentManifestWithActiveSession();
    final normalizedQuery = query.trim().toLowerCase();
    final items = await repository.itemsDao.activeItems();
    final results = <VaultListItem>[];

    for (final item in items) {
      final entry = await _decryptItem(item);
      if (normalizedQuery.isNotEmpty &&
          !_matchesQuery(entry: entry, query: normalizedQuery)) {
        continue;
      }
      results.add(
        VaultListItem(
          id: item.id,
          title: entry.title,
          website: entry.website,
          username: entry.username,
          tags: entry.tags,
          createdAt: item.createdAt,
          updatedAt: item.updatedAt,
        ),
      );
    }

    return List.unmodifiable(results);
  }

  Future<String> addBlob({
    required String itemId,
    required String displayName,
    required String mediaType,
    required Uint8List bytes,
  }) async {
    _ensureUnlocked();
    if (bytes.length > maxVaultBlobBytes) {
      throw VaultBlobTooLargeException(bytes.length);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final blobId = _uuid.v4();

    await _rewriteManifestForMutation(
      updatedAt: now,
      mutate: (txn, dek) async {
        await _requireActiveItemFrom(txn, itemId);
        final blobKey = await _deriveBlobKey(dek: dek, blobId: blobId);
        try {
          final metadata = {
            'version': 1,
            'display_name': displayName,
            'media_type': mediaType,
            'size_bytes': bytes.length,
          };
          final encryptedMetadata = await _crypto.encryptBytes(
            key: blobKey,
            plaintext: utf8.encode(jsonEncode(metadata)),
          );
          final encryptedContent = await _crypto.encryptBytes(
            key: blobKey,
            plaintext: bytes,
          );
          await txn.blobsDao.upsert(
            EncryptedVaultBlob(
              blobId: blobId,
              itemId: itemId,
              metadataNonce: b64(encryptedMetadata.nonce),
              metadataCiphertext: b64(encryptedMetadata.ciphertext),
              metadataMac: b64(encryptedMetadata.mac),
              nonce: b64(encryptedContent.nonce),
              ciphertext: b64(encryptedContent.ciphertext),
              mac: b64(encryptedContent.mac),
              createdAt: now,
              updatedAt: now,
            ),
          );
        } finally {
          _zeroBytes(blobKey);
        }
      },
    );
    return blobId;
  }

  Future<List<VaultBlobListItem>> listBlobs(String itemId) async {
    _ensureUnlocked();
    await _verifyCurrentManifestWithActiveSession();
    final blobs = await repository.blobsDao.activeByItem(itemId);
    final results = <VaultBlobListItem>[];
    for (final blob in blobs) {
      results.add(await _blobListItemFromEncrypted(blob));
    }
    return List.unmodifiable(results);
  }

  Future<DecryptedVaultBlob> openBlob(String blobId) async {
    _ensureUnlocked();
    await _verifyCurrentManifestWithActiveSession();
    final blob = await repository.blobsDao.byBlobId(blobId);
    if (blob == null || blob.deletedAt != null) {
      throw VaultItemNotFoundException(blobId);
    }
    await _requireActiveItem(blob.itemId);

    return _session.withDekCopy((dek) async {
      final blobKey = await _deriveBlobKey(dek: dek, blobId: blob.blobId);
      Uint8List? metadataBytes;
      try {
        metadataBytes = await _crypto.decryptBytes(
          key: blobKey,
          payload: EncryptedPayload(
            nonce: fromB64(blob.metadataNonce),
            ciphertext: fromB64(blob.metadataCiphertext),
            mac: fromB64(blob.metadataMac),
          ),
        );
        final metadata = _decodeBlobMetadata(metadataBytes);
        final clearBytes = await _crypto.decryptBytes(
          key: blobKey,
          payload: EncryptedPayload(
            nonce: fromB64(blob.nonce),
            ciphertext: fromB64(blob.ciphertext),
            mac: fromB64(blob.mac),
          ),
        );
        return DecryptedVaultBlob(
          blobId: blob.blobId,
          itemId: blob.itemId,
          displayName: metadata.displayName,
          mediaType: metadata.mediaType,
          bytes: clearBytes,
          createdAt: blob.createdAt,
          updatedAt: blob.updatedAt,
        );
      } on CryptoException {
        throw const VaultIntegrityException(
          'Blob payload could not be authenticated',
        );
      } on FormatException {
        throw const VaultIntegrityException('Blob metadata is malformed');
      } finally {
        _zeroBytes(metadataBytes);
        _zeroBytes(blobKey);
      }
    });
  }

  Future<void> deleteBlob(String blobId) async {
    _ensureUnlocked();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _rewriteManifestForMutation(
      updatedAt: now,
      mutate: (txn, _) async {
        final blob = await txn.blobsDao.byBlobId(blobId);
        if (blob == null || blob.deletedAt != null) {
          throw VaultItemNotFoundException(blobId);
        }
        await _requireActiveItemFrom(txn, blob.itemId);
        try {
          await txn.blobsDao.softDelete(blobId, now);
        } on StateError {
          throw VaultItemNotFoundException(blobId);
        }
      },
    );
  }

  Future<void> updateItem(String id, PasswordEntry entry) async {
    _ensureUnlocked();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _rewriteManifestForMutation(
      updatedAt: now,
      mutate: (txn, dek) async {
        final existing = await _requireActiveItemFrom(txn, id);
        final oldEntry = await _decryptEntryWithDek(existing, dek);
        if (oldEntry.password != entry.password) {
          await _archivePasswordHistory(
            txn: txn,
            entryId: id,
            dek: dek,
            oldPassword: oldEntry.password,
          );
        }
        final updatedItem = await _encryptEntryWithDek(
          dek: dek,
          id: id,
          entry: entry,
          createdAt: existing.createdAt,
          updatedAt: now,
        );
        final updated = await txn.itemsDao.updateActive(updatedItem);
        if (!updated) {
          throw VaultItemNotFoundException(id);
        }
      },
    );
  }

  Future<void> deleteItem(String id) async {
    _ensureUnlocked();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _rewriteManifestForMutation(
      updatedAt: now,
      mutate: (txn, _) async {
        await _requireActiveItemFrom(txn, id);
        try {
          await txn.itemsDao.softDelete(id, now);
          await txn.blobsDao.softDeleteForItem(id, now);
        } on StateError {
          throw VaultItemNotFoundException(id);
        }
      },
    );
  }

  Future<List<VaultListItem>> listDeletedItems() async {
    _ensureUnlocked();
    await _verifyCurrentManifestWithActiveSession();
    final items = await repository.itemsDao.deletedItems();
    final results = <VaultListItem>[];
    for (final item in items) {
      final entry = await _decryptItem(item);
      results.add(
        VaultListItem(
          id: item.id,
          title: entry.title,
          website: entry.website,
          username: entry.username,
          tags: entry.tags,
          createdAt: item.createdAt,
          updatedAt: item.updatedAt,
          deletedAt: item.deletedAt,
        ),
      );
    }
    return List.unmodifiable(results);
  }

  Future<void> restoreItem(String id) async {
    _ensureUnlocked();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _rewriteManifestForMutation(
      updatedAt: now,
      mutate: (txn, _) async {
        final item = await txn.itemsDao.byId(id);
        if (item == null || item.deletedAt == null) {
          throw VaultItemNotFoundException(id);
        }
        final restored = await txn.itemsDao.restoreItem(id, updatedAt: now);
        if (!restored) {
          throw VaultItemNotFoundException(id);
        }
        await txn.blobsDao.restoreForItem(
          id,
          updatedAt: now,
          deletedAt: item.deletedAt,
        );
      },
    );
  }

  Future<void> permanentlyDeleteItem(String id) async {
    _ensureUnlocked();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _rewriteManifestForMutation(
      updatedAt: now,
      mutate: (txn, _) async {
        final item = await txn.itemsDao.byId(id);
        if (item == null || item.deletedAt == null) {
          throw VaultItemNotFoundException(id);
        }
        await txn.blobsDao.hardDeleteForItem(id);
        await txn.itemsDao.hardDelete(id);
        await txn.historyDao?.deleteAllForEntry(id);
      },
    );
  }

  Future<void> emptyTrash() async {
    _ensureUnlocked();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _rewriteManifestForMutation(
      updatedAt: now,
      mutate: (txn, _) async {
        final deletedItems = await txn.itemsDao.deletedItems();
        for (final item in deletedItems) {
          await txn.blobsDao.hardDeleteForItem(item.id);
        }
        await txn.historyDao?.deleteAllForDeletedEntries();
        await txn.itemsDao.hardDeleteAllDeleted();
      },
    );
  }

  Future<int> deletedItemCount() async {
    _ensureUnlocked();
    await _verifyCurrentManifestWithActiveSession();
    return repository.itemsDao.deletedCount();
  }

  Future<List<Map<String, dynamic>>> listPasswordHistory(String entryId) async {
    try {
      _ensureUnlocked();
      await _verifyCurrentManifestWithActiveSession();
      final historyDao = repository.historyDao;
      if (historyDao == null) return const [];
      final records = await historyDao.byEntryId(entryId);
      return await _session.withDekCopy((dek) async {
        final results = <Map<String, dynamic>>[];
        for (final r in records) {
          Uint8List? passwordBytes;
          try {
            passwordBytes = await _crypto.decryptBytes(
              key: dek,
              payload: EncryptedPayload(
                nonce: fromB64(r['password_nonce'] as String),
                ciphertext: fromB64(r['encrypted_password'] as String),
                mac: fromB64(r['password_mac'] as String),
              ),
            );
            final password = _decodeHistoryPassword(
              record: r,
              clearBytes: passwordBytes,
            );
            results.add({
              'id': r['id'],
              'password': password,
              'recordedAt': r['recorded_at'],
              'entryId': r['entry_id'],
            });
          } catch (_) {
            throw const VaultIntegrityException(
              'Password history integrity check failed',
            );
          } finally {
            _zeroBytes(passwordBytes);
          }
        }
        return results;
      });
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  Future<void> restorePassword(String entryId, int historyId) async {
    try {
      _ensureUnlocked();
      final historyDao = repository.historyDao;
      if (historyDao == null) return;
      final historyRecord = await historyDao.byId(historyId);
      if (historyRecord == null) {
        throw VaultItemNotFoundException(entryId);
      }
      if (historyRecord['entry_id'] != entryId) {
        throw const VaultIntegrityException(
          'Password history record does not belong to this vault item',
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await _rewriteManifestForMutation(
        updatedAt: now,
        mutate: (txn, dek) async {
          Uint8List? passwordBytes;
          final String oldPassword;
          try {
            passwordBytes = await _crypto.decryptBytes(
              key: dek,
              payload: EncryptedPayload(
                nonce: fromB64(historyRecord['password_nonce'] as String),
                ciphertext: fromB64(
                  historyRecord['encrypted_password'] as String,
                ),
                mac: fromB64(historyRecord['password_mac'] as String),
              ),
            );
            oldPassword = _decodeHistoryPassword(
              record: historyRecord,
              clearBytes: passwordBytes,
            );
          } finally {
            _zeroBytes(passwordBytes);
          }

          final existing = await _requireActiveItemFrom(txn, entryId);
          final currentEntry = await _decryptEntryWithDek(existing, dek);

          if (currentEntry.password != oldPassword) {
            await _archivePasswordHistory(
              txn: txn,
              entryId: entryId,
              dek: dek,
              oldPassword: currentEntry.password,
            );
          }

          final restoredEntry = PasswordEntry(
            title: currentEntry.title,
            website: currentEntry.website,
            username: currentEntry.username,
            password: oldPassword,
            notes: currentEntry.notes,
            tags: currentEntry.tags,
            totpSecret: currentEntry.totpSecret,
          );

          final updatedItem = await _encryptEntryWithDek(
            dek: dek,
            id: entryId,
            entry: restoredEntry,
            createdAt: existing.createdAt,
            updatedAt: now,
          );
          final updated = await txn.itemsDao.updateActive(updatedItem);
          if (!updated) {
            throw VaultItemNotFoundException(entryId);
          }

          await txn.historyDao?.delete(historyId);
        },
      );
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  Future<Map<String, String?>> _decryptItemForHealth(
    EncryptedVaultItem item,
    Uint8List dek,
  ) async {
    Uint8List? clearBytes;
    try {
      clearBytes = await _crypto.decryptBytes(
        key: dek,
        payload: EncryptedPayload(
          nonce: fromB64(item.nonce),
          ciphertext: fromB64(item.ciphertext),
          mac: fromB64(item.mac),
        ),
      );
      final decoded = jsonDecode(utf8.decode(clearBytes));
      if (decoded is! Map) {
        throw const VaultIntegrityException('Health item payload is malformed');
      }
      final entry = PasswordEntry.fromJson(Map<String, Object?>.from(decoded));
      return {
        'id': item.id,
        'title': entry.title,
        'username': entry.username,
        'password': entry.password,
        'website': entry.website,
        'updatedAt': '${item.updatedAt}',
        'createdAt': '${item.createdAt}',
      };
    } finally {
      _zeroBytes(clearBytes);
    }
  }

  Future<HealthReport> analyzePasswordHealth({
    required PasswordHealthService healthService,
  }) async {
    try {
      _ensureUnlocked();
      await _verifyCurrentManifestWithActiveSession();
      final items = await repository.itemsDao.allItemsForManifest();
      final activeItems = items.where((i) => i.deletedAt == null).toList();

      final decryptedItems = await _session.withDekCopy((dek) async {
        final results = <Map<String, String?>>[];
        for (final item in activeItems) {
          try {
            results.add(await _decryptItemForHealth(item, dek));
          } on VaultIntegrityException {
            rethrow;
          } on Object {
            throw const VaultIntegrityException(
              'Health item payload could not be processed',
            );
          }
        }
        return results;
      });

      return healthService.analyze(decryptedItems: decryptedItems);
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  Future<List<TotpListItem>> listTotpItems() async {
    try {
      _ensureUnlocked();
      await _verifyCurrentManifestWithActiveSession();
      final items = await repository.itemsDao.allItemsForManifest();
      final active = items.where((i) => i.deletedAt == null).toList();

      return await _session.withDekCopy((dek) async {
        final results = <TotpListItem>[];
        for (final item in active) {
          Uint8List? clearBytes;
          try {
            clearBytes = await _crypto.decryptBytes(
              key: dek,
              payload: EncryptedPayload(
                nonce: fromB64(item.nonce),
                ciphertext: fromB64(item.ciphertext),
                mac: fromB64(item.mac),
              ),
            );
            final decoded = jsonDecode(utf8.decode(clearBytes));
            if (decoded is! Map) {
              throw const VaultIntegrityException(
                'TOTP item payload is malformed',
              );
            }
            final entry = PasswordEntry.fromJson(
              Map<String, Object?>.from(decoded),
            );
            if (entry.totpSecret == null || entry.totpSecret!.isEmpty) {
              continue;
            }
            results.add(
              TotpListItem(
                id: item.id,
                title: entry.title,
                username: entry.username,
                totpSecret: entry.totpSecret!,
              ),
            );
          } on VaultIntegrityException {
            rethrow;
          } on Object {
            throw const VaultIntegrityException(
              'TOTP item payload could not be processed',
            );
          } finally {
            _zeroBytes(clearBytes);
          }
        }
        return results;
      });
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  Future<List<String>> allTags() async {
    try {
      _ensureUnlocked();
      await _verifyCurrentManifestWithActiveSession();
      final items = await repository.itemsDao.allItemsForManifest();
      final active = items.where((i) => i.deletedAt == null).toList();
      final tags = <String>{};
      return await _session.withDekCopy((dek) async {
        for (final item in active) {
          Uint8List? clearBytes;
          try {
            clearBytes = await _crypto.decryptBytes(
              key: dek,
              payload: EncryptedPayload(
                nonce: fromB64(item.nonce),
                ciphertext: fromB64(item.ciphertext),
                mac: fromB64(item.mac),
              ),
            );
            final decoded = jsonDecode(utf8.decode(clearBytes));
            if (decoded is! Map) {
              throw const VaultIntegrityException(
                'Tag item payload is malformed',
              );
            }
            final entry = PasswordEntry.fromJson(
              Map<String, Object?>.from(decoded),
            );
            tags.addAll(entry.tags);
          } on VaultIntegrityException {
            rethrow;
          } on Object {
            throw const VaultIntegrityException(
              'Tag item payload could not be processed',
            );
          } finally {
            _zeroBytes(clearBytes);
          }
        }
        final sorted = tags.toList()..sort();
        return sorted;
      });
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  Future<void> renameTag(String oldTag, String newTag) async {
    _ensureUnlocked();
    if (oldTag == newTag) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    await _rewriteManifestForMutation(
      updatedAt: now,
      mutate: (txn, dek) async {
        final items = await txn.itemsDao.allItemsForManifest();
        for (final item in items) {
          if (item.deletedAt != null) continue;
          Uint8List? clearBytes;
          try {
            clearBytes = await _crypto.decryptBytes(
              key: dek,
              payload: EncryptedPayload(
                nonce: fromB64(item.nonce),
                ciphertext: fromB64(item.ciphertext),
                mac: fromB64(item.mac),
              ),
            );
            final decoded = jsonDecode(utf8.decode(clearBytes));
            if (decoded is! Map) {
              throw const VaultIntegrityException(
                'Tag rename item payload is malformed',
              );
            }
            final entry = PasswordEntry.fromJson(
              Map<String, Object?>.from(decoded),
            );
            if (!entry.tags.contains(oldTag)) continue;
            final newTags = entry.tags
                .map((t) => t == oldTag ? newTag : t)
                .toList();
            final updatedEntry = PasswordEntry(
              title: entry.title,
              website: entry.website,
              username: entry.username,
              password: entry.password,
              notes: entry.notes,
              tags: newTags,
              totpSecret: entry.totpSecret,
            );
            final updatedItem = await _encryptEntryWithDek(
              dek: dek,
              id: item.id,
              entry: updatedEntry,
              createdAt: item.createdAt,
              updatedAt: now,
            );
            await txn.itemsDao.updateActive(updatedItem);
          } on VaultIntegrityException {
            rethrow;
          } on Object {
            throw const VaultIntegrityException(
              'Tag rename failed because a vault item could not be processed',
            );
          } finally {
            _zeroBytes(clearBytes);
          }
        }
      },
    );
  }

  Future<void> deleteTag(String tag) async {
    _ensureUnlocked();
    final now = DateTime.now().millisecondsSinceEpoch;

    await _rewriteManifestForMutation(
      updatedAt: now,
      mutate: (txn, dek) async {
        final items = await txn.itemsDao.allItemsForManifest();
        for (final item in items) {
          if (item.deletedAt != null) continue;
          Uint8List? clearBytes;
          try {
            clearBytes = await _crypto.decryptBytes(
              key: dek,
              payload: EncryptedPayload(
                nonce: fromB64(item.nonce),
                ciphertext: fromB64(item.ciphertext),
                mac: fromB64(item.mac),
              ),
            );
            final decoded = jsonDecode(utf8.decode(clearBytes));
            if (decoded is! Map) {
              throw const VaultIntegrityException(
                'Tag delete item payload is malformed',
              );
            }
            final entry = PasswordEntry.fromJson(
              Map<String, Object?>.from(decoded),
            );
            if (!entry.tags.contains(tag)) continue;
            final newTags = entry.tags.where((t) => t != tag).toList();
            final updatedEntry = PasswordEntry(
              title: entry.title,
              website: entry.website,
              username: entry.username,
              password: entry.password,
              notes: entry.notes,
              tags: newTags,
              totpSecret: entry.totpSecret,
            );
            final updatedItem = await _encryptEntryWithDek(
              dek: dek,
              id: item.id,
              entry: updatedEntry,
              createdAt: item.createdAt,
              updatedAt: now,
            );
            await txn.itemsDao.updateActive(updatedItem);
          } on VaultIntegrityException {
            rethrow;
          } on Object {
            throw const VaultIntegrityException(
              'Tag delete failed because a vault item could not be processed',
            );
          } finally {
            _zeroBytes(clearBytes);
          }
        }
      },
    );
  }

  Future<VaultMeta> _requireVaultMeta() async {
    final meta = await repository.metaDao.get();
    if (meta == null) {
      throw StateError('Vault has not been created');
    }
    return meta;
  }

  Future<Uint8List> _decryptDek({
    required VaultMeta meta,
    required String password,
  }) async {
    Uint8List? kek;
    try {
      kek = await _kdf.deriveKey(
        password: password,
        salt: fromB64(meta.salt),
        params: meta.kdfParams,
      );
      return await _crypto.decryptBytes(
        key: kek,
        payload: EncryptedPayload(
          nonce: fromB64(meta.encryptedDekByMasterNonce),
          ciphertext: fromB64(meta.encryptedDekByMaster),
          mac: fromB64(meta.encryptedDekByMasterMac),
        ),
      );
    } finally {
      _zeroBytes(kek);
    }
  }

  Future<Uint8List> _decryptDekWithUnlockError({
    required VaultMeta meta,
    required String password,
  }) async {
    try {
      return await _decryptDek(meta: meta, password: password);
    } on CryptoException {
      throw const VaultUnlockException('Invalid master password');
    }
  }

  Future<VaultManifest> _verifyExistingManifest({
    required VaultMeta meta,
    required Uint8List dek,
  }) async {
    final manifest = await _readManifestForIntegrity(repository);
    if (manifest == null) {
      throw const VaultIntegrityException();
    }
    final items = await _readItemsForManifest(repository);
    final blobs = await _readBlobsForManifest(repository);
    final historyRecords = await _readHistoryForManifest(repository);
    await _manifestService.verifyManifest(
      dek: dek,
      meta: meta,
      items: items,
      blobs: blobs,
      historyRecords: historyRecords,
      manifest: manifest,
    );
    return manifest;
  }

  Future<void> _verifyAnchorForManifest({
    required VaultMeta meta,
    required VaultManifest manifest,
    required bool allowMissingAnchor,
    bool allowNewerManifest = false,
  }) async {
    try {
      final result = await _anchorService.verifyAgainstAnchor(
        vaultId: meta.id,
        manifest: manifest,
        allowNewerManifest: allowNewerManifest,
      );
      if (result == VaultAnchorVerificationResult.missing &&
          !allowMissingAnchor) {
        throw const VaultIntegrityException();
      }
    } on VaultAnchorException {
      throw const VaultIntegrityException();
    }
  }

  Future<void> _writeAnchorForManifest({
    required VaultMeta meta,
    required VaultManifest manifest,
  }) async {
    try {
      await _anchorService.writeAcceptedManifest(
        vaultId: meta.id,
        manifest: manifest,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } on VaultAnchorException {
      throw const VaultIntegrityException();
    }
  }

  Future<void> _deleteAnchorForMeta(VaultMeta? meta) async {
    if (meta == null) {
      return;
    }
    try {
      await _anchorService.deleteAnchor(vaultId: meta.id);
    } on VaultAnchorException {
      throw const VaultIntegrityException();
    }
  }

  Future<VaultManifest> _saveManifestForMetadataUpdate({
    required VaultRepository txn,
    required Uint8List dek,
    required VaultMeta currentMeta,
    required VaultMeta updatedMeta,
    required int updatedAt,
  }) async {
    final previous = await _readManifestForIntegrity(txn);
    if (previous == null) {
      throw const VaultIntegrityException();
    }
    final items = await _readItemsForManifest(txn);
    final blobs = await _readBlobsForManifest(txn);
    final historyRecords = await _readHistoryForManifest(txn);
    await _manifestService.verifyManifest(
      dek: dek,
      meta: currentMeta,
      items: items,
      blobs: blobs,
      historyRecords: historyRecords,
      manifest: previous,
    );
    await _verifyAnchorForManifest(
      meta: currentMeta,
      manifest: previous,
      allowMissingAnchor: false,
    );
    final manifest = await _manifestService.createManifest(
      dek: dek,
      meta: updatedMeta,
      items: items,
      blobs: blobs,
      historyRecords: historyRecords,
      previous: previous,
      updatedAt: updatedAt,
    );
    await txn.manifestDao.save(manifest);
    return manifest;
  }

  Future<T> _rewriteManifestForMutation<T>({
    required int updatedAt,
    required Future<T> Function(VaultRepository txn, Uint8List dek) mutate,
  }) async {
    try {
      final rewrite = await _session.withDekCopy((dek) async {
        return repository.transaction<_ManifestMutationResult<T>>((txn) async {
          final currentMeta = await txn.metaDao.get();
          if (currentMeta == null) {
            throw StateError('Vault has not been created');
          }
          final previous = await _readManifestForIntegrity(txn);
          if (previous == null) {
            throw const VaultIntegrityException();
          }
          final currentItems = await _readItemsForManifest(txn);
          final currentBlobs = await _readBlobsForManifest(txn);
          final currentHistory = await _readHistoryForManifest(txn);
          await _manifestService.verifyManifest(
            dek: dek,
            meta: currentMeta,
            items: currentItems,
            blobs: currentBlobs,
            historyRecords: currentHistory,
            manifest: previous,
          );
          await _verifyAnchorForManifest(
            meta: currentMeta,
            manifest: previous,
            allowMissingAnchor: false,
          );

          final result = await mutate(txn, dek);
          final updatedMeta = await txn.metaDao.get();
          if (updatedMeta == null) {
            throw StateError('Vault has not been created');
          }
          final updatedItems = await _readItemsForManifest(txn);
          final updatedBlobs = await _readBlobsForManifest(txn);
          final updatedHistory = await _readHistoryForManifest(txn);
          final manifest = await _manifestService.createManifest(
            dek: dek,
            meta: updatedMeta,
            items: updatedItems,
            blobs: updatedBlobs,
            historyRecords: updatedHistory,
            previous: previous,
            updatedAt: updatedAt,
          );
          await txn.manifestDao.save(manifest);
          return _ManifestMutationResult<T>(
            result: result,
            meta: updatedMeta,
            manifest: manifest,
          );
        });
      });
      await _writeAnchorForManifest(
        meta: rewrite.meta,
        manifest: rewrite.manifest,
      );
      return rewrite.result;
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  Future<VaultManifest?> _readManifestForIntegrity(
    VaultRepository repository,
  ) async {
    try {
      return await repository.manifestDao.get();
    } on FormatException {
      throw const VaultIntegrityException();
    } on StateError {
      throw const VaultIntegrityException();
    } on ArgumentError {
      throw const VaultIntegrityException();
    }
  }

  Future<List<EncryptedVaultItem>> _readItemsForManifest(
    VaultRepository repository,
  ) async {
    try {
      return await repository.itemsDao.allItemsForManifest();
    } on FormatException {
      throw const VaultIntegrityException();
    } on StateError {
      throw const VaultIntegrityException();
    } on ArgumentError {
      throw const VaultIntegrityException();
    }
  }

  Future<List<EncryptedVaultBlob>> _readBlobsForManifest(
    VaultRepository repository,
  ) async {
    try {
      return await repository.blobsDao.allForManifest();
    } on FormatException {
      throw const VaultIntegrityException();
    } on StateError {
      throw const VaultIntegrityException();
    } on ArgumentError {
      throw const VaultIntegrityException();
    }
  }

  Future<List<Map<String, Object?>>> _readHistoryForManifest(
    VaultRepository repository,
  ) async {
    try {
      final historyDao = repository.historyDao;
      if (historyDao == null) return const [];
      final rows = await historyDao.allRowsForManifest();
      return rows
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
    } on FormatException {
      throw const VaultIntegrityException();
    } on StateError {
      throw const VaultIntegrityException();
    } on ArgumentError {
      throw const VaultIntegrityException();
    }
  }

  bool _isIntegrityReadFailure(Object error) {
    return error is VaultIntegrityException ||
        error is FormatException ||
        error is StateError ||
        error is ArgumentError;
  }

  Future<Uint8List> _deriveBlobKey({
    required Uint8List dek,
    required String blobId,
  }) async {
    final key = await _blobHkdf.deriveKey(
      secretKey: SecretKey(dek),
      info: utf8.encode('$_blobKeyInfoPrefix$blobId'),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  Future<VaultBlobListItem> _blobListItemFromEncrypted(
    EncryptedVaultBlob blob,
  ) async {
    return _session.withDekCopy((dek) async {
      final blobKey = await _deriveBlobKey(dek: dek, blobId: blob.blobId);
      Uint8List? metadataBytes;
      try {
        metadataBytes = await _crypto.decryptBytes(
          key: blobKey,
          payload: EncryptedPayload(
            nonce: fromB64(blob.metadataNonce),
            ciphertext: fromB64(blob.metadataCiphertext),
            mac: fromB64(blob.metadataMac),
          ),
        );
        final metadata = _decodeBlobMetadata(metadataBytes);
        return VaultBlobListItem(
          blobId: blob.blobId,
          itemId: blob.itemId,
          displayName: metadata.displayName,
          mediaType: metadata.mediaType,
          sizeBytes: metadata.sizeBytes,
          createdAt: blob.createdAt,
          updatedAt: blob.updatedAt,
        );
      } on CryptoException {
        throw const VaultIntegrityException(
          'Blob metadata could not be authenticated',
        );
      } on FormatException {
        throw const VaultIntegrityException('Blob metadata is malformed');
      } finally {
        _zeroBytes(metadataBytes);
        _zeroBytes(blobKey);
      }
    });
  }

  _BlobMetadata _decodeBlobMetadata(Uint8List clearBytes) {
    final decoded = jsonDecode(utf8.decode(clearBytes));
    if (decoded is! Map) {
      throw const FormatException('Invalid blob metadata');
    }
    final payload = Map<String, Object?>.from(decoded);
    if (payload['version'] != 1 ||
        payload['display_name'] is! String ||
        payload['media_type'] is! String ||
        payload['size_bytes'] is! int) {
      throw const FormatException('Invalid blob metadata');
    }
    return _BlobMetadata(
      displayName: payload['display_name']! as String,
      mediaType: payload['media_type']! as String,
      sizeBytes: payload['size_bytes']! as int,
    );
  }

  Future<void> _withDekForBiometricDisable({
    required BiometricService biometricService,
    required Future<void> Function(Uint8List dek) action,
  }) async {
    if (_session.isUnlocked) {
      await _session.withDekCopy(action);
      return;
    }

    final result = await biometricService.unlock();
    final dek = result.dek;
    if (result.status != BiometricUnlockStatus.unlocked || dek == null) {
      throw const VaultUnlockException('Master password is required');
    }

    try {
      await action(dek);
    } finally {
      _zeroBytes(dek);
    }
  }

  void _ensureUnlocked() {
    _session.ensureUnlocked();
  }

  Future<EncryptedVaultItem> _requireActiveItem(String id) async {
    return _requireActiveItemFrom(repository, id);
  }

  Future<EncryptedVaultItem> _requireActiveItemFrom(
    VaultRepository repository,
    String id,
  ) async {
    final encryptedItem = await repository.itemsDao.byId(id);
    if (encryptedItem == null || encryptedItem.deletedAt != null) {
      throw VaultItemNotFoundException(id);
    }
    return encryptedItem;
  }

  Future<EncryptedVaultItem> _encryptEntryWithDek({
    required Uint8List dek,
    required String id,
    required PasswordEntry entry,
    required int createdAt,
    required int updatedAt,
  }) async {
    final encryptedPayload = await _crypto.encryptBytes(
      key: dek,
      plaintext: utf8.encode(jsonEncode(entry.toJson())),
    );

    return EncryptedVaultItem(
      id: id,
      nonce: b64(encryptedPayload.nonce),
      ciphertext: b64(encryptedPayload.ciphertext),
      mac: b64(encryptedPayload.mac),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Future<PasswordEntry> _decryptItem(EncryptedVaultItem item) async {
    Uint8List? clearBytes;
    try {
      clearBytes = await _session.decrypt(
        crypto: _crypto,
        payload: EncryptedPayload(
          nonce: fromB64(item.nonce),
          ciphertext: fromB64(item.ciphertext),
          mac: fromB64(item.mac),
        ),
      );
      final decoded = jsonDecode(utf8.decode(clearBytes));
      if (decoded is! Map) {
        throw const FormatException('Invalid vault item payload');
      }

      return PasswordEntry.fromJson(Map<String, Object?>.from(decoded));
    } finally {
      _zeroBytes(clearBytes);
    }
  }

  Future<PasswordEntry> _decryptEntryWithDek(
    EncryptedVaultItem item,
    Uint8List dek,
  ) async {
    Uint8List? clearBytes;
    try {
      clearBytes = await _crypto.decryptBytes(
        key: dek,
        payload: EncryptedPayload(
          nonce: fromB64(item.nonce),
          ciphertext: fromB64(item.ciphertext),
          mac: fromB64(item.mac),
        ),
      );
      final decoded = jsonDecode(utf8.decode(clearBytes));
      if (decoded is! Map) {
        throw const FormatException('Invalid vault item payload');
      }

      return PasswordEntry.fromJson(Map<String, Object?>.from(decoded));
    } finally {
      _zeroBytes(clearBytes);
    }
  }

  Future<void> _archivePasswordHistory({
    required VaultRepository txn,
    required String entryId,
    required Uint8List dek,
    required String oldPassword,
  }) async {
    final historyDao = txn.historyDao;
    if (historyDao == null) return;
    final recordedAt = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      'version': 1,
      'entry_id': entryId,
      'password': oldPassword,
      'recorded_at': recordedAt,
    };
    final encryptedPayload = await _crypto.encryptBytes(
      key: dek,
      plaintext: utf8.encode(jsonEncode(payload)),
    );
    await historyDao.insert(
      entryId,
      b64(encryptedPayload.ciphertext),
      b64(encryptedPayload.nonce),
      b64(encryptedPayload.mac),
      recordedAt,
    );
  }

  String _decodeHistoryPassword({
    required Map<String, dynamic> record,
    required Uint8List clearBytes,
  }) {
    final text = utf8.decode(clearBytes);
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return text;
      }
      final payload = Map<String, Object?>.from(decoded);
      if (!payload.containsKey('version')) {
        return text;
      }
      if (payload['version'] != 1 ||
          payload['entry_id'] != record['entry_id'] ||
          payload['recorded_at'] != record['recorded_at'] ||
          payload['password'] is! String) {
        throw const VaultIntegrityException(
          'Password history payload does not match its record',
        );
      }
      return payload['password']! as String;
    } on FormatException {
      return text;
    } on ArgumentError {
      throw const VaultIntegrityException(
        'Password history payload is malformed',
      );
    }
  }

  Future<void> _verifyCurrentManifestWithActiveSession() async {
    try {
      await _session.withDekCopy((dek) async {
        final meta = await _requireVaultMeta();
        final manifest = await _verifyExistingManifest(meta: meta, dek: dek);
        await _verifyAnchorForManifest(
          meta: meta,
          manifest: manifest,
          allowMissingAnchor: false,
        );
      });
    } on VaultIntegrityException {
      _session.lock();
      rethrow;
    }
  }

  bool _matchesQuery({required PasswordEntry entry, required String query}) {
    final searchableValues = [
      entry.title,
      entry.website,
      entry.username,
      entry.notes,
      ...entry.tags,
    ];

    return searchableValues.any((value) => value.toLowerCase().contains(query));
  }

  void _zeroBytes(Uint8List? bytes) {
    if (bytes == null) {
      return;
    }
    bytes.fillRange(0, bytes.length, 0);
  }
}

class _ManifestMutationResult<T> {
  const _ManifestMutationResult({
    required this.result,
    required this.meta,
    required this.manifest,
  });

  final T result;
  final VaultMeta meta;
  final VaultManifest manifest;
}

class _BlobMetadata {
  const _BlobMetadata({
    required this.displayName,
    required this.mediaType,
    required this.sizeBytes,
  });

  final String displayName;
  final String mediaType;
  final int sizeBytes;
}
