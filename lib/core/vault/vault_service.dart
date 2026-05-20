import 'dart:convert';
import 'dart:typed_data';

import 'package:secure_box/core/biometric/biometric_service.dart';
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
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:secure_box/data/models/vault_meta.dart';
import 'package:uuid/uuid.dart';

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

class VaultListItem {
  VaultListItem({
    required this.id,
    required this.title,
    required this.website,
    required this.username,
    required List<String> tags,
    required this.createdAt,
    required this.updatedAt,
  }) : tags = List.unmodifiable(tags);

  final String id;
  final String title;
  final String website;
  final String username;
  final List<String> tags;
  final int createdAt;
  final int updatedAt;
}

class TotpListItem {
  TotpListItem({required this.id, required this.title, required this.username, required this.totpSecret});
  final String id;
  final String title;
  final String username;
  final String totpSecret;
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
      await _manifestService.verifyManifest(
        dek: dek,
        meta: meta,
        items: items,
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
      return false;
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
          await biometricService.disable();
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
        await _manifestService.verifyManifest(
          dek: dek,
          meta: meta,
          items: currentItems,
          manifest: manifest,
        );
        return _manifestService.createManifest(
          dek: dek,
          meta: meta,
          items: items,
          previous: manifest,
          updatedAt: updatedAt,
        );
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
  }) async {
    Uint8List? dek;
    try {
      dek = await _decryptDekWithUnlockError(
        meta: meta,
        password: masterPassword,
      );
      await _manifestService.verifyManifest(
        dek: dek,
        meta: meta,
        items: items,
        manifest: manifest,
      );
    } finally {
      _zeroBytes(dek);
    }
  }

  Future<VaultManifest> createManifestForImportedVault({
    required String masterPassword,
    required VaultMeta meta,
    required List<EncryptedVaultItem> items,
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
        await _manifestService.verifyManifest(
          dek: dek,
          meta: currentMeta,
          items: items,
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
        final manifest = await _manifestService.createManifest(
          dek: dek,
          meta: currentMeta,
          items: items,
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

  Future<List<EncryptedVaultItem>> reencryptItemsForCurrentVault({
    required List<EncryptedVaultItem> items,
    required VaultMeta sourceMeta,
    required String sourcePassword,
  }) async {
    _ensureUnlocked();
    Uint8List? sourceDek;
    try {
      sourceDek = await _decryptDekWithUnlockError(
        meta: sourceMeta,
        password: sourcePassword,
      );
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
        } finally {
          _zeroBytes(plaintext);
        }
      }

      return List.unmodifiable(reencryptedItems);
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

  Future<void> updateItem(String id, PasswordEntry entry) async {
    _ensureUnlocked();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _rewriteManifestForMutation(
      updatedAt: now,
      mutate: (txn, dek) async {
        final existing = await _requireActiveItemFrom(txn, id);
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
        } on StateError {
          throw VaultItemNotFoundException(id);
        }
      },
    );
  }

  Future<Map<String, String?>> _decryptItemForHealth(
    EncryptedVaultItem item,
    Uint8List dek,
  ) async {
    final clearBytes = await _crypto.decryptBytes(
      key: dek,
      payload: EncryptedPayload(
        nonce: fromB64(item.nonce),
        ciphertext: fromB64(item.ciphertext),
        mac: fromB64(item.mac),
      ),
    );
    final decoded = jsonDecode(utf8.decode(clearBytes));
    if (decoded is! Map) {
      return {
        'id': item.id,
        'title': '',
        'username': '',
        'password': '',
        'website': null,
        'updatedAt': '${item.updatedAt}',
        'createdAt': '${item.createdAt}',
      };
    }
    final map = Map<String, Object?>.from(decoded);
    return {
      'id': item.id,
      'title': map['title'] as String? ?? '',
      'username': map['username'] as String? ?? '',
      'password': map['password'] as String? ?? '',
      'website': map['website'] as String?,
      'updatedAt': '${item.updatedAt}',
      'createdAt': '${item.createdAt}',
    };
  }

  Future<HealthReport> analyzePasswordHealth({
    required PasswordHealthService healthService,
  }) async {
    _ensureUnlocked();
    final items = await repository.itemsDao.allItemsForManifest();
    final activeItems = items.where((i) => i.deletedAt == null).toList();

    final decryptedItems = await _session.withDekCopy((dek) async {
      final results = <Map<String, String?>>[];
      for (final item in activeItems) {
        try {
          results.add(await _decryptItemForHealth(item, dek));
        } catch (_) {
          // skip items that fail to decrypt
        }
      }
      return results;
    });

    return healthService.analyze(decryptedItems: decryptedItems);
  }

  Future<List<TotpListItem>> listTotpItems() async {
    _ensureUnlocked();
    final items = await repository.itemsDao.allItemsForManifest();
    final active = items.where((i) => i.deletedAt == null).toList();

    return _session.withDekCopy((dek) async {
      final results = <TotpListItem>[];
      for (final item in active) {
        try {
          final clearBytes = await _crypto.decryptBytes(
            key: dek,
            payload: EncryptedPayload(
              nonce: fromB64(item.nonce),
              ciphertext: fromB64(item.ciphertext),
              mac: fromB64(item.mac),
            ),
          );
          final decoded = jsonDecode(utf8.decode(clearBytes));
          if (decoded is! Map) continue;
          final entry = PasswordEntry.fromJson(Map<String, Object?>.from(decoded));
          if (entry.totpSecret == null || entry.totpSecret!.isEmpty) continue;
          results.add(TotpListItem(
            id: item.id,
            title: entry.title,
            username: entry.username,
            totpSecret: entry.totpSecret!,
          ));
        } catch (_) {
          // skip items that fail to decrypt or parse
        }
      }
      return results;
    });
  }

  Future<List<String>> allTags() async {
    _ensureUnlocked();
    final items = await repository.itemsDao.allItemsForManifest();
    final active = items.where((i) => i.deletedAt == null).toList();
    final tags = <String>{};
    return _session.withDekCopy((dek) async {
      for (final item in active) {
        try {
          final clearBytes = await _crypto.decryptBytes(
            key: dek,
            payload: EncryptedPayload(
              nonce: fromB64(item.nonce),
              ciphertext: fromB64(item.ciphertext),
              mac: fromB64(item.mac),
            ),
          );
          final decoded = jsonDecode(utf8.decode(clearBytes));
          if (decoded is! Map) continue;
          final entry = PasswordEntry.fromJson(
            Map<String, Object?>.from(decoded),
          );
          tags.addAll(entry.tags);
        } catch (_) {
          // skip items that fail to decrypt
        }
      }
      final sorted = tags.toList()..sort();
      return sorted;
    });
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
          try {
            final clearBytes = await _crypto.decryptBytes(
              key: dek,
              payload: EncryptedPayload(
                nonce: fromB64(item.nonce),
                ciphertext: fromB64(item.ciphertext),
                mac: fromB64(item.mac),
              ),
            );
            final decoded = jsonDecode(utf8.decode(clearBytes));
            if (decoded is! Map) continue;
            final entry = PasswordEntry.fromJson(
              Map<String, Object?>.from(decoded),
            );
            if (!entry.tags.contains(oldTag)) continue;
            final newTags =
                entry.tags.map((t) => t == oldTag ? newTag : t).toList();
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
          } catch (_) {
            // skip items that fail to decrypt
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
          try {
            final clearBytes = await _crypto.decryptBytes(
              key: dek,
              payload: EncryptedPayload(
                nonce: fromB64(item.nonce),
                ciphertext: fromB64(item.ciphertext),
                mac: fromB64(item.mac),
              ),
            );
            final decoded = jsonDecode(utf8.decode(clearBytes));
            if (decoded is! Map) continue;
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
          } catch (_) {
            // skip items that fail to decrypt
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
    await _manifestService.verifyManifest(
      dek: dek,
      meta: meta,
      items: items,
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
    await _manifestService.verifyManifest(
      dek: dek,
      meta: currentMeta,
      items: items,
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
          await _manifestService.verifyManifest(
            dek: dek,
            meta: currentMeta,
            items: currentItems,
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
          final manifest = await _manifestService.createManifest(
            dek: dek,
            meta: updatedMeta,
            items: updatedItems,
            previous: previous,
            updatedAt: updatedAt,
          );
          await txn.manifestDao.save(manifest);
          await _writeAnchorForManifest(meta: updatedMeta, manifest: manifest);
          return _ManifestMutationResult<T>(
            result: result,
            meta: updatedMeta,
            manifest: manifest,
          );
        });
      });
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

  bool _isIntegrityReadFailure(Object error) {
    return error is VaultIntegrityException ||
        error is FormatException ||
        error is StateError ||
        error is ArgumentError;
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
    final clearBytes = await _session.decrypt(
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
  }

  Future<void> _verifyCurrentManifestWithActiveSession() async {
    try {
      await _session.withDekCopy((dek) async {
        final meta = await _requireVaultMeta();
        await _verifyExistingManifest(meta: meta, dek: dek);
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
