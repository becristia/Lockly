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
    'vault meta round-trips kdf params and biometric flag without requiring a legacy biometric tuple',
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
      expect(decoded.encryptedDekByBiometric, isNull);
      expect(decoded.encryptedDekByBiometricNonce, isNull);
      expect(decoded.encryptedDekByBiometricMac, isNull);
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
    'vault meta allows biometricEnabled true without biometric DEK tuple in memory',
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
        biometricEnabled: true,
        createdAt: 1715550000,
        updatedAt: 1715551111,
      );

      expect(meta.biometricEnabled, isTrue);
      expect(meta.encryptedDekByBiometric, isNull);
      expect(meta.encryptedDekByBiometricNonce, isNull);
      expect(meta.encryptedDekByBiometricMac, isNull);
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

  test('vault meta rejects malformed required DB column types', () {
    final malformedIdRow = _vaultMetaRow()..['id'] = 123;
    final malformedVersionRow = _vaultMetaRow()..['version'] = '1';

    expect(
      () => VaultMeta.fromDb(malformedIdRow),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains('id'),
        ),
      ),
    );
    expect(
      () => VaultMeta.fromDb(malformedVersionRow),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains('version'),
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
    'vault meta allows legacy biometric tuple when biometric_enabled is zero',
    () {
      final decoded = VaultMeta.fromDb(
        _vaultMetaRow(
          biometricEnabled: 0,
          encryptedDekByBiometric: 'encrypted-bio',
          encryptedDekByBiometricNonce: 'bio-nonce',
          encryptedDekByBiometricMac: 'bio-mac',
        ),
      );

      expect(decoded.biometricEnabled, isFalse);
      expect(decoded.encryptedDekByBiometric, 'encrypted-bio');
      expect(decoded.encryptedDekByBiometricNonce, 'bio-nonce');
      expect(decoded.encryptedDekByBiometricMac, 'bio-mac');
    },
  );

  test(
    'vault meta scrubs legacy biometric tuple when biometric is disabled during serialization',
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
        biometricEnabled: false,
        createdAt: 1715550000,
        updatedAt: 1715551111,
        encryptedDekByBiometric: 'encrypted-bio',
        encryptedDekByBiometricNonce: 'bio-nonce',
        encryptedDekByBiometricMac: 'bio-mac',
      );

      final row = meta.toDb();

      expect(row['biometric_enabled'], 0);
      expect(row['encrypted_dek_by_biometric'], isNull);
      expect(row['encrypted_dek_by_biometric_nonce'], isNull);
      expect(row['encrypted_dek_by_biometric_mac'], isNull);
    },
  );

  test('vault meta rejects malformed optional biometric tuple field types', () {
    final malformedBiometricFieldRow = _vaultMetaRow(
      biometricEnabled: 1,
      encryptedDekByBiometric: 'encrypted-bio',
      encryptedDekByBiometricNonce: 'bio-nonce',
      encryptedDekByBiometricMac: 'bio-mac',
    )..['encrypted_dek_by_biometric_nonce'] = 123;

    expect(
      () => VaultMeta.fromDb(malformedBiometricFieldRow),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains('encrypted_dek_by_biometric_nonce'),
        ),
      ),
    );
  });
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
