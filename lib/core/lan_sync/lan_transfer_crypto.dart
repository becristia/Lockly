import 'dart:convert';
import 'dart:typed_data';

import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';

class LanTransferCrypto {
  const LanTransferCrypto({
    required CryptoService crypto,
    required SecureRandom random,
  }) : _crypto = crypto,
       _random = random;

  final CryptoService _crypto;
  final SecureRandom _random;

  String randomToken() => encodeLanTransferBase64UrlNoPadding(
    _random.bytes(lanTransferSecretByteLength),
  );

  Uint8List randomTransferKey() => _random.bytes(lanTransferSecretByteLength);

  String encodeTransferKey(Uint8List key) {
    _validateTransferKey(key);
    return encodeLanTransferBase64UrlNoPadding(key);
  }

  Uint8List decodeTransferKey(String value) {
    final decoded = decodeLanTransferBase64UrlNoPadding(
      value,
      fieldName: 'Transfer key',
      expectedEncodedLength: lanTransferSecretEncodedLength,
      expectedByteLength: lanTransferSecretByteLength,
    );
    _validateTransferKey(decoded);
    return decoded;
  }

  String sha256Hex(List<int> bytes) => hashlib.sha256.convert(bytes).hex();

  bool tokenMatches(String expected, String actual) {
    final expectedBytes = utf8.encode(expected);
    final actualBytes = utf8.encode(actual);
    if (expectedBytes.length != actualBytes.length) {
      return false;
    }

    var difference = 0;
    for (var i = 0; i < expectedBytes.length; i++) {
      difference |= expectedBytes[i] ^ actualBytes[i];
    }
    return difference == 0;
  }

  Future<LanTransferEnvelope> encryptPackage({
    required Uint8List plaintext,
    required Uint8List key,
  }) async {
    final payload = await _crypto.encryptBytes(key: key, plaintext: plaintext);
    return LanTransferEnvelope(
      nonce: payload.nonce,
      ciphertext: payload.ciphertext,
      mac: payload.mac,
      contentLength: plaintext.length,
      packageSha256: sha256Hex(plaintext),
    );
  }

  Future<Uint8List> decryptPackage({
    required LanTransferEnvelope envelope,
    required Uint8List key,
  }) async {
    final plaintext = await _crypto.decryptBytes(
      key: key,
      payload: EncryptedPayload(
        nonce: envelope.nonce,
        ciphertext: envelope.ciphertext,
        mac: envelope.mac,
      ),
    );
    if (plaintext.length != envelope.contentLength) {
      throw const CryptoException('Transfer content length mismatch');
    }
    if (sha256Hex(plaintext) != envelope.packageSha256) {
      throw const CryptoException('Transfer package SHA-256 mismatch');
    }
    return plaintext;
  }

  void _validateTransferKey(Uint8List key) {
    if (key.length != lanTransferSecretByteLength) {
      throw const CryptoException('Transfer key must be 32 bytes');
    }
  }
}
