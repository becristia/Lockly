import 'dart:convert';
import 'dart:typed_data';

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

  Future<void> createVault({required String masterPassword}) async {
    if (await repository.metaDao.get() != null) {
      throw StateError('Vault already exists');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final salt = _random.bytes(16);
    final kdfParams = KdfParams.pbkdf2();
    final kek = await _kdf.deriveKey(
      password: masterPassword,
      salt: salt,
      params: kdfParams,
    );
    final dek = _random.bytes(32);
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
  }

  Future<VaultSession> unlock({required String masterPassword}) async {
    final meta = await _requireVaultMeta();

    try {
      final dek = await _decryptDek(meta: meta, password: masterPassword);
      _session.unlock(dek);
      return _session;
    } on CryptoException {
      _session.lock();
      throw const VaultUnlockException('Invalid master password');
    }
  }

  Future<void> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final meta = await _requireVaultMeta();
    final dek = await _decryptDekWithUnlockError(
      meta: meta,
      password: oldPassword,
    );
    final newSalt = _random.bytes(16);
    final newKek = await _kdf.deriveKey(
      password: newPassword,
      salt: newSalt,
      params: meta.kdfParams,
    );
    final wrappedDek = await _crypto.encryptBytes(key: newKek, plaintext: dek);
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
  }

  Future<String> createItem(PasswordEntry entry) async {
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
    final encryptedItem = await repository.itemsDao.byId(id);
    if (encryptedItem == null || encryptedItem.deletedAt != null) {
      throw VaultItemNotFoundException(id);
    }

    return _decryptItem(encryptedItem);
  }

  Future<List<VaultListItem>> listItems({String query = ''}) async {
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
    final existing = await repository.itemsDao.byId(id);
    if (existing == null || existing.deletedAt != null) {
      throw VaultItemNotFoundException(id);
    }

    final updatedItem = await _encryptEntry(
      id: id,
      entry: entry,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await repository.itemsDao.upsert(updatedItem);
  }

  Future<void> deleteItem(String id) {
    return repository.itemsDao.softDelete(
      id,
      DateTime.now().millisecondsSinceEpoch,
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
    final kek = await _kdf.deriveKey(
      password: password,
      salt: fromB64(meta.salt),
      params: meta.kdfParams,
    );
    return _crypto.decryptBytes(
      key: kek,
      payload: EncryptedPayload(
        nonce: fromB64(meta.encryptedDekByMasterNonce),
        ciphertext: fromB64(meta.encryptedDekByMaster),
        mac: fromB64(meta.encryptedDekByMasterMac),
      ),
    );
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

  Future<EncryptedVaultItem> _encryptEntry({
    required String id,
    required PasswordEntry entry,
    required int createdAt,
    required int updatedAt,
  }) async {
    final encryptedPayload = await _crypto.encryptBytes(
      key: _session.dek,
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
    final clearBytes = await _crypto.decryptBytes(
      key: _session.dek,
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
}
