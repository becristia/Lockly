import 'dart:typed_data';

import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretBoxAuthenticationError, SecretKey;
import 'package:secure_box/core/crypto/secure_random.dart';

class EncryptedPayload {
  const EncryptedPayload({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;
}

class CryptoException implements Exception {
  const CryptoException(this.message);
  final String message;

  @override
  String toString() => 'CryptoException: $message';
}

class CryptoService {
  CryptoService({required SecureRandom random}) : _random = random;

  final SecureRandom _random;
  final AesGcm _algorithm = AesGcm.with256bits();

  Future<EncryptedPayload> encryptBytes({
    required Uint8List key,
    required List<int> plaintext,
  }) async {
    _validateKey(key);
    final nonce = _random.nonce12();
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    return EncryptedPayload(
      nonce: Uint8List.fromList(box.nonce),
      ciphertext: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  Future<Uint8List> decryptBytes({
    required Uint8List key,
    required EncryptedPayload payload,
  }) async {
    _validateKey(key);
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(
          payload.ciphertext,
          nonce: payload.nonce,
          mac: Mac(payload.mac),
        ),
        secretKey: SecretKey(key),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const CryptoException('Authentication failed');
    }
  }

  void _validateKey(Uint8List key) {
    if (key.length != 32) {
      throw const CryptoException('Key must be 32 bytes for AES-256-GCM');
    }
  }
}
