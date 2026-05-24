import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hashlib/hashlib.dart';
import 'package:secure_box/core/emergency/emergency_crypto_service.dart';
import 'package:secure_box/core/sync/sync_models.dart';

void main() {
  group('EmergencyCryptoService', () {
    late EmergencyCryptoService service;

    setUp(() {
      service = EmergencyCryptoService();
    });

    test(
      'generates parseable safe key tokens and matching fingerprint',
      () async {
        final keyPair = await service.generateKeyPair();

        expect(keyPair.publicKey, matches(_publicKeyTokenPattern));
        expect(keyPair.privateKey, matches(_privateKeyTokenPattern));
        expect(keyPair.fingerprint, matches(_fingerprintPattern));
        expect(
          await service.fingerprintForPublicKey(keyPair.publicKey),
          keyPair.fingerprint,
        );
      },
    );

    test('encrypts and decrypts package plaintext for the recipient', () async {
      final recipient = await service.generateKeyPair();
      final plaintext = utf8.encode('client recovery material 42');

      final encrypted = await service.encryptPackage(
        plaintext: plaintext,
        recipientPublicKey: recipient.publicKey,
        grantId: 'grant-1',
        recipientKeyFingerprint: recipient.fingerprint,
      );

      final decrypted = await service.decryptPackage(
        encryptedRecoveryPackage: encrypted.encryptedRecoveryPackage,
        packageAad: encrypted.packageAad,
        packageFingerprint: encrypted.packageFingerprint,
        recipientPrivateKey: recipient.privateKey,
      );

      expect(utf8.decode(decrypted), 'client recovery material 42');
    });

    test(
      'defaults package aad to the recipient public key fingerprint',
      () async {
        final recipient = await service.generateKeyPair();
        final wrongRecipient = await service.generateKeyPair();

        final encrypted = await service.encryptPackage(
          plaintext: utf8.encode('default fingerprint binding material'),
          recipientPublicKey: recipient.publicKey,
          grantId: 'grant-1',
        );

        final packageAad =
            jsonDecode(encrypted.packageAad) as Map<String, Object?>;
        expect(packageAad['recipient_key_fingerprint'], recipient.fingerprint);

        packageAad['recipient_key_fingerprint'] = wrongRecipient.fingerprint;
        final tamperedAad = jsonEncode(packageAad);

        await expectLater(
          service.decryptPackage(
            encryptedRecoveryPackage: encrypted.encryptedRecoveryPackage,
            packageAad: tamperedAad,
            packageFingerprint: _packageFingerprint(
              encrypted.encryptedRecoveryPackage,
              tamperedAad,
            ),
            recipientPrivateKey: recipient.privateKey,
          ),
          throwsA(isA<EmergencyCryptoException>()),
        );
      },
    );

    test('generates package values accepted by emergency grant DTO', () async {
      final recipient = await service.generateKeyPair();

      final encrypted = await service.encryptPackage(
        plaintext: utf8.encode('compact recovery package bytes'),
        recipientPublicKey: recipient.publicKey,
        grantId: 'grant-1',
        recipientKeyFingerprint: recipient.fingerprint,
      );

      final request = EmergencyGrantCreateRequest(
        contactId: 'contact-1',
        waitingPeriodHours: 48,
        encryptedRecoveryPackage: encrypted.encryptedRecoveryPackage,
        packageAad: encrypted.packageAad,
        packageFingerprint: encrypted.packageFingerprint,
      );

      expect(request.toJson(), {
        'contact_id': 'contact-1',
        'waiting_period_hours': 48,
        'encrypted_recovery_package': encrypted.encryptedRecoveryPackage,
        'package_aad': encrypted.packageAad,
        'package_fingerprint': encrypted.packageFingerprint,
      });
    });

    test('does not expose plaintext or forbidden recovery fields', () async {
      final recipient = await service.generateKeyPair();

      final encrypted = await service.encryptPackage(
        plaintext: utf8.encode('unique-client-material-8675309'),
        recipientPublicKey: recipient.publicKey,
        grantId: 'grant-1',
        recipientKeyFingerprint: recipient.fingerprint,
      );

      final wirePayload =
          '${encrypted.encryptedRecoveryPackage}\n'
          '${encrypted.packageAad}\n'
          '${encrypted.packageFingerprint}';

      expect(wirePayload, isNot(contains('unique-client-material-8675309')));
      for (final marker in _forbiddenMarkers) {
        expect(wirePayload.toLowerCase(), isNot(contains(marker)));
      }
      expect(wirePayload, isNot(contains(recipient.privateKey)));
    });

    test('rejects tampered ciphertext, mac, aad, and fingerprint', () async {
      final recipient = await service.generateKeyPair();
      final encrypted = await service.encryptPackage(
        plaintext: utf8.encode('tamper test material'),
        recipientPublicKey: recipient.publicKey,
        grantId: 'grant-1',
        recipientKeyFingerprint: recipient.fingerprint,
      );

      await expectLater(
        service.decryptPackage(
          encryptedRecoveryPackage: _tamperJsonField(
            encrypted.encryptedRecoveryPackage,
            'ciphertext',
          ),
          packageAad: encrypted.packageAad,
          packageFingerprint: encrypted.packageFingerprint,
          recipientPrivateKey: recipient.privateKey,
        ),
        throwsA(isA<EmergencyCryptoException>()),
      );
      await expectLater(
        service.decryptPackage(
          encryptedRecoveryPackage: _tamperJsonField(
            encrypted.encryptedRecoveryPackage,
            'mac',
          ),
          packageAad: encrypted.packageAad,
          packageFingerprint: encrypted.packageFingerprint,
          recipientPrivateKey: recipient.privateKey,
        ),
        throwsA(isA<EmergencyCryptoException>()),
      );
      await expectLater(
        service.decryptPackage(
          encryptedRecoveryPackage: encrypted.encryptedRecoveryPackage,
          packageAad: _tamperJsonField(encrypted.packageAad, 'mac'),
          packageFingerprint: encrypted.packageFingerprint,
          recipientPrivateKey: recipient.privateKey,
        ),
        throwsA(isA<EmergencyCryptoException>()),
      );
      await expectLater(
        service.decryptPackage(
          encryptedRecoveryPackage: encrypted.encryptedRecoveryPackage,
          packageAad: encrypted.packageAad,
          packageFingerprint: _tamperToken(encrypted.packageFingerprint),
          recipientPrivateKey: recipient.privateKey,
        ),
        throwsA(isA<EmergencyCryptoException>()),
      );
    });

    test('rejects decryption with a different recipient private key', () async {
      final recipient = await service.generateKeyPair();
      final wrongRecipient = await service.generateKeyPair();
      final encrypted = await service.encryptPackage(
        plaintext: utf8.encode('recipient-bound material'),
        recipientPublicKey: recipient.publicKey,
        grantId: 'grant-1',
        recipientKeyFingerprint: recipient.fingerprint,
      );

      await expectLater(
        service.decryptPackage(
          encryptedRecoveryPackage: encrypted.encryptedRecoveryPackage,
          packageAad: encrypted.packageAad,
          packageFingerprint: encrypted.packageFingerprint,
          recipientPrivateKey: wrongRecipient.privateKey,
        ),
        throwsA(isA<EmergencyCryptoException>()),
      );
    });

    test('rejects recipient fingerprint mismatch in aad', () async {
      final recipient = await service.generateKeyPair();
      final encrypted = await service.encryptPackage(
        plaintext: utf8.encode('fingerprint-bound material'),
        recipientPublicKey: recipient.publicKey,
        grantId: 'grant-1',
        recipientKeyFingerprint: _zeroFingerprint,
      );

      await expectLater(
        service.decryptPackage(
          encryptedRecoveryPackage: encrypted.encryptedRecoveryPackage,
          packageAad: encrypted.packageAad,
          packageFingerprint: encrypted.packageFingerprint,
          recipientPrivateKey: recipient.privateKey,
        ),
        throwsA(isA<EmergencyCryptoException>()),
      );
    });

    test('rejects empty package aad mac and recipient fingerprint', () async {
      final recipient = await service.generateKeyPair();
      final encrypted = await service.encryptPackage(
        plaintext: utf8.encode('non-empty aad field material'),
        recipientPublicKey: recipient.publicKey,
        grantId: 'grant-1',
        recipientKeyFingerprint: recipient.fingerprint,
      );

      final emptyMacAad = _replaceJsonStringField(
        encrypted.packageAad,
        'mac',
        '',
      );
      await expectLater(
        service.decryptPackage(
          encryptedRecoveryPackage: encrypted.encryptedRecoveryPackage,
          packageAad: emptyMacAad,
          packageFingerprint: _packageFingerprint(
            encrypted.encryptedRecoveryPackage,
            emptyMacAad,
          ),
          recipientPrivateKey: recipient.privateKey,
        ),
        throwsA(
          isA<EmergencyCryptoException>().having(
            (error) => error.message,
            'message',
            'Invalid package AAD mac',
          ),
        ),
      );

      final emptyRecipientFingerprintAad = _replaceJsonStringField(
        encrypted.packageAad,
        'recipient_key_fingerprint',
        '',
      );
      await expectLater(
        service.decryptPackage(
          encryptedRecoveryPackage: encrypted.encryptedRecoveryPackage,
          packageAad: emptyRecipientFingerprintAad,
          packageFingerprint: _packageFingerprint(
            encrypted.encryptedRecoveryPackage,
            emptyRecipientFingerprintAad,
          ),
          recipientPrivateKey: recipient.privateKey,
        ),
        throwsA(
          isA<EmergencyCryptoException>().having(
            (error) => error.message,
            'message',
            'Invalid package AAD recipient fingerprint',
          ),
        ),
      );
    });
  });
}

