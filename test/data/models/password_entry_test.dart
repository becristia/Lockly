import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/data/models/vault_meta.dart';

void main() {
  test(
    'password entry serializes all sensitive fields inside one JSON payload',
    () {
      final entry = PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: 'recovery codes stored offline',
        tags: const ['dev', 'important'],
      );

      final encoded = jsonEncode(entry.toJson());
      final decoded = PasswordEntry.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );

      expect(decoded.title, 'GitHub');
      expect(decoded.website, 'https://github.com');
      expect(decoded.username, 'user@example.com');
      expect(decoded.password, 'secret-password');
      expect(decoded.notes, 'recovery codes stored offline');
      expect(decoded.tags, ['dev', 'important']);
    },
  );

  test('password entry rejects missing required fields', () {
    expect(
      () => PasswordEntry.fromJson({
        'title': 'GitHub',
        'website': 'https://github.com',
        'username': 'user@example.com',
        'password': 'secret-password',
        'notes': 'recovery codes stored offline',
      }),
      throwsFormatException,
    );
  });

  test('password entry rejects wrong field types', () {
    expect(
      () => PasswordEntry.fromJson({
        'title': 'GitHub',
        'website': 'https://github.com',
        'username': 'user@example.com',
        'password': 12345,
        'notes': 'recovery codes stored offline',
        'tags': const ['dev', 'important'],
      }),
      throwsFormatException,
    );
  });

  test(
    'password entry copies tags defensively and keeps serialized output stable',
    () {
      final sourceTags = <String>['dev', 'important'];
      final entry = PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: 'recovery codes stored offline',
        tags: sourceTags,
      );

      final encodedBeforeMutation = jsonEncode(entry.toJson());

      sourceTags.add('mutated');

      expect(identical(entry.tags, sourceTags), isFalse);
      expect(entry.tags, ['dev', 'important']);
      expect(jsonEncode(entry.toJson()), encodedBeforeMutation);
      expect(() => entry.tags.add('blocked'), throwsUnsupportedError);
    },
  );

  test('encrypted vault item round-trips through DB mapping', () {
    const item = EncryptedVaultItem(
      id: 'item-1',
      nonce: 'base64-nonce',
      ciphertext: 'base64-ciphertext',
      mac: 'base64-mac',
      createdAt: 1715550000,
      updatedAt: 1715551111,
      deletedAt: 1715552222,
    );

    final row = item.toDb();
    final decoded = EncryptedVaultItem.fromDb(row);

    expect(decoded.id, item.id);
    expect(decoded.nonce, item.nonce);
    expect(decoded.ciphertext, item.ciphertext);
    expect(decoded.mac, item.mac);
    expect(decoded.createdAt, item.createdAt);
    expect(decoded.updatedAt, item.updatedAt);
    expect(decoded.deletedAt, item.deletedAt);
  });

  test('encrypted vault item rejects malformed DB rows', () {
    expect(
      () => EncryptedVaultItem.fromDb({
        'id': 'item-1',
        'nonce': 123,
        'ciphertext': 'base64-ciphertext',
        'mac': 'base64-mac',
        'created_at': 1715550000,
        'updated_at': 1715551111,
        'deleted_at': null,
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('nonce'),
        ),
      ),
    );
  });

  test(
    'vault meta round-trips kdf params and biometric flag through DB mapping',
    () {
      final meta = VaultMeta(
        id: 'vault-1',
        version: 1,
        kdf: 'pbkdf2-hmac-sha256',
        kdfParams: KdfParams.pbkdf2(iterations: 180000, bits: 256),
        salt: 'base64-salt',
        encryptedDekByMaster: 'encrypted-master',
        encryptedDekByMasterNonce: 'master-nonce',
        encryptedDekByMasterMac: 'master-mac',
        encryptedDekByBiometric: 'encrypted-bio',
        encryptedDekByBiometricNonce: 'bio-nonce',
        encryptedDekByBiometricMac: 'bio-mac',
        biometricEnabled: true,
        createdAt: 1715550000,
        updatedAt: 1715551111,
      );

      final row = meta.toDb();
      final decoded = VaultMeta.fromDb(row);
      final kdfParamsJson = jsonDecode(row['kdf_params']! as String);

      expect(row['biometric_enabled'], 1);
      expect(kdfParamsJson, {
        'name': 'pbkdf2-hmac-sha256',
        'iterations': 180000,
        'bits': 256,
      });
      expect(decoded.id, meta.id);
      expect(decoded.version, meta.version);
      expect(decoded.kdf, meta.kdf);
      expect(decoded.kdfParams.name, meta.kdfParams.name);
      expect(decoded.kdfParams.iterations, meta.kdfParams.iterations);
      expect(decoded.kdfParams.bits, meta.kdfParams.bits);
      expect(decoded.salt, meta.salt);
      expect(decoded.encryptedDekByMaster, meta.encryptedDekByMaster);
      expect(decoded.encryptedDekByMasterNonce, meta.encryptedDekByMasterNonce);
      expect(decoded.encryptedDekByMasterMac, meta.encryptedDekByMasterMac);
      expect(decoded.encryptedDekByBiometric, meta.encryptedDekByBiometric);
      expect(
        decoded.encryptedDekByBiometricNonce,
        meta.encryptedDekByBiometricNonce,
      );
      expect(
        decoded.encryptedDekByBiometricMac,
        meta.encryptedDekByBiometricMac,
      );
      expect(decoded.biometricEnabled, isTrue);
      expect(decoded.createdAt, meta.createdAt);
      expect(decoded.updatedAt, meta.updatedAt);
    },
  );

  test('vault meta rejects mismatched kdf and kdf params name from DB', () {
    expect(
      () => VaultMeta.fromDb(
        _vaultMetaRow(
          kdfParams: jsonEncode({
            'name': 'argon2id',
            'iterations': 180000,
            'bits': 256,
          }),
        ),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          allOf(contains('kdf'), contains('kdf_params.name')),
        ),
      ),
    );
  });

  test('vault meta rejects mismatched kdf and kdf params name in memory', () {
    expect(
      () => VaultMeta(
        id: 'vault-1',
        version: 1,
        kdf: 'argon2id',
        kdfParams: KdfParams.pbkdf2(iterations: 180000, bits: 256),
        salt: 'base64-salt',
        encryptedDekByMaster: 'encrypted-master',
        encryptedDekByMasterNonce: 'master-nonce',
        encryptedDekByMasterMac: 'master-mac',
        biometricEnabled: false,
        createdAt: 1715550000,
        updatedAt: 1715551111,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message.toString(),
          'message',
          allOf(contains('kdf'), contains('kdfParams.name')),
        ),
      ),
    );
  });

  test(
    'vault meta rejects biometricEnabled true without biometric DEK tuple in memory',
    () {
      expect(
        () => VaultMeta(
          id: 'vault-1',
          version: 1,
          kdf: 'pbkdf2-hmac-sha256',
          kdfParams: KdfParams.pbkdf2(iterations: 180000, bits: 256),
          salt: 'base64-salt',
          encryptedDekByMaster: 'encrypted-master',
          encryptedDekByMasterNonce: 'master-nonce',
          encryptedDekByMasterMac: 'master-mac',
          biometricEnabled: true,
          createdAt: 1715550000,
          updatedAt: 1715551111,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(
              contains('biometricEnabled'),
              contains('encryptedDekByBiometric'),
            ),
          ),
        ),
      );
    },
  );

  test('vault meta rejects malformed kdf params json text', () {
    expect(
      () => VaultMeta.fromDb(
        _vaultMetaRow(kdfParams: '{"name": "pbkdf2-hmac-sha256"'),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains('kdf_params'),
        ),
      ),
    );
  });

  test('vault meta decodes biometric_enabled zero as false', () {
    final decoded = VaultMeta.fromDb(_vaultMetaRow(biometricEnabled: 0));

    expect(decoded.biometricEnabled, isFalse);
  });

  test(
    'vault meta rejects biometric_enabled values other than zero or one',
    () {
      expect(
        () => VaultMeta.fromDb(_vaultMetaRow(biometricEnabled: 2)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message.toString(),
            'message',
            contains('biometric_enabled'),
          ),
        ),
      );
    },
  );

  test(
    'vault meta rejects biometric_enabled zero with persisted biometric DEK tuple from DB',
    () {
      expect(
        () => VaultMeta.fromDb(
          _vaultMetaRow(
            biometricEnabled: 0,
            encryptedDekByBiometric: 'encrypted-bio',
            encryptedDekByBiometricNonce: 'bio-nonce',
            encryptedDekByBiometricMac: 'bio-mac',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message.toString(),
            'message',
            allOf(
              contains('biometric_enabled'),
              contains('encrypted_dek_by_biometric'),
            ),
          ),
        ),
      );
    },
  );
}

Map<String, Object?> _vaultMetaRow({
  String kdf = 'pbkdf2-hmac-sha256',
  String? kdfParams,
  int biometricEnabled = 0,
  String? encryptedDekByBiometric,
  String? encryptedDekByBiometricNonce,
  String? encryptedDekByBiometricMac,
}) {
  return {
    'id': 'vault-1',
    'version': 1,
    'kdf': kdf,
    'kdf_params': kdfParams ?? jsonEncode(KdfParams.pbkdf2().toJson()),
    'salt': 'base64-salt',
    'encrypted_dek_by_master': 'encrypted-master',
    'encrypted_dek_by_master_nonce': 'master-nonce',
    'encrypted_dek_by_master_mac': 'master-mac',
    'encrypted_dek_by_biometric': encryptedDekByBiometric,
    'encrypted_dek_by_biometric_nonce': encryptedDekByBiometricNonce,
    'encrypted_dek_by_biometric_mac': encryptedDekByBiometricMac,
    'biometric_enabled': biometricEnabled,
    'created_at': 1715550000,
    'updated_at': 1715551111,
  };
}
