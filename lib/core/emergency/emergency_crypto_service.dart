import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:hashlib/hashlib.dart';

class EmergencyKeyPairBundle {
  const EmergencyKeyPairBundle({
    required this.publicKey,
    required this.privateKey,
    required this.fingerprint,
  });

  final String publicKey;
  final String privateKey;
  final String fingerprint;
}

class EmergencyEncryptedPackage {
  const EmergencyEncryptedPackage({
    required this.encryptedRecoveryPackage,
    required this.packageAad,
    required this.packageFingerprint,
  });

  final String encryptedRecoveryPackage;
  final String packageAad;
  final String packageFingerprint;
}

class EmergencyCryptoException implements Exception {
  const EmergencyCryptoException(this.message);

  final String message;

  @override
  String toString() => 'EmergencyCryptoException: $message';
}

class EmergencyCryptoService {
  EmergencyCryptoService({
    X25519? keyExchange,
    AesGcm? cipher,
    Hkdf? kdf,
    Random? random,
  }) : _keyExchange = keyExchange ?? X25519(),
       _cipher = cipher ?? AesGcm.with256bits(),
       _kdf = kdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
       _random = random ?? Random.secure();

  final X25519 _keyExchange;
  final AesGcm _cipher;
  final Hkdf _kdf;
  final Random _random;

  Future<EmergencyKeyPairBundle> generateKeyPair() async {
    final keyPair = await _keyExchange.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicBytes = publicKey.bytes;

    final publicToken = '$_publicPrefix.${_hex(publicBytes)}';
    return EmergencyKeyPairBundle(
      publicKey: publicToken,
      privateKey: '$_privatePrefix.${_hex(privateBytes)}',
      fingerprint: _fingerprintForPublicBytes(publicBytes),
    );
  }

  Future<String> fingerprintForPublicKey(String publicKey) async {
    return _fingerprintForPublicBytes(_decodeToken(publicKey, _publicPrefix));
  }

  Future<EmergencyEncryptedPackage> encryptPackage({
    required List<int> plaintext,
    required String recipientPublicKey,
    String? grantId,
    String? recipientKeyFingerprint,
  }) async {
    try {
      final recipientPublicBytes = _decodeToken(
        recipientPublicKey,
        _publicPrefix,
      );
      final recipientPublic = SimplePublicKey(
        recipientPublicBytes,
        type: KeyPairType.x25519,
      );
      final ephemeralKeyPair = await _keyExchange.newKeyPair();
      final ephemeralPublic = await ephemeralKeyPair.extractPublicKey();
      final sharedKey = await _keyExchange.sharedSecretKey(
        keyPair: ephemeralKeyPair,
        remotePublicKey: recipientPublic,
      );
      final packageAad = _encodePackageAad(
        mac: _hex(_randomBytes(32)),
        grantId: grantId,
        recipientKeyFingerprint:
            recipientKeyFingerprint ??
            _fingerprintForPublicBytes(recipientPublicBytes),
      );
      final wrappingKey = await _deriveWrappingKey(
        sharedKey: sharedKey,
        senderPublicBytes: ephemeralPublic.bytes,
        recipientPublicBytes: recipientPublicBytes,
      );
      final secretBox = await _cipher.encrypt(
        plaintext,
        secretKey: wrappingKey,
        aad: utf8.encode(packageAad),
      );
      final envelope = _encodeEnvelope(
        senderPublicBytes: ephemeralPublic.bytes,
        secretBox: secretBox,
      );
      return EmergencyEncryptedPackage(
        encryptedRecoveryPackage: envelope,
        packageAad: packageAad,
        packageFingerprint: _packageFingerprint(envelope, packageAad),
      );
    } catch (error) {
      if (error is EmergencyCryptoException) {
        rethrow;
      }
      throw const EmergencyCryptoException('Unable to encrypt package');
    }
  }

  Future<List<int>> decryptPackage({
    required String encryptedRecoveryPackage,
    required String packageAad,
    required String packageFingerprint,
    required String recipientPrivateKey,
  }) async {
    try {
      if (_packageFingerprint(encryptedRecoveryPackage, packageAad) !=
          packageFingerprint) {
        throw const EmergencyCryptoException('Package fingerprint mismatch');
      }

      final privateBytes = _decodeToken(recipientPrivateKey, _privatePrefix);
      final recipientKeyPair = await _keyExchange.newKeyPairFromSeed(
        privateBytes,
      );
      final recipientPublic = await recipientKeyPair.extractPublicKey();
      final aad = _decodePackageAad(packageAad);
      final aadRecipientFingerprint = aad['recipient_key_fingerprint'];
      if (aadRecipientFingerprint != null &&
          aadRecipientFingerprint !=
              _fingerprintForPublicBytes(recipientPublic.bytes)) {
        throw const EmergencyCryptoException('Recipient fingerprint mismatch');
      }

      final envelope = _decodeEnvelope(encryptedRecoveryPackage);
      final sharedKey = await _keyExchange.sharedSecretKey(
        keyPair: recipientKeyPair,
        remotePublicKey: SimplePublicKey(
          envelope.senderPublicBytes,
          type: KeyPairType.x25519,
        ),
      );
      final wrappingKey = await _deriveWrappingKey(
        sharedKey: sharedKey,
        senderPublicBytes: envelope.senderPublicBytes,
        recipientPublicBytes: recipientPublic.bytes,
      );
      return await _cipher.decrypt(
        envelope.secretBox,
        secretKey: wrappingKey,
        aad: utf8.encode(packageAad),
      );
    } catch (error) {
      if (error is EmergencyCryptoException) {
        rethrow;
      }
      throw const EmergencyCryptoException('Unable to decrypt package');
    }
  }

