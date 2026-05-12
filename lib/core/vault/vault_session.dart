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
    _requireDekCopy();
  }

  Future<EncryptedPayload> encrypt({
    required CryptoService crypto,
    required List<int> plaintext,
  }) {
    return crypto.encryptBytes(key: _requireDekCopy(), plaintext: plaintext);
  }

  Future<Uint8List> decrypt({
    required CryptoService crypto,
    required EncryptedPayload payload,
  }) {
    return crypto.decryptBytes(key: _requireDekCopy(), payload: payload);
  }

  Uint8List _requireDekCopy() {
    final dek = _dek;
    if (dek == null) {
      throw const VaultLockedException('Vault is locked');
    }
    return Uint8List.fromList(dek);
  }
}
