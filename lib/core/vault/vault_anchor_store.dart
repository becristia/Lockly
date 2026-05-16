import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:secure_box/core/vault/vault_anchor.dart';

abstract class VaultAnchorStore {
  Future<VaultAnchor?> read({required String vaultId});

  Future<void> write(VaultAnchor anchor);

  Future<void> delete({required String vaultId});
}

class SecureStorageVaultAnchorStore implements VaultAnchorStore {
  SecureStorageVaultAnchorStore({
    FlutterSecureStorage? storage,
    AndroidOptions androidOptions = _defaultAndroidOptions,
  }) : _storage = storage ?? FlutterSecureStorage(aOptions: androidOptions),
       _androidOptions = androidOptions;

  static const _keyPrefix = 'vault_anchor_';
  static const _defaultAndroidOptions = AndroidOptions(
    storageNamespace: 'secure_box_vault_anchor',
    resetOnError: false,
  );
  @visibleForTesting
  static const defaultAndroidOptionsForTest = _defaultAndroidOptions;

  final FlutterSecureStorage _storage;
  final AndroidOptions _androidOptions;

  @override
  Future<VaultAnchor?> read({required String vaultId}) async {
    final value = await _storage.read(
      key: _keyFor(vaultId),
      aOptions: _androidOptions,
    );
    if (value == null) {
      return null;
    }

    final decoded = jsonDecode(value);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Invalid vault anchor JSON');
    }

    return VaultAnchor.fromJson(Map<String, Object?>.from(decoded));
  }

  @override
  Future<void> write(VaultAnchor anchor) {
    return _storage.write(
      key: _keyFor(anchor.vaultId),
      value: jsonEncode(anchor.toJson()),
      aOptions: _androidOptions,
    );
  }

  @override
  Future<void> delete({required String vaultId}) {
    return _storage.delete(key: _keyFor(vaultId), aOptions: _androidOptions);
  }

  String _keyFor(String vaultId) => '$_keyPrefix$vaultId';
}

class MemoryVaultAnchorStore implements VaultAnchorStore {
  final Map<String, VaultAnchor> _anchors = {};

  @override
  Future<VaultAnchor?> read({required String vaultId}) async {
    return _anchors[vaultId];
  }

  @override
  Future<void> write(VaultAnchor anchor) async {
    _anchors[anchor.vaultId] = anchor;
  }

  @override
  Future<void> delete({required String vaultId}) async {
    _anchors.remove(vaultId);
  }
}
