import 'dart:typed_data';

import 'package:secure_box/core/crypto/crypto_service.dart';

class VaultLockedException implements Exception {
  const VaultLockedException(this.message);

  final String message;

  @override
  String toString() => 'VaultLockedException: $message';
}

class VaultSession {
  Uint8List? _dek;

  bool get isUnlocked => _dek != null;

  void unlock(Uint8List dek) {
    if (dek.length != 32) {
      throw ArgumentError.value(
        dek.length,
        'dek',
        'DEK must be 32 bytes for AES-256-GCM',
      );
    }
    lock();
    _dek = Uint8List.fromList(dek);
  }

  void lock() {
    final dek = _dek;
    if (dek != null) {
      dek.fillRange(0, dek.length, 0);
    }
    _dek = null;
  }

  void ensureUnlocked() {
    if (_dek == null) {
      throw const VaultLockedException('Vault is locked');
    }
  }

  Future<EncryptedPayload> encrypt({
    required CryptoService crypto,
    required List<int> plaintext,
  }) async {
    final key = _copyDek();
    try {
      return await crypto.encryptBytes(key: key, plaintext: plaintext);
    } finally {
      _zero(key);
    }
  }

  Future<Uint8List> decrypt({
    required CryptoService crypto,
    required EncryptedPayload payload,
  }) async {
    final key = _copyDek();
    try {
      return await crypto.decryptBytes(key: key, payload: payload);
    } finally {
      _zero(key);
    }
  }

  Uint8List _copyDek() {
    final dek = _dek;
    if (dek == null) {
      throw const VaultLockedException('Vault is locked');
    }
    return Uint8List.fromList(dek);
  }

  void _zero(Uint8List value) {
    value.fillRange(0, value.length, 0);
  }
}
