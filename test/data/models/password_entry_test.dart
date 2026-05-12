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

  test('password entry stores tags as an immutable copy', () {
    final sourceTags = <String>['dev', 'important'];
    final entry = PasswordEntry(
      title: 'GitHub',
      website: 'https://github.com',
      username: 'user@example.com',
      password: 'secret-password',
      notes: 'recovery codes stored offline',
      tags: sourceTags,
    );

    sourceTags.add('mutated');

    expect(entry.tags, ['dev', 'important']);
    expect(() => entry.tags.add('new-tag'), throwsUnsupportedError);
  });

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

  test('vault meta decodes biometric_enabled zero as false', () {
    final decoded = VaultMeta.fromDb({
      'id': 'vault-1',
      'version': 1,
      'kdf': 'pbkdf2-hmac-sha256',
      'kdf_params': jsonEncode(KdfParams.pbkdf2().toJson()),
      'salt': 'base64-salt',
      'encrypted_dek_by_master': 'encrypted-master',
      'encrypted_dek_by_master_nonce': 'master-nonce',
      'encrypted_dek_by_master_mac': 'master-mac',
      'encrypted_dek_by_biometric': null,
      'encrypted_dek_by_biometric_nonce': null,
      'encrypted_dek_by_biometric_mac': null,
      'biometric_enabled': 0,
      'created_at': 1715550000,
      'updated_at': 1715551111,
    });

    expect(decoded.biometricEnabled, isFalse);
  });
}
