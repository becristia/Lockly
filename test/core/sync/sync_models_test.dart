import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/core/sync/sync_payload_guard.dart';
import 'package:secure_box/data/models/encrypted_vault_blob.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/passkey_record.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/data/models/vault_manifest.dart';
import 'package:secure_box/data/models/vault_meta.dart';

void main() {
  final activeUpdatedAt = DateTime.utc(
    2026,
    5,
    13,
    10,
    0,
    11,
    111,
  ).millisecondsSinceEpoch;
  final deletedAt = DateTime.utc(
    2026,
    5,
    13,
    10,
    0,
    22,
    222,
  ).millisecondsSinceEpoch;

  test('vault meta upload payload contains only ciphertext-safe fields', () {
    final meta = VaultMeta(
      id: 'vault-1',
      version: 1,
      kdf: 'argon2id',
      kdfParams: KdfParams.argon2id(
        memoryKiB: 65536,
        iterations: 3,
        parallelism: 1,
        bits: 256,
      ),
      salt: 'base64-salt',
      encryptedDekByMaster: 'dek-ciphertext',
      encryptedDekByMasterNonce: 'dek-nonce',
      encryptedDekByMasterMac: 'dek-mac',
      biometricEnabled: true,
      encryptedDekByBiometric: 'biometric-ciphertext',
      encryptedDekByBiometricNonce: 'biometric-nonce',
      encryptedDekByBiometricMac: 'biometric-mac',
      createdAt: 1715550000,
      updatedAt: 1715551111,
    );

    const manifest = VaultManifest(
      version: 1,
      epoch: 1,
      counter: 4,
      nonce: 'manifest-nonce',
      ciphertext: 'manifest-ciphertext',
      mac: 'manifest-mac',
      updatedAt: 1715552222,
    );

    final dto = SyncVaultMetaPayload.fromLocal(
      meta,
      manifest: manifest,
      revision: 9,
    );
    final json = dto.toJson();
    final dekEnvelope = jsonDecode(json['encrypted_dek_by_master']! as String);

    expect(json.keys, {
      'kdf',
      'kdf_params',
      'salt',
      'encrypted_dek_by_master',
      'manifest',
      'revision',
    });
    expect(dekEnvelope, {
      'ciphertext': 'dek-ciphertext',
      'nonce': 'dek-nonce',
      'mac': 'dek-mac',
    });
    expect(json['manifest'], {
      'version': 1,
      'epoch': 1,
      'counter': 4,
      'nonce': 'manifest-nonce',
      'ciphertext': 'manifest-ciphertext',
      'mac': 'manifest-mac',
      'updated_at': 1715552222,
    });
    expect(findForbiddenSyncFields(json), isEmpty);
    expect(jsonEncode(json), isNot(contains('biometric')));
  });

  test('sync item upload payload contains only ciphertext-safe fields', () {
    final plaintextEntry = PasswordEntry(
      title: 'GitHub',
      website: 'https://github.com',
      username: 'alice',
      password: 'local-password',
      notes: '',
      tags: const ['passkey'],
      passkey: const PasskeyRecord(
        relyingPartyId: 'github.com',
        credentialId: 'credential-id',
        userHandle: 'user-handle',
        displayName: 'Alice',
        publicKeyAlgorithm: 'ES256',
        platform: 'android',
        platformReady: false,
      ),
    );
    final item = EncryptedVaultItem(
      id: 'item-1',
      nonce: 'item-nonce',
      ciphertext: 'item-ciphertext',
      mac: 'item-mac',
      createdAt: DateTime.utc(2026, 5, 13, 10).millisecondsSinceEpoch,
      updatedAt: activeUpdatedAt,
      deletedAt: null,
    );

    final dto = SyncItemPayload.fromLocal(item, revision: 12);
    final json = dto.toJson();
    final aadEnvelope = jsonDecode(json['aad']! as String);

    expect(plaintextEntry.toJson()['passkey'], isA<Map<String, Object?>>());
    expect(json.keys, {
      'ciphertext',
      'nonce',
      'aad',
      'revision',
      'deleted',
      'client_updated_at',
      'created_at',
      'updated_at',
      'deleted_at',
    });
    expect(aadEnvelope, {'mac': 'item-mac', 'schema': 'lockly-item-v1'});
    expect(json['deleted'], isFalse);
    expect(json['client_updated_at'], '2026-05-13T10:00:11.111Z');
    expect(
      json['created_at'],
      DateTime.utc(2026, 5, 13, 10).millisecondsSinceEpoch,
    );
    expect(json['updated_at'], activeUpdatedAt);
    expect(json['deleted_at'], isNull);
    expect(findForbiddenSyncFields(json), isEmpty);
    expect(json.containsKey('passkey'), isFalse);
    expect(jsonEncode(json), isNot(contains('credential-id')));
    expect(jsonEncode(json), isNot(contains('user-handle')));
    expect(jsonEncode(json), isNot(contains('github.com')));
  });

  test('sync item payload rejects unsafe aad before upload', () {
    final unsafeAadValues = [
      'cleartext',
      '{"mac":"mac","schema":"lockly-item-v1","username":"alice"}',
      '{"mac":"password=plaintext-secret","schema":"lockly-item-v1"}',
      '{"mac":"masterPassword","schema":"lockly-item-v1"}',
      '{"mac":"rawKey","schema":"lockly-item-v1"}',
      '[{"mac":"mac","schema":"lockly-item-v1"}]',
    ];

    for (final aad in unsafeAadValues) {
      expect(
        () => SyncItemPayload.fromJson({
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
          'aad': aad,
          'revision': 1,
          'deleted': false,
          'client_updated_at': '2026-05-13T10:00:00Z',
        }),
        throwsFormatException,
      );
    }
  });

  test('sync item aad allows opaque mac values with incidental words', () {
    final payload = SyncItemPayload.fromJson({
      'ciphertext': 'ciphertext',
      'nonce': 'nonce',
      'aad':
          '{"mac":"dek-note-password-key-passkey","schema":"lockly-item-v1"}',
      'revision': 1,
      'deleted': false,
      'client_updated_at': '2026-05-13T10:00:00Z',
    });

    expect(payload.aad, contains('dek-note-password-key-passkey'));
  });

  test('sync item upload payload marks soft-deleted encrypted rows', () {
    final item = EncryptedVaultItem(
      id: 'item-1',
      nonce: 'item-nonce',
      ciphertext: 'item-ciphertext',
      mac: 'item-mac',
      createdAt: DateTime.utc(2026, 5, 13, 10).millisecondsSinceEpoch,
      updatedAt: activeUpdatedAt,
      deletedAt: deletedAt,
    );

    final json = SyncItemPayload.fromLocal(item, revision: 13).toJson();

    expect(json['deleted'], isTrue);
    expect(json['client_updated_at'], '2026-05-13T10:00:22.222Z');
    expect(
      json['created_at'],
      DateTime.utc(2026, 5, 13, 10).millisecondsSinceEpoch,
    );
    expect(json['updated_at'], activeUpdatedAt);
    expect(json['deleted_at'], deletedAt);
    expect(findForbiddenSyncFields(json), isEmpty);
  });

  test('sync blob upload payload contains only encrypted blob fields', () {
    const blob = EncryptedVaultBlob(
      blobId: 'blob-1',
      itemId: 'item-1',
      metadataNonce: 'meta-nonce',
      metadataCiphertext: 'meta-ciphertext',
      metadataMac: 'meta-mac',
      nonce: 'content-nonce',
      ciphertext: 'content-ciphertext',
      mac: 'content-mac',
      createdAt: 1779494400000,
      updatedAt: 1779494411111,
    );

    final dto = SyncBlobPayload.fromLocal(blob, revision: 4);
    final json = dto.toJson();

    expect(json.keys, {
      'metadata_ciphertext',
      'metadata_nonce',
      'metadata_aad',
      'ciphertext',
      'nonce',
      'aad',
      'ciphertext_sha256',
      'ciphertext_size',
      'revision',
      'deleted',
      'client_updated_at',
      'created_at',
      'updated_at',
      'deleted_at',
    });
    expect(jsonDecode(json['metadata_aad']! as String), {
      'mac': 'meta-mac',
      'schema': 'lockly-blob-meta-v1',
    });
    expect(jsonDecode(json['aad']! as String), {
      'mac': 'content-mac',
      'schema': 'lockly-blob-v1',
    });
    expect(json['ciphertext_size'], 'content-ciphertext'.length);
    expect(json['deleted'], isFalse);
    expect(json['client_updated_at'], '2026-05-23T00:00:11.111Z');
    expect(json['created_at'], 1779494400000);
    expect(json['updated_at'], 1779494411111);
    expect(json['deleted_at'], isNull);
    expect(findForbiddenSyncFields(json), isEmpty);
  });

  test('sync DTOs preserve manifest timestamps from cloud payloads', () {
    final item = SyncItemPayload.fromJson({
      'ciphertext': 'ciphertext',
      'nonce': 'nonce',
      'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
      'revision': 4,
      'deleted': true,
      'client_updated_at': '2026-05-13T10:00:00Z',
      'created_at': 1778666400000,
      'updated_at': 1778666460000,
      'deleted_at': 1778666520000,
    });
    final blob = SyncBlobPayload.fromJson({
      'metadata_ciphertext': 'meta-ciphertext',
      'metadata_nonce': 'meta-nonce',
      'metadata_aad': '{"mac":"meta-mac","schema":"lockly-blob-meta-v1"}',
      'ciphertext': 'content-ciphertext',
      'nonce': 'content-nonce',
      'aad': '{"mac":"content-mac","schema":"lockly-blob-v1"}',
      'ciphertext_sha256':
          '32e09955ad05411c67617336e6a7026bd1828b3453f15f427b87667a61960d6e',
      'ciphertext_size': 18,
      'revision': 4,
      'deleted': true,
      'client_updated_at': '2026-05-13T10:01:00Z',
      'created_at': 1778666401000,
      'updated_at': 1778666461000,
      'deleted_at': 1778666521000,
    });

    expect(item.createdAt, 1778666400000);
    expect(item.updatedAt, 1778666460000);
    expect(item.deletedAt, 1778666520000);
    expect(blob.createdAt, 1778666401000);
    expect(blob.updatedAt, 1778666461000);
    expect(blob.deletedAt, 1778666521000);
  });

  test('sync blob DTOs reject unsafe fields and parse metadata-only conflicts', () {
    expect(
      () => SyncBlob.assertSafeRawBlobs([
        {
          'blob_id': 'blob-1',
          'item_id': 'item-1',
          'metadata_ciphertext': 'meta-ciphertext',
          'metadata_nonce': 'meta-nonce',
          'metadata_aad': '{"mac":"meta-mac","schema":"lockly-blob-meta-v1"}',
          'ciphertext': 'content-ciphertext',
          'nonce': 'content-nonce',
          'aad': '{"mac":"content-mac","schema":"lockly-blob-v1"}',
          'ciphertext_sha256':
              '32e09955ad05411c67617336e6a7026bd1828b3453f15f427b87667a61960d6e',
          'ciphertext_size': 18,
          'revision': 1,
          'deleted': false,
          'client_updated_at': '2026-05-23T09:00:00Z',
          'filename': 'recovery-codes.txt',
        },
      ]),
      throwsFormatException,
    );
    expect(
      () => SyncBlobConflict.fromJson({
        'blob_id': 'blob-1',
        'client_revision': 2,
        'server_revision': 3,
      }),
      returnsNormally,
    );
    expect(
      SyncBlobPushResponse.fromJson({
        'applied': <Object?>[],
        'conflicts': [
          {'blob_id': 'blob-1', 'client_revision': 2, 'server_revision': 3},
        ],
      }).conflicts.single.toJson().keys,
      {'blob_id', 'client_revision', 'server_revision'},
    );
    expect(
      () => SyncBlobPullResponse.fromJson({
        'server_time': '2026-05-23T10:00:00Z',
        'blobs': [
          {
            'blob_id': 'blob-1',
            'item_id': 'item-1',
            'metadata_ciphertext': 'meta-ciphertext',
            'metadata_nonce': 'meta-nonce',
            'metadata_aad': '{"mac":"meta-mac","schema":"lockly-blob-meta-v1"}',
            'ciphertext': 'content-ciphertext',
            'nonce': 'content-nonce',
            'aad': '{"mac":"content-mac","schema":"lockly-blob-v1"}',
            'ciphertext_sha256':
                '32e09955ad05411c67617336e6a7026bd1828b3453f15f427b87667a61960d6e',
            'ciphertext_size': 18,
            'revision': 1,
            'deleted': false,
            'client_updated_at': '2026-05-23T09:00:00Z',
            'server_updated_at': '2026-05-23T10:00:00Z',
            'file_bytes': 'plain',
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test(
    'sync blob DTOs allow opaque ciphertext with incidental short terms',
    () {
      const opaque = 'AAAAAAAAAAtotpPASSWORDpasskeyrawkeyBBBBBBBBBB';
      const blob = EncryptedVaultBlob(
        blobId: 'blob-opaque',
        itemId: 'item-opaque',
        metadataNonce: 'metaNonceTOTPx',
        metadataCiphertext: opaque,
        metadataMac: 'meta-mac',
        nonce: 'contentNonceTOTPx',
        ciphertext: opaque,
        mac: 'content-mac',
        createdAt: 1779494400000,
        updatedAt: 1779494400000,
      );
      final json = SyncBlob(
        id: blob.blobId,
        itemId: blob.itemId,
        payload: SyncBlobPayload.fromLocal(blob, revision: 0),
      ).toJson();

      expect(() => SyncBlob.fromJson(json), returnsNormally);
      expect(() => SyncBlob.assertSafeRawBlobs([json]), returnsNormally);
    },
  );

  test('forbidden field scanner reports nested unsafe field names', () {
    final payload = {
      'ciphertext': 'ok',
      'nested': {
        'masterPassword': 'no',
        'master_key': 'no',
        'masterKey': 'no',
        'items': [
          {'rawDek': 'no'},
          {'plaintext': 'no'},
          {'plaintext_password': 'no'},
          {'private_key': 'no'},
          {'password': 'no'},
          {'totpSecret': 'no'},
          {'master': 'no'},
          {'passkey': 'no'},
          {'attachment': 'no'},
          {'secret': 'no'},
          {'master-key': 'no'},
          {'username': 'no'},
          {'notes': 'no'},
          {'api_key': 'no'},
          {'secretValue': 'no'},
          {'noteText': 'no'},
          {'totpUri': 'no'},
          {'passkeyCredential': 'no'},
          {'attachmentName': 'no'},
          {'wrappedKek': 'no'},
          {'apikey': 'no'},
          {'secretvalue': 'no'},
          {'notetext': 'no'},
          {'totpuri': 'no'},
          {'passkeycredential': 'no'},
          {'attachmentname': 'no'},
          {'wrappedkek': 'no'},
        ],
      },
    };

    expect(findForbiddenSyncFields(payload), [
      'nested.masterPassword',
      'nested.master_key',
      'nested.masterKey',
      'nested.items[0].rawDek',
      'nested.items[1].plaintext',
      'nested.items[2].plaintext_password',
      'nested.items[3].private_key',
      'nested.items[4].password',
      'nested.items[5].totpSecret',
      'nested.items[6].master',
      'nested.items[7].passkey',
      'nested.items[8].attachment',
      'nested.items[9].secret',
      'nested.items[10].master-key',
      'nested.items[11].username',
      'nested.items[12].notes',
      'nested.items[13].api_key',
      'nested.items[14].secretValue',
      'nested.items[15].noteText',
      'nested.items[16].totpUri',
      'nested.items[17].passkeyCredential',
      'nested.items[18].attachmentName',
      'nested.items[19].wrappedKek',
      'nested.items[20].apikey',
      'nested.items[21].secretvalue',
      'nested.items[22].notetext',
      'nested.items[23].totpuri',
      'nested.items[24].passkeycredential',
      'nested.items[25].attachmentname',
      'nested.items[26].wrappedkek',
    ]);
    expect(() => assertNoForbiddenSyncFields(payload), throwsStateError);
  });

  test('forbidden field scanner rejects plaintext password entry payloads', () {
    final entry = PasswordEntry(
      title: 'Bank',
      website: 'https://bank.example',
      username: 'user@example.test',
      password: 'clear-password',
      notes: 'clear notes',
      tags: const ['finance'],
      totpSecret: 'JBSWY3DPEHPK3PXP',
    );

    final findings = findForbiddenSyncFields(entry.toJson());

    expect(findings, contains('password'));
    expect(findings, contains('totpSecret'));
    expect(() => assertNoForbiddenSyncFields(entry.toJson()), throwsStateError);
  });

  test('sync device parses optional operational metadata', () {
    final device = SyncDevice.fromJson({
      'id': 'device-1',
      'device_name': 'Work laptop',
      'device_type': 'desktop',
      'platform': 'windows',
      'client_version': '1.4.2',
      'trusted': true,
      'last_sync_at': '2026-05-23T09:00:00Z',
      'last_ip_address': '203.0.113.10',
      'last_user_agent': 'Lockly/1.4.2 Windows',
      'created_at': '2026-05-22T09:00:00Z',
      'revoked_at': null,
    });

    expect(device.platform, 'windows');
    expect(device.clientVersion, '1.4.2');
    expect(device.lastIpAddress, '203.0.113.10');
    expect(device.lastUserAgent, 'Lockly/1.4.2 Windows');
    expect(device.toJson(), containsPair('platform', 'windows'));
    expect(device.toJson(), containsPair('client_version', '1.4.2'));
    expect(device.toJson(), containsPair('last_ip_address', '203.0.113.10'));
    expect(
      device.toJson(),
      containsPair('last_user_agent', 'Lockly/1.4.2 Windows'),
    );
  });

  test('sync device remains backward-compatible when metadata is absent', () {
    final device = SyncDevice.fromJson({
      'id': 'device-1',
      'device_name': 'Phone',
      'device_type': null,
      'trusted': true,
      'last_sync_at': null,
      'created_at': '2026-05-22T09:00:00Z',
      'revoked_at': null,
    });

    expect(device.platform, isNull);
    expect(device.clientVersion, isNull);
    expect(device.lastIpAddress, isNull);
    expect(device.lastUserAgent, isNull);
  });

  test('emergency contact metadata accepts only zero-knowledge fields', () {
    final contact = EmergencyContact.fromJson({
      'id': 'contact-1',
      'owner_user_id': 'owner-1',
      'recipient_user_id': 'recipient-1',
      'recipient_email': 'trusted@example.test',
      'recipient_public_key': 'recipient-public-key-token',
      'recipient_key_fingerprint': 'fingerprint-1',
      'recipient_label': 'Trusted contact',
      'status': 'active',
      'created_at': '2026-05-24T08:00:00Z',
      'updated_at': '2026-05-24T08:00:00Z',
      'revoked_at': null,
    });

    expect(contact.id, 'contact-1');
    expect(contact.recipientEmail, 'trusted@example.test');
    expect(contact.recipientPublicKey, 'recipient-public-key-token');
    expect(contact.recipientKeyFingerprint, 'fingerprint-1');
    expect(contact.recipientLabel, 'Trusted contact');
    expect(contact.status, 'active');
    expect(
      () => EmergencyContact.fromJson({
        ...contact.toJson(),
        'recipientPrivateKey': 'private-key',
      }),
      throwsFormatException,
    );
    expect(
      () => EmergencyContact.fromJson({
        ...contact.toJson(),
        'unsupported': 'value',
      }),
      throwsFormatException,
    );
  });

  test('emergency contact rejects private key token values', () {
    const privateKeyToken =
        'lockly-x25519-private-v1.0000000000000000000000000000000000000000000000000000000000000000';

    expect(
      () => const EmergencyContactCreateRequest(
        recipientEmail: 'trusted@example.test',
        recipientPublicKey: privateKeyToken,
        recipientKeyFingerprint: 'fingerprint-1',
        recipientLabel: 'Trusted contact',
      ).toJson(),
      throwsStateError,
    );
    expect(
      () => EmergencyContact.fromJson({
        'id': 'contact-1',
        'owner_user_id': 'owner-1',
        'recipient_user_id': 'recipient-1',
        'recipient_email': 'trusted@example.test',
        'recipient_public_key': privateKeyToken,
        'recipient_key_fingerprint': 'fingerprint-1',
        'recipient_label': 'Trusted contact',
        'status': 'active',
        'created_at': '2026-05-24T08:00:00Z',
        'updated_at': '2026-05-24T08:00:00Z',
        'revoked_at': null,
      }),
      throwsFormatException,
    );
  });

  test('emergency grant metadata never accepts package body', () {
    final grant = EmergencyGrant.fromJson(_safeEmergencyGrantJson());

    expect(grant.id, 'grant-1');
    expect(grant.contactId, 'contact-1');
    expect(grant.waitingPeriodHours, 48);
    expect(grant.packageAad, _safeEmergencyPackageAad);
    expect(grant.packageFingerprint, 'package-fingerprint-1');
    expect(grant.recipientKeyFingerprint, 'fingerprint-1');
    expect(grant.toJson().containsKey('encrypted_recovery_package'), isFalse);
    expect(
      () => EmergencyGrant.fromJson({
        ..._safeEmergencyGrantJson(),
        'encrypted_recovery_package': _safeEmergencyPackageEnvelope,
      }),
      throwsFormatException,
    );
    expect(
      () => EmergencyGrant.fromJson({
        ..._safeEmergencyGrantJson(),
        'recovery_plaintext': 'clear recovery material',
      }),
      throwsFormatException,
    );
  });

  test('emergency grant metadata rejects non-official statuses', () {
    expect(
      () => EmergencyGrant.fromJson({
        ..._safeEmergencyGrantJson(),
        'status': 'accepted',
      }),
      throwsFormatException,
    );
  });

  test('emergency package DTO accepts encrypted package only', () {
    final package = EmergencyAccessPackage.fromJson({
      'grant_id': 'grant-1',
      'owner_user_id': 'owner-1',
      'recipient_user_id': 'recipient-1',
      'contact_id': 'contact-1',
      'status': 'downloaded',
      'encrypted_recovery_package': _safeEmergencyPackageEnvelope,
      'package_aad': _safeEmergencyPackageAad,
      'package_fingerprint': 'package-fingerprint-1',
      'recipient_key_fingerprint': 'fingerprint-1',
      'downloaded_at': '2026-05-24T10:00:00Z',
    });

    expect(package.grantId, 'grant-1');
    expect(package.encryptedRecoveryPackage, _safeEmergencyPackageEnvelope);
    expect(package.packageAad, _safeEmergencyPackageAad);
    expect(
      () => EmergencyAccessPackage.fromJson({
        'grant_id': 'grant-1',
        'owner_user_id': 'owner-1',
        'recipient_user_id': 'recipient-1',
        'contact_id': 'contact-1',
        'status': 'downloaded',
        'encrypted_recovery_package':
            '{"ciphertext":"cipher","nonce":"nonce","mac":"mac","plaintext":"clear"}',
        'package_aad': _safeEmergencyPackageAad,
        'package_fingerprint': 'package-fingerprint-1',
        'recipient_key_fingerprint': 'fingerprint-1',
        'downloaded_at': null,
      }),
      throwsFormatException,
    );
    expect(
      () => EmergencyAccessPackage.fromJson({
        'grant_id': 'grant-1',
        'owner_user_id': 'owner-1',
        'recipient_user_id': 'recipient-1',
        'contact_id': 'contact-1',
        'status': 'downloaded',
        'encrypted_recovery_package': _safeEmergencyPackageEnvelope,
        'package_aad': _safeEmergencyPackageAad,
        'package_fingerprint': 'package-fingerprint-1',
        'recipient_key_fingerprint': 'fingerprint-1',
        'recovery_plaintext': 'clear recovery material',
      }),
      throwsFormatException,
    );
  });

  test('emergency package DTO rejects non-official statuses', () {
    expect(
      () => EmergencyAccessPackage.fromJson({
        'grant_id': 'grant-1',
        'owner_user_id': 'owner-1',
        'recipient_user_id': 'recipient-1',
        'contact_id': 'contact-1',
        'status': 'accepted',
        'encrypted_recovery_package': _safeEmergencyPackageEnvelope,
        'package_aad': _safeEmergencyPackageAad,
        'package_fingerprint': 'package-fingerprint-1',
        'recipient_key_fingerprint': 'fingerprint-1',
        'downloaded_at': null,
      }),
      throwsFormatException,
    );
  });

  test('emergency grant create request validates package envelope and aad', () {
    final request = EmergencyGrantCreateRequest(
      contactId: 'contact-1',
      waitingPeriodHours: 48,
      encryptedRecoveryPackage: _safeEmergencyPackageEnvelope,
      packageAad: _safeEmergencyPackageAad,
      packageFingerprint: 'package-fingerprint-1',
    );

    expect(request.toJson(), {
      'contact_id': 'contact-1',
      'waiting_period_hours': 48,
      'encrypted_recovery_package': _safeEmergencyPackageEnvelope,
      'package_aad': _safeEmergencyPackageAad,
      'package_fingerprint': 'package-fingerprint-1',
    });
    expect(
      () => EmergencyGrantCreateRequest(
        contactId: 'contact-1',
        waitingPeriodHours: 48,
        encryptedRecoveryPackage:
            '{"ciphertext":"cipher","nonce":"nonce","mac":"mac","password":"clear"}',
        packageAad: _safeEmergencyPackageAad,
        packageFingerprint: 'package-fingerprint-1',
      ).toJson(),
      throwsStateError,
    );
    expect(
      () => EmergencyGrantCreateRequest(
        contactId: 'contact-1',
        waitingPeriodHours: 48,
        encryptedRecoveryPackage: _safeEmergencyPackageEnvelope,
        packageAad:
            '{"schema":"lockly-emergency-package-v1","mac":"mac","username":"alice"}',
        packageFingerprint: 'package-fingerprint-1',
      ).toJson(),
      throwsStateError,
    );
    expect(
      () => EmergencyGrantCreateRequest(
        contactId: 'contact/../master-password',
        waitingPeriodHours: 48,
        encryptedRecoveryPackage: _safeEmergencyPackageEnvelope,
        packageAad: _safeEmergencyPackageAad,
        packageFingerprint: 'package-fingerprint-1',
      ).toJson(),
      throwsStateError,
    );
  });

  test(
    'auth, device, sync, pull, and conflict DTOs match backend contract',
    () {
      final tokens = SyncAuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        tokenType: 'bearer',
      );
      const device = SyncDevice(
        id: 'device-1',
        deviceName: 'Work laptop',
        deviceType: 'windows',
        trusted: true,
        lastSyncAt: null,
        createdAt: '2026-05-13T10:00:00Z',
        revokedAt: null,
      );
      final item = SyncItem(
        id: 'item-1',
        payload: SyncItemPayload.fromJson({
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
          'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
          'revision': 4,
          'deleted': false,
          'client_updated_at': '2026-05-13T10:00:00Z',
          'server_updated_at': '2026-05-13T10:05:00Z',
        }),
      );
      final push = SyncPushResponse(
        serverTime: '2026-05-13T10:05:00Z',
        applied: [item],
        conflicts: [
          SyncConflict(itemId: 'item-2', localRevision: 2, remoteRevision: 3),
        ],
      );
      final pull = SyncPullResponse(
        serverTime: '2026-05-13T10:05:00Z',
        items: [item],
      );

      expect(SyncAuthTokens.fromJson(tokens.toJson()).accessToken, 'access');
      expect(SyncAuthTokens.fromJson(tokens.toJson()).tokenType, 'bearer');
      expect(
        () => SyncAuthTokens.fromJson({
          ...tokens.toJson(),
          'master_password': 'clear-master-password',
        }),
        throwsFormatException,
      );
      expect(
        () => SyncAccount.fromJson({
          'id': 'account-1',
          'email': 'user@example.test',
          'password': 'clear-password',
        }),
        throwsFormatException,
      );
      expect(SyncDevice.fromJson(device.toJson()).deviceName, 'Work laptop');
      expect(
        () =>
            SyncDevice.fromJson({...device.toJson(), 'secret': 'clear-secret'}),
        throwsFormatException,
      );
      expect(item.toJson()['item_id'], 'item-1');
      expect(item.toJson().containsKey('id'), isFalse);
      expect(item.toJson()['server_updated_at'], '2026-05-13T10:05:00Z');
      expect(
        () => SyncItemPayload.fromJson({
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
          'revision': 4,
          'deleted': false,
          'client_updated_at': '2026-05-13T10:00:00Z',
        }),
        throwsFormatException,
      );
      expect(push.toJson().keys, {'server_time', 'applied', 'conflicts'});
      expect(
        SyncPushResponse.fromJson(push.toJson()).applied.single.id,
        'item-1',
      );
      expect(
        SyncPushResponse.fromJson(push.toJson()).conflicts.single.itemId,
        'item-2',
      );
      expect(
        SyncPushResponse.fromJson({
          'applied': [
            {
              'item_id': 'item-1',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
              'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
              'revision': 4,
              'deleted': false,
              'client_updated_at': '2026-05-13T10:00:00Z',
              'server_updated_at': '2026-05-13T10:05:00Z',
            },
          ],
          'conflicts': [
            {'item_id': 'item-2', 'client_revision': 2, 'server_revision': 3},
          ],
        }).conflicts.single.remoteRevision,
        3,
      );
      expect(
        () => SyncPushResponse.fromJson({
          'server_time': '2026-05-13T10:05:00Z',
          'applied': <Object?>[],
          'conflicts': <Object?>[],
          'password': 'clear-password',
        }),
        throwsFormatException,
      );
      expect(
        () => SyncPushResponse.fromJson({
          'applied': <Object?>[],
          'conflicts': [
            {
              'item_id': 'item-2',
              'client_revision': 2,
              'server_revision': 3,
              'master_key': 'raw-master-key',
            },
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => SyncItem.fromJson({
          'item_id': 'username-note-password',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
          'aad': '{"mac":"mac","schema":"lockly-item-v1"}',
          'revision': 4,
          'deleted': false,
          'client_updated_at': '2026-05-13T10:00:00Z',
          'server_updated_at': '2026-05-13T10:05:00Z',
        }),
        throwsFormatException,
      );
      expect(
        () => SyncConflict.fromJson({
          'item_id': 'username-note-password',
          'client_revision': 2,
          'server_revision': 3,
        }),
        throwsFormatException,
      );
      expect(
        () => SyncPullResponse.fromJson({
          'server_time': '2026-05-13T10:05:00Z',
          'items': <Object?>[],
          'apikey': 'raw-api-key',
        }),
        throwsFormatException,
      );
      expect(pull.toJson().keys, {'server_time', 'items'});
      expect(
        SyncPullResponse.fromJson(pull.toJson()).items.single.id,
        'item-1',
      );
    },
  );
}

const String _safeEmergencyPackageEnvelope =
    '{"ciphertext":"emergency-ciphertext","nonce":"emergency-nonce","mac":"emergency-mac"}';

const String _safeEmergencyPackageAad =
    '{"schema":"lockly-emergency-package-v1","mac":"emergency-mac","grant_id":"grant-1","recipient_key_fingerprint":"fingerprint-1"}';

Map<String, Object?> _safeEmergencyGrantJson() {
  return {
    'id': 'grant-1',
    'owner_user_id': 'owner-1',
    'recipient_user_id': 'recipient-1',
    'contact_id': 'contact-1',
    'vault_id': 'vault-1',
    'status': 'pending_acceptance',
    'waiting_period_hours': 48,
    'package_aad': _safeEmergencyPackageAad,
    'package_fingerprint': 'package-fingerprint-1',
    'recipient_key_fingerprint': 'fingerprint-1',
    'requested_at': null,
    'ready_at': null,
    'downloaded_at': null,
    'cancelled_at': null,
    'revoked_at': null,
    'expires_at': null,
    'created_at': '2026-05-24T08:00:00Z',
    'updated_at': '2026-05-24T08:00:00Z',
  };
}
