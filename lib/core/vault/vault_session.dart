import 'dart:typed_data';

class VaultLockedException implements Exception {
  const VaultLockedException(this.message);

  final String message;

  @override
  String toString() => 'VaultLockedException: $message';
}

class VaultSession {
  Uint8List? _dek;

  bool get isUnlocked => _dek != null;

  Uint8List get dek {
    final dek = _dek;
    if (dek == null) {
      throw const VaultLockedException('Vault is locked');
    }
    return Uint8List.fromList(dek);
  }

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
}
