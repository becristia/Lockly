import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_crypto.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';

void main() {
  LanTransferCrypto transferCrypto() {
    final random = SecureRandom();
    return LanTransferCrypto(
      crypto: CryptoService(random: random),
      random: random,
    );
  }

  test('encrypts and decrypts a transfer package roundtrip', () async {
    final lanCrypto = transferCrypto();
    final key = lanCrypto.randomTransferKey();
    final plaintext = Uint8List.fromList(utf8.encode('{"items":[1,2,3]}'));

    final envelope = await lanCrypto.encryptPackage(
      plaintext: plaintext,
      key: key,
    );
    final decrypted = await lanCrypto.decryptPackage(
      envelope: envelope,
      key: key,
    );

    expect(decrypted, plaintext);
    expect(envelope.contentLength, plaintext.length);
    expect(envelope.packageSha256, hashlib.sha256.convert(plaintext).hex());
  });

  test('uses randomized ciphertext for the same plaintext and key', () async {
    final lanCrypto = transferCrypto();
    final key = lanCrypto.randomTransferKey();
    final plaintext = Uint8List.fromList(utf8.encode('same payload'));

    final first = await lanCrypto.encryptPackage(
      plaintext: plaintext,
      key: key,
    );
    final second = await lanCrypto.encryptPackage(
      plaintext: plaintext,
      key: key,
    );

    expect(first.nonce, isNot(second.nonce));
    expect(first.ciphertext, isNot(second.ciphertext));
    expect(
      await lanCrypto.decryptPackage(envelope: first, key: key),
      plaintext,
    );
    expect(
      await lanCrypto.decryptPackage(envelope: second, key: key),
      plaintext,
    );
  });

  test('calculates packageSha256 as sha256 of plaintext bytes', () async {
    final lanCrypto = transferCrypto();
    final plaintext = Uint8List.fromList(List<int>.generate(64, (i) => i));

    expect(
      lanCrypto.sha256Hex(plaintext),
      hashlib.sha256.convert(plaintext).hex(),
    );

    final envelope = await lanCrypto.encryptPackage(
      plaintext: plaintext,
      key: lanCrypto.randomTransferKey(),
    );
    expect(envelope.packageSha256, lanCrypto.sha256Hex(plaintext));
  });

  test('encodes and decodes 32-byte transfer keys as QR-safe strings', () {
    final lanCrypto = transferCrypto();
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

    final encoded = lanCrypto.encodeTransferKey(key);
    final decoded = lanCrypto.decodeTransferKey(encoded);

    expect(encoded, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(encoded, isNot(contains('=')));
    expect(decoded, key);
  });

  test('rejects transfer keys that do not decode to exactly 32 bytes', () {
    final lanCrypto = transferCrypto();

    expect(
      () => lanCrypto.encodeTransferKey(
        Uint8List.fromList(List<int>.filled(31, 1)),
      ),
      throwsA(anyOf(isA<LanTransferFormatException>(), isA<CryptoException>())),
    );
    expect(
      () =>
          lanCrypto.decodeTransferKey(base64UrlEncode(List<int>.filled(31, 1))),
      throwsA(anyOf(isA<LanTransferFormatException>(), isA<CryptoException>())),
    );
    expect(
      () => lanCrypto.decodeTransferKey('not valid base64url'),
      throwsA(anyOf(isA<LanTransferFormatException>(), isA<CryptoException>())),
    );
  });

  test('generates random QR-safe tokens and 32-byte transfer keys', () {
    final lanCrypto = transferCrypto();

    final firstToken = lanCrypto.randomToken();
    final secondToken = lanCrypto.randomToken();
    final key = lanCrypto.randomTransferKey();

    expect(firstToken, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(firstToken, isNot(contains('=')));
    expect(firstToken.length, greaterThanOrEqualTo(32));
    expect(firstToken, isNot(secondToken));
    expect(key, hasLength(32));
  });

  test('tokenMatches only accepts exact token matches', () {
    final lanCrypto = transferCrypto();
    const expected = '0123456789abcdef0123456789abcdef';

    expect(lanCrypto.tokenMatches(expected, expected), isTrue);
    expect(
      lanCrypto.tokenMatches(expected, 'x123456789abcdef0123456789abcdef'),
      isFalse,
    );
    expect(
      lanCrypto.tokenMatches(expected, '0123456789abcdef0123456789abcdee'),
      isFalse,
    );
    expect(lanCrypto.tokenMatches(expected, '0123456789abcdef'), isFalse);
  });

  test('decryptPackage rejects content length and sha256 mismatches', () async {
    final lanCrypto = transferCrypto();
    final key = lanCrypto.randomTransferKey();
    final plaintext = Uint8List.fromList(utf8.encode('integrity checked'));
    final envelope = await lanCrypto.encryptPackage(
      plaintext: plaintext,
      key: key,
    );

    expect(
      () => lanCrypto.decryptPackage(
        envelope: LanTransferEnvelope(
          nonce: envelope.nonce,
          ciphertext: envelope.ciphertext,
          mac: envelope.mac,
          contentLength: plaintext.length + 1,
          packageSha256: envelope.packageSha256,
        ),
        key: key,
      ),
      throwsA(isA<CryptoException>()),
    );
    expect(
      () => lanCrypto.decryptPackage(
        envelope: LanTransferEnvelope(
          nonce: envelope.nonce,
          ciphertext: envelope.ciphertext,
          mac: envelope.mac,
          contentLength: envelope.contentLength,
          packageSha256:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
        key: key,
      ),
      throwsA(isA<CryptoException>()),
    );
  });
}
