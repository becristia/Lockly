import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/backup/backup_service.dart';
import 'package:secure_box/core/sync/sync_backup_adapter.dart';
import 'package:secure_box/core/sync/sync_models.dart';

void main() {
  test(
    'cloud vault package converts ciphertext sync payloads to v2 backup',
    () {
      final meta = SyncVaultMetaPayload.fromJson({
        'id': 'vault-1',
        'kdf': 'argon2id',
        'kdf_params': {
          'name': 'argon2id',
          'memoryKiB': 65536,
          'iterations': 3,
          'parallelism': 1,
          'bits': 256,
        },
        'salt': 'salt-b64',
        'encrypted_dek_by_master': jsonEncode({
          'ciphertext': 'dek-ciphertext',
          'nonce': 'dek-nonce',
          'mac': 'dek-mac',
        }),
        'manifest': {
          'version': 1,
          'epoch': 1,
          'counter': 5,
          'nonce': 'manifest-nonce',
          'ciphertext': 'manifest-ciphertext',
          'mac': 'manifest-mac',
          'updated_at': 1715552222,
        },
        'revision': 2,
        'created_at': '2026-05-13T10:00:00Z',
        'updated_at': '2026-05-13T10:05:00Z',
      });
      final item = SyncItem.fromJson({
        'item_id': 'item-1',
        'ciphertext': 'item-ciphertext',
        'nonce': 'item-nonce',
        'aad': jsonEncode({'mac': 'item-mac', 'schema': 'lockly-item-v1'}),
        'revision': 7,
        'deleted': false,
        'client_updated_at': '2026-05-13T10:02:03.004Z',
        'created_at': 1778666400000,
        'updated_at': 1778666460000,
        'deleted_at': null,
        'server_updated_at': '2026-05-13T10:06:00Z',
      });

      final backup = cloudVaultBackupFromSync(meta: meta, items: [item]);
      final json = backup.toJson();

      expect(VaultBackup.fromJson(json).manifest!.counter, 5);
      expect(json['version'], 2);
      expect(json['magic'], 'secure-box-backup');
      expect(json['vault_id'], 'vault-1');
      expect(json['biometric_enabled'], isFalse);
      expect(json['encrypted_dek_by_biometric'], isNull);
      expect(json['encrypted_dek_by_master'], 'dek-ciphertext');
      expect(json['encrypted_dek_by_master_nonce'], 'dek-nonce');
      expect(json['encrypted_dek_by_master_mac'], 'dek-mac');
      expect(json['item_count'], 1);
      expect(json['history_count'], 0);
      expect(jsonEncode(json), isNot(contains('masterPassword')));
      expect(jsonEncode(json), isNot(contains('biometric-ciphertext')));

      final items = json['items']! as List<Object?>;
      final first = items.single! as Map<String, Object?>;
      expect(first['id'], 'item-1');
      expect(first['mac'], 'item-mac');
      expect(first['created_at'], 1778666400000);
      expect(first['updated_at'], 1778666460000);
    },
  );

  test(
    'cloud vault package preserves tombstones for manifest verification',
    () {
      final meta = SyncVaultMetaPayload.fromJson({
        'id': 'vault-1',
        'kdf': 'argon2id',
        'kdf_params': {
          'name': 'argon2id',
          'memoryKiB': 65536,
          'iterations': 3,
          'parallelism': 1,
          'bits': 256,
        },
        'salt': 'salt-b64',
        'encrypted_dek_by_master': jsonEncode({
          'ciphertext': 'dek-ciphertext',
          'nonce': 'dek-nonce',
          'mac': 'dek-mac',
        }),
        'manifest': {
          'version': 1,
          'epoch': 1,
          'counter': 5,
          'nonce': 'manifest-nonce',
          'ciphertext': 'manifest-ciphertext',
          'mac': 'manifest-mac',
          'updated_at': 1715552222,
        },
        'revision': 2,
        'created_at': '2026-05-13T10:00:00Z',
        'updated_at': '2026-05-13T10:05:00Z',
      });
      final item = SyncItem.fromJson({
        'item_id': 'item-deleted',
        'ciphertext': 'item-ciphertext',
        'nonce': 'item-nonce',
        'aad': jsonEncode({'mac': 'item-mac', 'schema': 'lockly-item-v1'}),
        'revision': 7,
        'deleted': true,
        'client_updated_at': '2026-05-13T10:02:03.004Z',
        'created_at': 1778666400000,
        'updated_at': 1778666460000,
        'deleted_at': 1778666523004,
        'server_updated_at': '2026-05-13T10:06:00Z',
      });
      final blob = SyncBlob.fromJson({
        'blob_id': 'blob-deleted',
        'item_id': 'item-deleted',
        'metadata_ciphertext': 'meta-ciphertext',
        'metadata_nonce': 'meta-nonce',
        'metadata_aad': jsonEncode({
          'mac': 'meta-mac',
          'schema': 'lockly-blob-meta-v1',
        }),
        'ciphertext': 'content-ciphertext',
        'nonce': 'content-nonce',
        'aad': jsonEncode({'mac': 'content-mac', 'schema': 'lockly-blob-v1'}),
        'ciphertext_sha256':
            'f5ea429c69de955b0c5055a56783ad618ca532d77f07be184d866c444515bd85',
        'ciphertext_size': 18,
        'revision': 3,
        'deleted': true,
        'client_updated_at': '2026-05-13T10:03:03.004Z',
        'created_at': 1778666401000,
        'updated_at': 1778666461000,
        'deleted_at': 1778666583004,
        'server_updated_at': '2026-05-13T10:06:00Z',
      });

      final backup = cloudVaultBackupFromSync(
        meta: meta,
        items: [item],
        blobs: [blob],
      );

      expect(backup.items.single.deletedAt, 1778666523004);
      expect(backup.blobs.single.deletedAt, 1778666583004);
      expect(backup.toJson()['items'], hasLength(1));
      expect(backup.toJson()['blobs'], hasLength(1));
    },
  );

  test('cloud vault package rejects missing manifest before import', () {
    final meta = SyncVaultMetaPayload.fromJson({
      'id': 'vault-1',
      'kdf': 'argon2id',
      'kdf_params': {
        'name': 'argon2id',
        'memoryKiB': 65536,
        'iterations': 3,
        'parallelism': 1,
        'bits': 256,
      },
      'salt': 'salt-b64',
      'encrypted_dek_by_master': jsonEncode({
        'ciphertext': 'dek-ciphertext',
        'nonce': 'dek-nonce',
        'mac': 'dek-mac',
      }),
      'revision': 2,
      'created_at': '2026-05-13T10:00:00Z',
      'updated_at': '2026-05-13T10:05:00Z',
    });

    expect(
      () => cloudVaultBackupFromSync(meta: meta, items: const []),
      throwsFormatException,
    );
  });

  test('cloud vault package rejects unsafe item aad before import', () {
    final meta = SyncVaultMetaPayload.fromJson({
      'id': 'vault-1',
      'kdf': 'argon2id',
      'kdf_params': {
        'name': 'argon2id',
        'memoryKiB': 65536,
        'iterations': 3,
        'parallelism': 1,
        'bits': 256,
      },
      'salt': 'salt-b64',
      'encrypted_dek_by_master': jsonEncode({
        'ciphertext': 'dek-ciphertext',
        'nonce': 'dek-nonce',
        'mac': 'dek-mac',
      }),
      'manifest': {
        'version': 1,
        'epoch': 1,
        'counter': 5,
        'nonce': 'manifest-nonce',
        'ciphertext': 'manifest-ciphertext',
        'mac': 'manifest-mac',
        'updated_at': 1715552222,
      },
      'revision': 2,
      'created_at': '2026-05-13T10:00:00Z',
      'updated_at': '2026-05-13T10:05:00Z',
    });

    expect(
      () => cloudVaultBackupFromSync(
        meta: meta,
        items: [
          SyncItem.fromJson({
            'item_id': 'item-1',
            'ciphertext': 'item-ciphertext',
            'nonce': 'item-nonce',
            'aad': jsonEncode({
              'mac': 'item-mac',
              'schema': 'lockly-item-v1',
              'username': 'alice',
            }),
            'revision': 7,
            'deleted': false,
            'client_updated_at': '2026-05-13T10:02:03.004Z',
            'server_updated_at': '2026-05-13T10:06:00Z',
          }),
        ],
      ),
      throwsFormatException,
    );
  });

  test('cloud vault package rejects unsafe vault metadata kdf params', () {
    expect(
      () => SyncVaultMetaPayload.fromJson({
        'id': 'vault-1',
        'kdf': 'argon2id',
        'kdf_params': {
          'name': 'argon2id',
          'memoryKiB': 65536,
          'iterations': 3,
          'parallelism': 1,
          'bits': 256,
          'apikey': 'raw-api-key',
        },
        'salt': 'salt-b64',
        'encrypted_dek_by_master': jsonEncode({
          'ciphertext': 'dek-ciphertext',
          'nonce': 'dek-nonce',
          'mac': 'dek-mac',
        }),
        'manifest': {
          'version': 1,
          'epoch': 1,
          'counter': 5,
          'nonce': 'manifest-nonce',
          'ciphertext': 'manifest-ciphertext',
          'mac': 'manifest-mac',
          'updated_at': 1715552222,
        },
        'revision': 2,
        'created_at': '2026-05-13T10:00:00Z',
        'updated_at': '2026-05-13T10:05:00Z',
      }),
      throwsFormatException,
    );
  });

  test(
    'cloud vault package rejects unsafe manifest and dek envelope fields',
    () {
      final base = {
        'id': 'vault-1',
        'kdf': 'argon2id',
        'kdf_params': {
          'name': 'argon2id',
          'memoryKiB': 65536,
          'iterations': 3,
          'parallelism': 1,
          'bits': 256,
        },
        'salt': 'salt-b64',
        'encrypted_dek_by_master': jsonEncode({
          'ciphertext': 'dek-ciphertext',
          'nonce': 'dek-nonce',
          'mac': 'dek-mac',
        }),
        'manifest': {
          'version': 1,
          'epoch': 1,
          'counter': 5,
          'nonce': 'manifest-nonce',
          'ciphertext': 'manifest-ciphertext',
          'mac': 'manifest-mac',
          'updated_at': 1715552222,
        },
        'revision': 2,
        'created_at': '2026-05-13T10:00:00Z',
        'updated_at': '2026-05-13T10:05:00Z',
      };

      expect(
        () => SyncVaultMetaPayload.fromJson({
          ...base,
          'manifest': {
            ...base['manifest']! as Map<String, Object?>,
            'title': 'Bank',
          },
        }),
        throwsFormatException,
      );
      expect(
        () => cloudVaultBackupFromSync(
          meta: SyncVaultMetaPayload.fromJson({
            ...base,
            'encrypted_dek_by_master': jsonEncode({
              'ciphertext': 'dek-ciphertext',
              'nonce': 'dek-nonce',
              'mac': 'dek-mac',
              'email': 'user@example.test',
            }),
          }),
          items: const [],
        ),
        throwsFormatException,
      );
      expect(
        () => SyncVaultMetaPayload.fromJson({
          ...base,
          'encrypted_dek_by_master': jsonEncode({
            'ciphertext': 'rawdek-plaintext-password',
            'nonce': 'dek-nonce',
            'mac': 'dek-mac',
          }),
        }),
        throwsFormatException,
      );
      expect(
        () => SyncVaultMetaPayload.fromJson({
          ...base,
          'manifest': {
            ...base['manifest']! as Map<String, Object?>,
            'mac': 'plaintext-password',
          },
        }),
        throwsFormatException,
      );
    },
  );
}
