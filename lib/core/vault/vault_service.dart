import 'dart:convert';
import 'dart:typed_data';

import 'package:secure_box/core/biometric/biometric_service.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/encoding.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_session.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/password_entry.dart';
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

class VaultService {
  VaultService({
    required this.repository,
    required SecureRandom random,
    required KdfService kdf,
    required CryptoService crypto,
    VaultSession? session,
    Uuid? uuid,
  }) : _random = random,
       _kdf = kdf,
       _crypto = crypto,
       _session = session ?? VaultSession(),
       _uuid = uuid ?? const Uuid();

  final VaultRepository repository;
  final SecureRandom _random;
  final KdfService _kdf;
  final CryptoService _crypto;
  final VaultSession _session;
  final Uuid _uuid;

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
    final kdfParams = KdfParams.pbkdf2();
    Uint8List? kek;
    Uint8List? dek;
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
      });
      _session.lock();
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
      _session.unlock(dek);
      return _session;
    } on CryptoException {
      _session.lock();
      throw const VaultUnlockException('Invalid master password');
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
      _session.lock();
      return false;
    }

    try {
      _session.unlock(dek);
      return true;
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
      await biometricService.enable(dek);
      biometricEnabled = true;
      final updatedAt = DateTime.now().millisecondsSinceEpoch;
      await repository.metaDao.save(
        VaultMeta(
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
        ),
      );
    } catch (_) {
      if (biometricEnabled) {
        await biometricService.disable();
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
    await biometricService.disable();
    if (!meta.biometricEnabled) {
      return;
    }

    await repository.metaDao.clearBiometricDek(
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final meta = await _requireVaultMeta();
    Uint8List? dek;
    Uint8List? newKek;
    try {
      dek = await _decryptDekWithUnlockError(meta: meta, password: oldPassword);
      final newSalt = _random.bytes(16);
      newKek = await _kdf.deriveKey(
        password: newPassword,
        salt: newSalt,
        params: meta.kdfParams,
      );
      final wrappedDek = await _crypto.encryptBytes(
        key: newKek,
        plaintext: dek,
      );
      final updatedAt = DateTime.now().millisecondsSinceEpoch;
      final updatedMeta = VaultMeta(
        id: meta.id,
        version: meta.version,
        kdf: meta.kdf,
        kdfParams: meta.kdfParams,
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

      await repository.transaction((txn) => txn.metaDao.save(updatedMeta));
      _session.unlock(dek);
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
    final encryptedItem = await _encryptEntry(
      id: id,
      entry: entry,
      createdAt: now,
      updatedAt: now,
    );

    await repository.itemsDao.upsert(encryptedItem);
    return id;
  }

  Future<PasswordEntry> getItem(String id) async {
    _ensureUnlocked();
    final encryptedItem = await _requireActiveItem(id);
    return _decryptItem(encryptedItem);
  }

  Future<List<VaultListItem>> listItems({String query = ''}) async {
    _ensureUnlocked();
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
    final existing = await _requireActiveItem(id);
    final updatedItem = await _encryptEntry(
      id: id,
      entry: entry,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final updated = await repository.itemsDao.updateActive(updatedItem);
    if (!updated) {
      throw VaultItemNotFoundException(id);
    }
  }

  Future<void> deleteItem(String id) async {
    _ensureUnlocked();
    await _requireActiveItem(id);
    try {
      await repository.itemsDao.softDelete(
        id,
        DateTime.now().millisecondsSinceEpoch,
      );
    } on StateError {
      throw VaultItemNotFoundException(id);
    }
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

  void _ensureUnlocked() {
    _session.ensureUnlocked();
  }

  Future<EncryptedVaultItem> _requireActiveItem(String id) async {
    final encryptedItem = await repository.itemsDao.byId(id);
    if (encryptedItem == null || encryptedItem.deletedAt != null) {
      throw VaultItemNotFoundException(id);
    }
    return encryptedItem;
  }

  Future<EncryptedVaultItem> _encryptEntry({
    required String id,
    required PasswordEntry entry,
    required int createdAt,
    required int updatedAt,
  }) async {
    final encryptedPayload = await _session.encrypt(
      crypto: _crypto,
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
