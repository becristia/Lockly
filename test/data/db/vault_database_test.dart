import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:secure_box/data/models/encrypted_vault_item.dart';
import 'package:secure_box/data/models/vault_meta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('vault items store only encrypted fields', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultItemsDao(db);
    final now = DateTime.utc(2026, 5, 12).millisecondsSinceEpoch;

    await dao.upsert(
      EncryptedVaultItem(
        id: 'item-1',
        nonce: 'nonce-value',
        ciphertext: 'ciphertext-value',
        mac: 'mac-value',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final rows = await db.query('vault_items');
    expect(
      rows.single.keys,
      containsAll([
        'id',
        'nonce',
        'ciphertext',
        'mac',
        'created_at',
        'updated_at',
        'deleted_at',
      ]),
    );
    expect(rows.single.keys, isNot(contains('password')));
    expect(rows.single.keys, isNot(contains('username')));
    expect(rows.single.keys, isNot(contains('notes')));
    expect(rows.single.keys, isNot(contains('title')));
    expect(rows.single['ciphertext'], 'ciphertext-value');
  });

  test('vault items can be read, filtered, and soft-deleted', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultItemsDao(db);
    final createdAt = DateTime.utc(2026, 5, 12).millisecondsSinceEpoch;
    final deletedAt = createdAt + 1000;

    final activeItem = EncryptedVaultItem(
      id: 'active-item',
      nonce: 'active-nonce',
      ciphertext: 'active-ciphertext',
      mac: 'active-mac',
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final deletedItem = EncryptedVaultItem(
      id: 'deleted-item',
      nonce: 'deleted-nonce',
      ciphertext: 'deleted-ciphertext',
      mac: 'deleted-mac',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await dao.upsert(activeItem);
    await dao.upsert(deletedItem);

    expect(await dao.byId(activeItem.id), isNotNull);
    expect(await dao.byId('missing-item'), isNull);

    await dao.softDelete(deletedItem.id, deletedAt);

    final activeItems = await dao.activeItems();
    final storedDeletedItem = await dao.byId(deletedItem.id);

    expect(activeItems.map((item) => item.id), [activeItem.id]);
    expect(storedDeletedItem?.deletedAt, deletedAt);
    expect(storedDeletedItem?.updatedAt, deletedAt);
  });

  test('daos can be used inside a database transaction', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final item = EncryptedVaultItem(
      id: 'txn-item',
      nonce: 'txn-nonce',
      ciphertext: 'txn-ciphertext',
      mac: 'txn-mac',
      createdAt: 1747000000000,
      updatedAt: 1747000000000,
    );
    final meta = _buildVaultMeta(
      biometricEnabled: false,
      encryptedDekByBiometric: null,
      encryptedDekByBiometricNonce: null,
      encryptedDekByBiometricMac: null,
    );

    await db.transaction((txn) async {
      await SettingsDao(txn).setValue('clipboard_clear_seconds', '45');
      await VaultMetaDao(txn).save(meta);
      await VaultItemsDao(txn).upsert(item);
    });

    expect(await SettingsDao(db).getValue('clipboard_clear_seconds'), '45');
    expect((await VaultMetaDao(db).get())!.toDb(), meta.toDb());
    expect((await VaultItemsDao(db).byId(item.id))!.toDb(), item.toDb());
  });

  test('settings can be saved and read', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = SettingsDao(db);

    await dao.setValue('clipboard_clear_seconds', '30');

    expect(await dao.getValue('clipboard_clear_seconds'), '30');
    expect(await dao.getValue('missing-key'), isNull);
  });

  test('vault meta can be saved and read', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultMetaDao(db);
    final meta = _buildVaultMeta(
      biometricEnabled: true,
      encryptedDekByBiometric: null,
      encryptedDekByBiometricNonce: null,
      encryptedDekByBiometricMac: null,
    );

    await dao.save(meta);

    expect(await dao.get(), isNotNull);
    expect((await dao.get())!.toDb(), meta.toDb());
  });

  test('vault meta save preserves a single persisted row', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultMetaDao(db);
    final firstMeta = _buildVaultMeta(
      id: 'vault-1',
      biometricEnabled: false,
      encryptedDekByBiometric: null,
      encryptedDekByBiometricNonce: null,
      encryptedDekByBiometricMac: null,
      updatedAt: 1747000000000,
    );
    final secondMeta = _buildVaultMeta(
      id: 'vault-2',
      biometricEnabled: true,
      encryptedDekByBiometric: null,
      encryptedDekByBiometricNonce: null,
      encryptedDekByBiometricMac: null,
      updatedAt: 1747000001111,
    );

    await dao.save(firstMeta);
    await dao.save(secondMeta);

    final rows = await db.query('vault_meta');
    final storedMeta = await dao.get();

    expect(rows, hasLength(1));
    expect(storedMeta, isNotNull);
    expect(storedMeta!.toDb(), secondMeta.toDb());
  });

  test(
    'vault meta table rejects a second row outside dao replace semantics',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final firstMeta = _buildVaultMeta(
        id: 'vault-1',
        biometricEnabled: false,
        encryptedDekByBiometric: null,
        encryptedDekByBiometricNonce: null,
        encryptedDekByBiometricMac: null,
      );
      final secondMeta = _buildVaultMeta(
        id: 'vault-2',
        biometricEnabled: false,
        encryptedDekByBiometric: null,
        encryptedDekByBiometricNonce: null,
        encryptedDekByBiometricMac: null,
      );

      await db.insert('vault_meta', firstMeta.toDb());

      expect(
        () => db.insert('vault_meta', secondMeta.toDb()),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('vault_meta'), hasLength(1));
    },
  );

  test(
    'vault meta save scrubs disabled legacy biometric tuple columns',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final dao = VaultMetaDao(db);
      final meta = _buildVaultMeta(
        biometricEnabled: false,
        encryptedDekByBiometric: 'stale-biometric-dek',
        encryptedDekByBiometricNonce: 'stale-biometric-nonce',
        encryptedDekByBiometricMac: 'stale-biometric-mac',
      );

      await dao.save(meta);

      final row = (await db.query('vault_meta')).single;
      final storedMeta = await dao.get();

      expect(row['biometric_enabled'], 0);
      expect(row['encrypted_dek_by_biometric'], isNull);
      expect(row['encrypted_dek_by_biometric_nonce'], isNull);
      expect(row['encrypted_dek_by_biometric_mac'], isNull);
      expect(storedMeta, isNotNull);
      expect(storedMeta!.biometricEnabled, isFalse);
      expect(storedMeta.encryptedDekByBiometric, isNull);
      expect(storedMeta.encryptedDekByBiometricNonce, isNull);
      expect(storedMeta.encryptedDekByBiometricMac, isNull);
    },
  );

  test('clearing biometric DEK disables biometric unlock state', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultMetaDao(db);
    final initialMeta = _buildVaultMeta(
      biometricEnabled: true,
      encryptedDekByBiometric: 'encrypted-biometric-dek',
      encryptedDekByBiometricNonce: 'biometric-nonce',
      encryptedDekByBiometricMac: 'biometric-mac',
      updatedAt: 1747000000000,
    );
    final clearedAt = 1747000009999;

    await dao.save(initialMeta);
    await dao.clearBiometricDek(clearedAt);

    final clearedMeta = await dao.get();

    expect(clearedMeta, isNotNull);
    expect(clearedMeta!.biometricEnabled, isFalse);
    expect(clearedMeta.encryptedDekByBiometric, isNull);
    expect(clearedMeta.encryptedDekByBiometricNonce, isNull);
    expect(clearedMeta.encryptedDekByBiometricMac, isNull);
    expect(clearedMeta.updatedAt, clearedAt);
    expect(clearedMeta.encryptedDekByMaster, initialMeta.encryptedDekByMaster);
  });

  test(
    'clearing biometric DEK also works when biometric is enabled without legacy tuple columns',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final dao = VaultMetaDao(db);
      final initialMeta = _buildVaultMeta(
        biometricEnabled: true,
        encryptedDekByBiometric: null,
        encryptedDekByBiometricNonce: null,
        encryptedDekByBiometricMac: null,
        updatedAt: 1747000000000,
      );
      final clearedAt = 1747000011111;

      await dao.save(initialMeta);
      await dao.clearBiometricDek(clearedAt);

      final clearedMeta = await dao.get();

      expect(clearedMeta, isNotNull);
      expect(clearedMeta!.biometricEnabled, isFalse);
      expect(clearedMeta.encryptedDekByBiometric, isNull);
      expect(clearedMeta.encryptedDekByBiometricNonce, isNull);
      expect(clearedMeta.encryptedDekByBiometricMac, isNull);
      expect(clearedMeta.updatedAt, clearedAt);
    },
  );

  test('soft delete requires an existing item row', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultItemsDao(db);

    expect(
      () => dao.softDelete('missing-item', 1747000009999),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('vault_items'),
        ),
      ),
    );
  });

  test('soft delete fails when the item is already deleted', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultItemsDao(db);
    final createdAt = DateTime.utc(2026, 5, 12).millisecondsSinceEpoch;
    final firstDeletedAt = createdAt + 1000;
    final secondDeletedAt = createdAt + 2000;
    final item = EncryptedVaultItem(
      id: 'deleted-once',
      nonce: 'nonce-value',
      ciphertext: 'ciphertext-value',
      mac: 'mac-value',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await dao.upsert(item);
    await dao.softDelete(item.id, firstDeletedAt);

    expect(
      () => dao.softDelete(item.id, secondDeletedAt),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('vault_items'),
        ),
      ),
    );
  });

  test('clearing biometric DEK requires an existing singleton row', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final dao = VaultMetaDao(db);

    expect(
      () => dao.clearBiometricDek(1747000009999),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('vault_meta'),
        ),
      ),
    );
  });

  test(
    'clearing biometric DEK fails when biometric unlock is already cleared',
    () async {
      final db = await AppDatabase.openInMemory();
      addTearDown(db.close);
      final dao = VaultMetaDao(db);
      final meta = _buildVaultMeta(
        biometricEnabled: true,
        encryptedDekByBiometric: 'encrypted-biometric-dek',
        encryptedDekByBiometricNonce: 'biometric-nonce',
        encryptedDekByBiometricMac: 'biometric-mac',
        updatedAt: 1747000000000,
      );

      await dao.save(meta);
      await dao.clearBiometricDek(1747000001111);

      expect(
        () => dao.clearBiometricDek(1747000002222),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('vault_meta'),
          ),
        ),
      );
    },
  );
}

VaultMeta _buildVaultMeta({
  String id = 'vault-1',
  required bool biometricEnabled,
  required String? encryptedDekByBiometric,
  required String? encryptedDekByBiometricNonce,
  required String? encryptedDekByBiometricMac,
  int createdAt = 1747000000000,
  int updatedAt = 1747000000000,
}) {
  return VaultMeta(
    id: id,
    version: 1,
    kdf: 'pbkdf2-hmac-sha256',
    kdfParams: KdfParams.pbkdf2(iterations: 120000, bits: 256),
    salt: 'base64-salt',
    encryptedDekByMaster: 'encrypted-master-dek',
    encryptedDekByMasterNonce: 'master-nonce',
    encryptedDekByMasterMac: 'master-mac',
    biometricEnabled: biometricEnabled,
    createdAt: createdAt,
    updatedAt: updatedAt,
    encryptedDekByBiometric: encryptedDekByBiometric,
    encryptedDekByBiometricNonce: encryptedDekByBiometricNonce,
    encryptedDekByBiometricMac: encryptedDekByBiometricMac,
  );
}
