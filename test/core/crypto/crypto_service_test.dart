import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';

void main() {
  test(
    'correct password decrypts encrypted DEK and wrong password fails',
    () async {
      final random = SecureRandom();
      final kdf = KdfService();
      final crypto = CryptoService(random: random);
      final salt = random.bytes(16);
      final params = KdfParams.pbkdf2(iterations: 120000);
      final dek = random.bytes(32);

      final goodKek = await kdf.deriveKey(
        password: 'correct horse battery staple',
        salt: salt,
        params: params,
      );
      final encryptedDek = await crypto.encryptBytes(
        key: goodKek,
        plaintext: dek,
      );

      final unlockedDek = await crypto.decryptBytes(
        key: goodKek,
        payload: encryptedDek,
      );
      expect(unlockedDek, dek);

      final badKek = await kdf.deriveKey(
        password: 'wrong password',
        salt: salt,
        params: params,
      );
      expect(
        () => crypto.decryptBytes(key: badKek, payload: encryptedDek),
        throwsA(isA<CryptoException>()),
      );
    },
  );

  test(
    'same plaintext encrypts to different ciphertext with unique nonces',
    () async {
      final random = SecureRandom();
      final crypto = CryptoService(random: random);
      final key = random.bytes(32);
      final plaintext = utf8.encode('same secret payload');

      final first = await crypto.encryptBytes(key: key, plaintext: plaintext);
      final second = await crypto.encryptBytes(key: key, plaintext: plaintext);

      expect(first.nonce, isNot(second.nonce));
      expect(first.ciphertext, isNot(second.ciphertext));
      expect(await crypto.decryptBytes(key: key, payload: first), plaintext);
      expect(await crypto.decryptBytes(key: key, payload: second), plaintext);
    },
  );
}
