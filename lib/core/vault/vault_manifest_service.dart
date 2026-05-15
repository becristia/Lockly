import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart'
    show Hkdf, Hmac, SecretKey, Sha256;
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/encoding.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:secure_box/data/models/vault_meta.dart';

const _manifestVersion = 1;
const _manifestKeyInfo = 'secure-box:vault-manifest:v1';
const _manifestKeyLength = 32;

class VaultIntegrityException implements Exception {
  const VaultIntegrityException([
    this.message = 'Vault integrity check failed',
  ]);

  final String message;

  @override
  String toString() => 'VaultIntegrityException: $message';
}

class VaultManifestService {
  VaultManifestService({required CryptoService crypto}) : _crypto = crypto;

  final CryptoService _crypto;
  final Hkdf _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: _manifestKeyLength,
  );
  final Sha256 _sha256 = Sha256();

  Future<VaultManifest> createManifest({
    required Uint8List dek,
    required VaultMeta meta,
    required List<EncryptedVaultItem> items,
    required VaultManifest? previous,
    required int updatedAt,
  }) async {
    final epoch = previous?.epoch ?? 1;
    final counter = previous == null ? 1 : previous.counter + 1;
    final payload = await _buildPayload(
      meta: meta,
      items: items,
      epoch: epoch,
      counter: counter,
    );
    final manifestKey = await _deriveManifestKey(dek);
    try {
      final encrypted = await _crypto.encryptBytes(
        key: manifestKey,
        plaintext: utf8.encode(_canonicalJson(payload)),
      );
      return VaultManifest(
        version: _manifestVersion,
        epoch: epoch,
        counter: counter,
        nonce: b64(encrypted.nonce),
        ciphertext: b64(encrypted.ciphertext),
        mac: b64(encrypted.mac),
        updatedAt: updatedAt,
      );
    } finally {
      manifestKey.fillRange(0, manifestKey.length, 0);
    }
  }

  Future<void> verifyManifest({
    required Uint8List dek,
    required VaultMeta meta,
    required List<EncryptedVaultItem> items,
    required VaultManifest manifest,
  }) async {
    if (manifest.version != _manifestVersion) {
      throw const VaultIntegrityException();
    }

    final manifestKey = await _deriveManifestKey(dek);
    try {
      final plaintext = await _decryptManifestPayload(
        key: manifestKey,
        manifest: manifest,
      );
      final decoded = _decodePayload(plaintext);
      final expected = await _buildPayload(
        meta: meta,
        items: items,
        epoch: manifest.epoch,
        counter: manifest.counter,
      );

      if (_canonicalJson(decoded) != _canonicalJson(expected)) {
        throw const VaultIntegrityException();
      }
    } finally {
      manifestKey.fillRange(0, manifestKey.length, 0);
    }
  }

  Future<Uint8List> _deriveManifestKey(Uint8List dek) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(dek),
      info: utf8.encode(_manifestKeyInfo),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  Future<Uint8List> _decryptManifestPayload({
    required Uint8List key,
    required VaultManifest manifest,
  }) async {
    try {
      return await _crypto.decryptBytes(
        key: key,
        payload: EncryptedPayload(
          nonce: fromB64(manifest.nonce),
          ciphertext: fromB64(manifest.ciphertext),
          mac: fromB64(manifest.mac),
        ),
      );
    } on FormatException {
      throw const VaultIntegrityException();
    } on CryptoException {
      throw const VaultIntegrityException();
    } on ArgumentError {
      throw const VaultIntegrityException();
    } on StateError {
      throw const VaultIntegrityException();
    }
  }

  Map<String, Object?> _decodePayload(Uint8List plaintext) {
    try {
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map<String, Object?>) {
        throw const VaultIntegrityException();
      }
      if (decoded['version'] != _manifestVersion) {
        throw const VaultIntegrityException();
      }
      return decoded;
    } on FormatException {
      throw const VaultIntegrityException();
    } on ArgumentError {
      throw const VaultIntegrityException();
    }
  }

  Future<Map<String, Object?>> _buildPayload({
    required VaultMeta meta,
    required List<EncryptedVaultItem> items,
    required int epoch,
    required int counter,
  }) async {
    return {
      'version': _manifestVersion,
      'vault_id': meta.id,
      'epoch': epoch,
      'counter': counter,
      'kdf': meta.kdf,
      'meta_digest': await _digestObject(_metaDescriptor(meta)),
      'kdf_params_digest': await _digestObject(meta.kdfParams.toJson()),
      'encrypted_dek_digest': await _digestObject({
        'encrypted_dek_by_master': meta.encryptedDekByMaster,
        'encrypted_dek_by_master_nonce': meta.encryptedDekByMasterNonce,
        'encrypted_dek_by_master_mac': meta.encryptedDekByMasterMac,
      }),
      'active_item_count': items.where((item) => item.deletedAt == null).length,
      'deleted_item_count': items
          .where((item) => item.deletedAt != null)
          .length,
      'items_digest': await _digestObject(_itemDescriptors(items)),
    };
  }

  Map<String, Object?> _metaDescriptor(VaultMeta meta) {
    return {
      'id': meta.id,
      'version': meta.version,
      'kdf': meta.kdf,
      'kdf_params': meta.kdfParams.toJson(),
      'salt': meta.salt,
      'encrypted_dek_by_master': meta.encryptedDekByMaster,
      'encrypted_dek_by_master_nonce': meta.encryptedDekByMasterNonce,
      'encrypted_dek_by_master_mac': meta.encryptedDekByMasterMac,
      'biometric_enabled': meta.biometricEnabled,
      'encrypted_dek_by_biometric': meta.encryptedDekByBiometric,
      'encrypted_dek_by_biometric_nonce': meta.encryptedDekByBiometricNonce,
      'encrypted_dek_by_biometric_mac': meta.encryptedDekByBiometricMac,
      'created_at': meta.createdAt,
      'updated_at': meta.updatedAt,
    };
  }

  List<Map<String, Object?>> _itemDescriptors(List<EncryptedVaultItem> items) {
    final descriptors = items
        .map(
          (item) => {
            'id': item.id,
            'nonce': item.nonce,
            'ciphertext': item.ciphertext,
            'mac': item.mac,
            'created_at': item.createdAt,
            'updated_at': item.updatedAt,
            'deleted_at': item.deletedAt,
          },
        )
        .toList();
    descriptors.sort((left, right) {
      final idComparison = (left['id']! as String).compareTo(
        right['id']! as String,
      );
      if (idComparison != 0) {
        return idComparison;
      }
      return _canonicalJson(left).compareTo(_canonicalJson(right));
    });
    return descriptors;
  }

  Future<String> _digestObject(Object? value) async {
    final digest = await _sha256.hash(utf8.encode(_canonicalJson(value)));
    return b64(Uint8List.fromList(digest.bytes));
  }

  String _canonicalJson(Object? value) {
    return jsonEncode(_canonicalize(value));
  }

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final sorted = <String, Object?>{};
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      for (final key in keys) {
        sorted[key] = _canonicalize(value[key]);
      }
      return sorted;
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }
}
