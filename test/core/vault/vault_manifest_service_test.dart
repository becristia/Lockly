import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/encoding.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
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
}

VaultMeta _meta({String? encryptedDekByMaster}) {
  return VaultMeta(
    id: 'vault-1',
    version: 1,
    kdf: 'pbkdf2-hmac-sha256',
    kdfParams: KdfParams.pbkdf2(iterations: 120000),
    salt: b64(Uint8List.fromList(List<int>.filled(16, 7))),
    encryptedDekByMaster:
        encryptedDekByMaster ?? b64(Uint8List.fromList([1, 2, 3])),
    encryptedDekByMasterNonce: b64(Uint8List.fromList([4, 5, 6])),
    encryptedDekByMasterMac: b64(Uint8List.fromList([7, 8, 9])),
    biometricEnabled: false,
    createdAt: 1000,
    updatedAt: 2000,
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