final _publicKeyTokenPattern = RegExp(
  r'^lockly-x25519-public-v1\.[0-9a-f]{64}$',
);
final _privateKeyTokenPattern = RegExp(
  r'^lockly-x25519-private-v1\.[0-9a-f]{64}$',
);
final _fingerprintPattern = RegExp(r'^x25519-sha256\.[0-9a-f]{64}$');
final _zeroFingerprint = 'x25519-sha256.${'0' * 64}';

const _forbiddenMarkers = {
  'masterpassword',
  'masterkey',
  'rawkek',
  'rawdek',
  'recoveryplaintext',
  'recipientprivatekey',
  'wrappedprivatekey',
  'passkeyprivatematerial',
  'passkeyprivatekey',
  'itemplaintext',
  'filebytes',
  'privatekey',
  'password',
  'plaintext',
  'secret',
  'totp',
  'passkey',
  'username',
  'note',
  'filename',
  'decrypted',
};

String _tamperJsonField(String encoded, String field) {
  final json = jsonDecode(encoded) as Map<String, Object?>;
  final value = json[field] as String;
  json[field] = _tamperToken(value);
  return jsonEncode(json);
}

String _replaceJsonStringField(String encoded, String field, String value) {
  final json = jsonDecode(encoded) as Map<String, Object?>;
  json[field] = value;
  return jsonEncode(json);
}

String _tamperToken(String value) {
  final replacement = value.endsWith('0') ? '1' : '0';
  return '${value.substring(0, value.length - 1)}$replacement';
}

String _packageFingerprint(String envelope, String aad) {
  return 'pkg-sha256.${sha256.convert(utf8.encode('$envelope\n$aad')).hex()}';
}
