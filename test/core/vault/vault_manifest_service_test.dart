import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart'
    show Hkdf, Hmac, SecretKey, Sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/encoding.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:secure_box/data/models/vault_meta.dart';

void main() {
  late VaultManifestService service;
  late Uint8List dek;
  late VaultMeta meta;
  late List<EncryptedVaultItem> items;

  setUp(() {
    service = VaultManifestService(
      crypto: CryptoService(random: SecureRandom()),
    );
    dek = Uint8List.fromList(List<int>.generate(32, (index) => index));
    meta = _meta();
    items = [_itemB(), _itemA()];
  });

  test(
    'create and verify succeeds for same encrypted state in any item order',
    () async {
      final manifest = await service.createManifest(
        dek: dek,
        meta: meta,
        items: items,
        previous: null,
        updatedAt: 3000,
      );

      expect(manifest.version, 1);
      expect(manifest.epoch, 1);
      expect(manifest.counter, 1);

      await service.verifyManifest(
        dek: dek,
        meta: meta,
        items: items.reversed.toList(),
        manifest: manifest,
      );
    },
  );

  test('verify rejects tampered item ciphertext', () async {
    final manifest = await service.createManifest(
      dek: dek,
      meta: meta,
      items: items,
      previous: null,
      updatedAt: 3000,
    );
    final tamperedItems = [
      _itemB(ciphertext: b64(Uint8List.fromList([99, 98, 97]))),
      _itemA(),
    ];

    expect(
      () => service.verifyManifest(
        dek: dek,
        meta: meta,
        items: tamperedItems,
        manifest: manifest,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

  test('create preserves previous epoch and increments counter', () async {
    final first = await service.createManifest(
      dek: dek,
      meta: meta,
      items: items,
      previous: null,
      updatedAt: 3000,
    );
    final second = await service.createManifest(
      dek: dek,
      meta: meta,
      items: items,
      previous: first,
      updatedAt: 4000,
    );

    expect(second.epoch, first.epoch);
    expect(second.counter, first.counter + 1);
  });

  test('verify rejects tampered metadata', () async {
    final manifest = await service.createManifest(
      dek: dek,
      meta: meta,
      items: items,
      previous: null,
      updatedAt: 3000,
    );
    final tamperedMeta = _meta(
      encryptedDekByMaster: b64(Uint8List.fromList([42, 42, 42])),
    );

    expect(
      () => service.verifyManifest(
        dek: dek,
        meta: tamperedMeta,
        items: items,
        manifest: manifest,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

  test('verify rejects tampered salt', () async {
    final manifest = await service.createManifest(
      dek: dek,
      meta: meta,
      items: items,
      previous: null,
      updatedAt: 3000,
    );
    final tamperedMeta = _meta(
      salt: b64(Uint8List.fromList(List<int>.filled(16, 8))),
    );

    expect(
      () => service.verifyManifest(
        dek: dek,
        meta: tamperedMeta,
        items: items,
        manifest: manifest,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

  test('verify rejects tampered biometric metadata', () async {
    final biometricMeta = _meta(
      biometricEnabled: true,
      encryptedDekByBiometric: b64(Uint8List.fromList([31, 32, 33])),
      encryptedDekByBiometricNonce: b64(Uint8List.fromList([34, 35, 36])),
      encryptedDekByBiometricMac: b64(Uint8List.fromList([37, 38, 39])),
    );
    final manifest = await service.createManifest(
      dek: dek,
      meta: biometricMeta,
      items: items,
      previous: null,
      updatedAt: 3000,
    );

    expect(
      () => service.verifyManifest(
        dek: dek,
        meta: _meta(
          biometricEnabled: false,
          encryptedDekByBiometric: b64(Uint8List.fromList([31, 32, 33])),
          encryptedDekByBiometricNonce: b64(Uint8List.fromList([34, 35, 36])),
          encryptedDekByBiometricMac: b64(Uint8List.fromList([37, 38, 39])),
        ),
        items: items,
        manifest: manifest,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
    expect(
      () => service.verifyManifest(
        dek: dek,
        meta: _meta(
          biometricEnabled: true,
          encryptedDekByBiometric: b64(Uint8List.fromList([40, 41, 42])),
          encryptedDekByBiometricNonce: b64(Uint8List.fromList([34, 35, 36])),
          encryptedDekByBiometricMac: b64(Uint8List.fromList([37, 38, 39])),
        ),
        items: items,
        manifest: manifest,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

  test('verify wraps malformed manifest encryption fields', () async {
    final manifest = await service.createManifest(
      dek: dek,
      meta: meta,
      items: items,
      previous: null,
      updatedAt: 3000,
    );
    final malformedManifest = manifest.copyWith(
      nonce: b64(Uint8List.fromList([1, 2, 3])),
    );

    expect(
      () => service.verifyManifest(
        dek: dek,
        meta: meta,
        items: items,
        manifest: malformedManifest,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

  test('verify rejects manifest row counter mismatch generically', () async {
    final manifest = await service.createManifest(
      dek: dek,
      meta: meta,
      items: items,
      previous: null,
      updatedAt: 3000,
    );

    expect(
      () => service.verifyManifest(
        dek: dek,
        meta: meta,
        items: items,
        manifest: manifest.copyWith(counter: manifest.counter + 1),
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

  test('verify rejects legacy manifest when password history exists', () async {
    final legacyManifest = await _legacyManifest(
      dek: dek,
      meta: meta,
      items: items,
      updatedAt: 3000,
    );

    expect(
      () => service.verifyManifest(
        dek: dek,
        meta: meta,
        items: items,
        historyRecords: const [
          {
            'id': 1,
            'entry_id': 'item-a',
            'encrypted_password': 'ciphertext',
            'password_nonce': 'nonce',
            'password_mac': 'mac',
            'recorded_at': 3100,
          },
        ],
        manifest: legacyManifest,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );
  });
}

Future<VaultManifest> _legacyManifest({
  required Uint8List dek,
  required VaultMeta meta,
  required List<EncryptedVaultItem> items,
  required int updatedAt,
}) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final key = Uint8List.fromList(
    await (await hkdf.deriveKey(
      secretKey: SecretKey(dek),
      info: utf8.encode('secure-box:vault-manifest:v1'),
    )).extractBytes(),
  );
  final crypto = CryptoService(random: SecureRandom());
  final payload = {
    'version': 1,
    'vault_id': meta.id,
    'epoch': 1,
    'counter': 1,
    'kdf': meta.kdf,
    'meta_digest': await _digestObject(_metaDescriptor(meta)),
    'kdf_params_digest': await _digestObject(meta.kdfParams.toJson()),
    'encrypted_dek_digest': await _digestObject({
      'encrypted_dek_by_master': meta.encryptedDekByMaster,
      'encrypted_dek_by_master_nonce': meta.encryptedDekByMasterNonce,
      'encrypted_dek_by_master_mac': meta.encryptedDekByMasterMac,
    }),
    'active_item_count': items.where((item) => item.deletedAt == null).length,
    'deleted_item_count': items.where((item) => item.deletedAt != null).length,
    'items_digest': await _digestObject(_itemDescriptors(items)),
  };
  try {
    final encrypted = await crypto.encryptBytes(
      key: key,
      plaintext: utf8.encode(_canonicalJson(payload)),
    );
    return VaultManifest(
      version: 1,
      epoch: 1,
      counter: 1,
      nonce: b64(encrypted.nonce),
      ciphertext: b64(encrypted.ciphertext),
      mac: b64(encrypted.mac),
      updatedAt: updatedAt,
    );
  } finally {
    key.fillRange(0, key.length, 0);
  }
}

VaultMeta _meta({
  String? salt,
  String? encryptedDekByMaster,
  bool biometricEnabled = false,
  String? encryptedDekByBiometric,
  String? encryptedDekByBiometricNonce,
  String? encryptedDekByBiometricMac,
}) {
  return VaultMeta(
    id: 'vault-1',
    version: 1,
    kdf: 'pbkdf2-hmac-sha256',
    kdfParams: KdfParams.pbkdf2(iterations: 120000),
    salt: salt ?? b64(Uint8List.fromList(List<int>.filled(16, 7))),
    encryptedDekByMaster:
        encryptedDekByMaster ?? b64(Uint8List.fromList([1, 2, 3])),
    encryptedDekByMasterNonce: b64(Uint8List.fromList([4, 5, 6])),
    encryptedDekByMasterMac: b64(Uint8List.fromList([7, 8, 9])),
    biometricEnabled: biometricEnabled,
    createdAt: 1000,
    updatedAt: 2000,
    encryptedDekByBiometric: encryptedDekByBiometric,
    encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
    encryptedDekByBiometricMac: encryptedDekByBiometricMac,
  );
}

EncryptedVaultItem _itemA({String? ciphertext}) {
  return EncryptedVaultItem(
    id: 'item-a',
    nonce: b64(Uint8List.fromList([10, 11, 12])),
    ciphertext: ciphertext ?? b64(Uint8List.fromList([13, 14, 15])),
    mac: b64(Uint8List.fromList([16, 17, 18])),
    createdAt: 1100,
    updatedAt: 2100,
  );
}

EncryptedVaultItem _itemB({String? ciphertext}) {
  return EncryptedVaultItem(
    id: 'item-b',
    nonce: b64(Uint8List.fromList([20, 21, 22])),
    ciphertext: ciphertext ?? b64(Uint8List.fromList([23, 24, 25])),
    mac: b64(Uint8List.fromList([26, 27, 28])),
    createdAt: 1200,
    updatedAt: 2200,
    deletedAt: 2300,
  );
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
  final digest = await Sha256().hash(utf8.encode(_canonicalJson(value)));
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
