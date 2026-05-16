import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/vault/vault_anchor.dart';
import 'package:secure_box/core/vault/vault_anchor_service.dart';
import 'package:secure_box/core/vault/vault_anchor_store.dart';
import 'package:secure_box/data/models/vault_manifest.dart';

void main() {
  VaultManifest manifest({int epoch = 1, int counter = 1, String mac = 'mac'}) {
    return VaultManifest(
      version: 1,
      epoch: epoch,
      counter: counter,
      nonce: 'nonce',
      ciphertext: 'ciphertext',
      mac: mac,
      updatedAt: 1760000000000 + counter,
    );
  }

  test('writeAcceptedManifest stores non-secret manifest anchor', () async {
    final store = MemoryVaultAnchorStore();
    final service = VaultAnchorService(store: store);

    await service.writeAcceptedManifest(
      vaultId: 'vault-1',
      manifest: manifest(counter: 2),
      updatedAt: 1760000001000,
    );

    final anchor = await store.read(vaultId: 'vault-1');
    expect(anchor, isNotNull);
    expect(anchor!.vaultId, 'vault-1');
    expect(anchor.schemaVersion, 1);
    expect(anchor.manifestEpoch, 1);
    expect(anchor.manifestCounter, 2);
    expect(anchor.manifestDigest, isNot(contains('ciphertext')));
    expect(anchor.manifestDigest, isNot(contains('mac')));
  });

  test('verifyAgainstAnchor accepts matching manifest', () async {
    final store = MemoryVaultAnchorStore();
    final service = VaultAnchorService(store: store);
    final current = manifest(counter: 3);
    await service.writeAcceptedManifest(
      vaultId: 'vault-1',
      manifest: current,
      updatedAt: 1760000003000,
    );

    final result = await service.verifyAgainstAnchor(
      vaultId: 'vault-1',
      manifest: current,
    );

    expect(result, VaultAnchorVerificationResult.matched);
  });

  test('verifyAgainstAnchor reports missing anchor without throwing', () async {
    final service = VaultAnchorService(store: MemoryVaultAnchorStore());

    final result = await service.verifyAgainstAnchor(
      vaultId: 'vault-1',
      manifest: manifest(),
    );

    expect(result, VaultAnchorVerificationResult.missing);
  });

  test('verifyAgainstAnchor rejects rollback to lower counter', () async {
    final store = MemoryVaultAnchorStore();
    final service = VaultAnchorService(store: store);
    await service.writeAcceptedManifest(
      vaultId: 'vault-1',
      manifest: manifest(counter: 5),
      updatedAt: 1760000005000,
    );

    expect(
      () => service.verifyAgainstAnchor(
        vaultId: 'vault-1',
        manifest: manifest(counter: 4),
      ),
      throwsA(isA<VaultAnchorException>()),
    );
  });

  test('verifyAgainstAnchor rejects same counter digest mismatch', () async {
    final store = MemoryVaultAnchorStore();
    final service = VaultAnchorService(store: store);
    await service.writeAcceptedManifest(
      vaultId: 'vault-1',
      manifest: manifest(counter: 5),
      updatedAt: 1760000005000,
    );

    expect(
      () => service.verifyAgainstAnchor(
        vaultId: 'vault-1',
        manifest: manifest(counter: 5, mac: 'different-mac'),
      ),
      throwsA(isA<VaultAnchorException>()),
    );
  });

  test('deleteAnchor removes stored anchor', () async {
    final store = MemoryVaultAnchorStore();
    final service = VaultAnchorService(store: store);
    await service.writeAcceptedManifest(
      vaultId: 'vault-1',
      manifest: manifest(),
      updatedAt: 1760000000000,
    );

    await service.deleteAnchor(vaultId: 'vault-1');

    expect(await store.read(vaultId: 'vault-1'), isNull);
  });

  test('VaultAnchor rejects malformed schema version', () {
    expect(
      () => VaultAnchor.fromJson({
        'vault_id': 'vault-1',
        'schema_version': 2,
        'manifest_epoch': 1,
        'manifest_counter': 1,
        'manifest_digest': 'digest',
        'updated_at': 1760000000000,
      }),
      throwsFormatException,
    );
  });
}