  Future<SecretKey> _deriveWrappingKey({
    required SecretKey sharedKey,
    required List<int> senderPublicBytes,
    required List<int> recipientPublicBytes,
  }) {
    return _kdf.deriveKey(
      secretKey: sharedKey,
      nonce: [
        ...utf8.encode(_schema),
        ...senderPublicBytes,
        ...recipientPublicBytes,
      ],
    );
  }

  List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }
}

const _publicPrefix = 'lockly-x25519-public-v1';
const _privatePrefix = 'lockly-x25519-private-v1';
const _schema = 'lockly-emergency-package-v1';
final _hexPattern = RegExp(r'^[0-9a-f]+$');

String _encodePackageAad({
  required String mac,
  String? grantId,
  String? recipientKeyFingerprint,
}) {
  final json = <String, String>{'schema': _schema, 'mac': mac};
  if (grantId != null) {
    json['grant_id'] = grantId;
  }
  if (recipientKeyFingerprint != null) {
    json['recipient_key_fingerprint'] = recipientKeyFingerprint;
  }
  return jsonEncode(json);
}

Map<String, String> _decodePackageAad(String encoded) {
  final decoded = _decodeObject(encoded, 'package_aad');
  if (decoded['schema'] != _schema) {
    throw const EmergencyCryptoException('Unsupported package AAD schema');
  }
  if (!decoded.containsKey('mac')) {
    throw const EmergencyCryptoException('Missing package AAD mac');
  }
  if (decoded['mac']!.isEmpty) {
    throw const EmergencyCryptoException('Invalid package AAD mac');
  }
  if (decoded['recipient_key_fingerprint'] case final fingerprint?
      when fingerprint.isEmpty) {
    throw const EmergencyCryptoException(
      'Invalid package AAD recipient fingerprint',
    );
  }
  final unsupported = decoded.keys.toSet().difference({
    'schema',
    'mac',
    'grant_id',
    'recipient_key_fingerprint',
  });
  if (unsupported.isNotEmpty) {
    throw const EmergencyCryptoException('Unsupported package AAD field');
  }
  return decoded;
}

String _encodeEnvelope({
  required List<int> senderPublicBytes,
  required SecretBox secretBox,
}) {
  return jsonEncode(<String, String>{
    'ciphertext': _hex([...senderPublicBytes, ...secretBox.cipherText]),
    'nonce': _hex(secretBox.nonce),
    'mac': _hex(secretBox.mac.bytes),
  });
}

_DecodedEnvelope _decodeEnvelope(String encoded) {
  final decoded = _decodeObject(encoded, 'encrypted_recovery_package');
  if (decoded.keys.toSet().length != 3 ||
      !decoded.containsKey('ciphertext') ||
      !decoded.containsKey('nonce') ||
      !decoded.containsKey('mac')) {
    throw const EmergencyCryptoException('Invalid package envelope shape');
  }
  final combinedCiphertext = _decodeHex(decoded['ciphertext']!);
  if (combinedCiphertext.length < 33) {
    throw const EmergencyCryptoException('Invalid package ciphertext');
  }
  final nonce = _decodeHex(decoded['nonce']!);
  final mac = _decodeHex(decoded['mac']!);
  if (nonce.length != 12 || mac.length != 16) {
    throw const EmergencyCryptoException('Invalid package envelope sizes');
  }
  return _DecodedEnvelope(
    senderPublicBytes: combinedCiphertext.sublist(0, 32),
    secretBox: SecretBox(
      combinedCiphertext.sublist(32),
      nonce: nonce,
      mac: Mac(mac),
    ),
  );
}

Map<String, String> _decodeObject(String encoded, String label) {
  final value = jsonDecode(encoded);
  if (value is! Map<String, Object?>) {
    throw EmergencyCryptoException('Invalid $label JSON');
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    final entryValue = entry.value;
    if (entryValue is! String) {
      throw EmergencyCryptoException('Invalid $label field');
    }
    result[entry.key] = entryValue;
  }
  return result;
}

List<int> _decodeToken(String token, String prefix) {
  if (!token.startsWith('$prefix.')) {
    throw const EmergencyCryptoException('Invalid emergency key token');
  }
  final bytes = _decodeHex(token.substring(prefix.length + 1));
  if (bytes.length != 32) {
    throw const EmergencyCryptoException('Invalid emergency key length');
  }
  return bytes;
}

String _fingerprintForPublicBytes(List<int> publicBytes) {
  return 'x25519-sha256.${sha256.convert(publicBytes).hex()}';
}

String _packageFingerprint(String envelope, String aad) {
  return 'pkg-sha256.${sha256.convert(utf8.encode('$envelope\n$aad')).hex()}';
}

String _hex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

List<int> _decodeHex(String value) {
  if (value.isEmpty || value.length.isOdd || !_hexPattern.hasMatch(value)) {
    throw const EmergencyCryptoException('Invalid hex value');
  }
  final bytes = <int>[];
  for (var index = 0; index < value.length; index += 2) {
    bytes.add(int.parse(value.substring(index, index + 2), radix: 16));
  }
  return bytes;
}

class _DecodedEnvelope {
  const _DecodedEnvelope({
    required this.senderPublicBytes,
    required this.secretBox,
  });

  final List<int> senderPublicBytes;
  final SecretBox secretBox;
}
