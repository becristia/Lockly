import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:secure_box/core/crypto/encoding.dart';
import 'package:secure_box/core/vault/vault_anchor.dart';
import 'package:secure_box/core/vault/vault_anchor_store.dart';
import 'package:secure_box/data/models/vault_manifest.dart';

enum VaultAnchorVerificationResult { matched, missing, newerThanAnchor }

class VaultAnchorException implements Exception {
  const VaultAnchorException([this.message = 'Vault anchor check failed']);

  final String message;

  @override
  String toString() => 'VaultAnchorException: $message';
}

class VaultAnchorService {
  VaultAnchorService({required VaultAnchorStore store}) : _store = store;

  static const _pendingAnchorVaultIdSuffix = ':pending';

  final VaultAnchorStore _store;
  final Sha256 _sha256 = Sha256();

  Future<VaultAnchorVerificationResult> verifyAgainstAnchor({
    required String vaultId,
    required VaultManifest manifest,
    bool allowNewerManifest = false,
  }) async {
    final VaultAnchor? anchor;
    try {
      anchor = await _store.read(vaultId: vaultId);
    } catch (error, stackTrace) {
      if (error is Error) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      throw const VaultAnchorException();
    }
    if (anchor == null) {
      return VaultAnchorVerificationResult.missing;
    }

    if (anchor.vaultId != vaultId ||
        anchor.schemaVersion != VaultAnchor.currentSchemaVersion) {
      throw const VaultAnchorException();
    }
    if (_isManifestOlderThanAnchor(manifest: manifest, anchor: anchor)) {
      throw const VaultAnchorException();
    }
    if (_isManifestNewerThanAnchor(manifest: manifest, anchor: anchor)) {
      if (allowNewerManifest) {
        return VaultAnchorVerificationResult.newerThanAnchor;
      }
      throw const VaultAnchorException();
    }
    if (manifest.epoch == anchor.manifestEpoch &&
        manifest.counter == anchor.manifestCounter) {
      final digest = await digestManifest(manifest);
      if (digest != anchor.manifestDigest) {
        throw const VaultAnchorException();
      }
    }

    return VaultAnchorVerificationResult.matched;
  }

  Future<void> writeAcceptedManifest({
    required String vaultId,
    required VaultManifest manifest,
    required int updatedAt,
  }) async {
    await _writeAnchorForManifest(
      storedVaultId: vaultId,
      manifest: manifest,
      updatedAt: updatedAt,
    );
  }

  Future<void> writePendingManifest({
    required String vaultId,
    required VaultManifest manifest,
    required int updatedAt,
  }) async {
    await _writeAnchorForManifest(
      storedVaultId: _pendingAnchorVaultId(vaultId),
      manifest: manifest,
      updatedAt: updatedAt,
    );
  }

  Future<bool> matchesPendingManifest({
    required String vaultId,
    required VaultManifest manifest,
  }) async {
    final pendingVaultId = _pendingAnchorVaultId(vaultId);
    final VaultAnchor? anchor;
    try {
      anchor = await _store.read(vaultId: pendingVaultId);
    } catch (error, stackTrace) {
      if (error is Error) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      throw const VaultAnchorException();
    }
    if (anchor == null) {
      return false;
    }
    if (anchor.vaultId != pendingVaultId ||
        anchor.schemaVersion != VaultAnchor.currentSchemaVersion) {
      throw const VaultAnchorException();
    }
    if (anchor.manifestEpoch != manifest.epoch ||
        anchor.manifestCounter != manifest.counter) {
      return false;
    }
    return anchor.manifestDigest == await digestManifest(manifest);
  }

  Future<void> deletePendingManifest({required String vaultId}) {
    return deleteAnchor(vaultId: _pendingAnchorVaultId(vaultId));
  }

  Future<void> _writeAnchorForManifest({
    required String storedVaultId,
    required VaultManifest manifest,
    required int updatedAt,
  }) async {
    final anchor = VaultAnchor(
      vaultId: storedVaultId,
      schemaVersion: VaultAnchor.currentSchemaVersion,
      manifestEpoch: manifest.epoch,
      manifestCounter: manifest.counter,
      manifestDigest: await digestManifest(manifest),
      updatedAt: updatedAt,
    );
    try {
      await _store.write(anchor);
    } catch (error, stackTrace) {
      if (error is Error) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      throw const VaultAnchorException();
    }
  }

  String _pendingAnchorVaultId(String vaultId) =>
      '$vaultId$_pendingAnchorVaultIdSuffix';

  Future<void> deleteAnchor({required String vaultId}) async {
    try {
      await _store.delete(vaultId: vaultId);
    } catch (error, stackTrace) {
      if (error is Error) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      throw const VaultAnchorException();
    }
  }

  Future<String> digestManifest(VaultManifest manifest) async {
    final canonical = jsonEncode({
      'ciphertext_digest': await _digestString(manifest.ciphertext),
      'counter': manifest.counter,
      'epoch': manifest.epoch,
      'mac_digest': await _digestString(manifest.mac),
      'nonce_digest': await _digestString(manifest.nonce),
      'updated_at': manifest.updatedAt,
      'version': manifest.version,
    });
    return _digestString(canonical);
  }

  Future<String> _digestString(String value) async {
    final digest = await _sha256.hash(utf8.encode(value));
    return b64(Uint8List.fromList(digest.bytes));
  }

  bool _isManifestOlderThanAnchor({
    required VaultManifest manifest,
    required VaultAnchor anchor,
  }) {
    if (manifest.epoch < anchor.manifestEpoch) {
      return true;
    }
    if (manifest.epoch > anchor.manifestEpoch) {
      return false;
    }
    return manifest.counter < anchor.manifestCounter;
  }

  bool _isManifestNewerThanAnchor({
    required VaultManifest manifest,
    required VaultAnchor anchor,
  }) {
    if (manifest.epoch > anchor.manifestEpoch) {
      return true;
    }
    if (manifest.epoch < anchor.manifestEpoch) {
      return false;
    }
    return manifest.counter > anchor.manifestCounter;
  }
}
