import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Hmac, Pbkdf2, SecretKey;
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

  test('rejects pbkdf2 params with non-positive iterations', () async {
    final kdf = KdfService();

    expect(
      () => kdf.deriveKey(
        password: 'master-password',
        salt: Uint8List.fromList(List<int>.filled(16, 7)),
        params: KdfParams.pbkdf2(iterations: 0),
      ),
      throwsArgumentError,
    );
  });

  test('rejects pbkdf2 params below the MVP iteration floor', () async {
    final kdf = KdfService();

    expect(
      () => kdf.deriveKey(
        password: 'master-password',
        salt: Uint8List.fromList(List<int>.filled(16, 7)),
        params: KdfParams.pbkdf2(iterations: 99999),
      ),
      throwsArgumentError,
    );
  });

  test('rejects pbkdf2 params with an empty salt', () async {
    final kdf = KdfService();

    expect(
      () => kdf.deriveKey(
        password: 'master-password',
        salt: Uint8List(0),
        params: KdfParams.pbkdf2(),
      ),
      throwsArgumentError,
    );
  });

  test('rejects pbkdf2 params with a salt shorter than 16 bytes', () async {
    final kdf = KdfService();

    expect(
      () => kdf.deriveKey(
        password: 'master-password',
        salt: Uint8List.fromList(List<int>.filled(15, 7)),
        params: KdfParams.pbkdf2(),
      ),
      throwsArgumentError,
    );
  });

  test('rejects pbkdf2 params with a non-256-bit output size', () async {
    final kdf = KdfService();

    expect(
      () => kdf.deriveKey(
        password: 'master-password',
        salt: Uint8List.fromList(List<int>.filled(16, 7)),
        params: KdfParams.pbkdf2(bits: 128),
      ),
      throwsArgumentError,
    );
  });

  test('rejects unsupported kdf names', () async {
    final kdf = KdfService();

    expect(
      () => kdf.deriveKey(
        password: 'master-password',
        salt: Uint8List.fromList(List<int>.filled(16, 7)),
        params: const KdfParams(name: 'scrypt', iterations: 120000, bits: 256),
      ),
      throwsArgumentError,
    );
  });

  test('encryptBytes rejects keys that are not 32 bytes', () async {
    final crypto = CryptoService(random: SecureRandom());

    expect(
      () => crypto.encryptBytes(
        key: Uint8List.fromList(List<int>.filled(31, 1)),
        plaintext: utf8.encode('secret'),
      ),
      throwsA(isA<CryptoException>()),
    );
  });

  test('decryptBytes rejects keys that are not 32 bytes', () async {
    final random = SecureRandom();
    final crypto = CryptoService(random: random);
    final validKey = random.bytes(32);
    final payload = await crypto.encryptBytes(
      key: validKey,
      plaintext: utf8.encode('secret'),
    );

    expect(
      () => crypto.decryptBytes(
        key: Uint8List.fromList(List<int>.filled(31, 1)),
        payload: payload,
      ),
      throwsA(isA<CryptoException>()),
    );
  });

  test('decryptBytes rejects tampered payload authentication', () async {
    final random = SecureRandom();
    final crypto = CryptoService(random: random);
    final key = random.bytes(32);
    final payload = await crypto.encryptBytes(
      key: key,
      plaintext: utf8.encode('secret'),
    );
    final tamperedMac = Uint8List.fromList(payload.mac);
    tamperedMac[0] ^= 0x01;

    expect(
      () => crypto.decryptBytes(
        key: key,
        payload: EncryptedPayload(
          nonce: payload.nonce,
          ciphertext: payload.ciphertext,
          mac: tamperedMac,
        ),
      ),
      throwsA(isA<CryptoException>()),
    );
  });

  test('non-ASCII master passwords derive UTF-8 compatible keys', () async {
    final random = SecureRandom();
    final kdf = KdfService();
    final crypto = CryptoService(random: random);
    final password = 'p\u{00E4}ssw\u{00F6}rd\u{1F510}\u{6F22}\u{5B57}';
    final salt = Uint8List.fromList(List<int>.generate(16, (index) => index));
    final params = KdfParams.pbkdf2();
    final dek = random.bytes(32);

    final derivedByService = await kdf.deriveKey(
      password: password,
      salt: salt,
      params: params,
    );
    final directAlgorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: params.iterations,
      bits: params.bits,
    );
    final utf8DerivedKey = Uint8List.fromList(
      await (await directAlgorithm.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      )).extractBytes(),
    );
    final encryptedDek = await crypto.encryptBytes(
      key: derivedByService,
      plaintext: dek,
    );

    expect(
      await crypto.decryptBytes(key: utf8DerivedKey, payload: encryptedDek),
      dek,
    );
  });
}
