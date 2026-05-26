import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/backup/backup_service.dart';
import 'package:secure_box/core/crypto/crypto_service.dart';
import 'package:secure_box/core/crypto/kdf_service.dart';
import 'package:secure_box/core/crypto/secure_random.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_client.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_crypto.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_server.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_service.dart';
import 'package:secure_box/core/vault/vault_anchor_service.dart';
import 'package:secure_box/core/vault/vault_anchor_store.dart';
import 'package:secure_box/core/vault/vault_repository.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/db/app_database.dart';
import 'package:secure_box/data/db/password_history_dao.dart';
import 'package:secure_box/data/db/settings_dao.dart';
import 'package:secure_box/data/db/vault_items_dao.dart';
import 'package:secure_box/data/db/vault_manifest_dao.dart';
import 'package:secure_box/data/db/vault_meta_dao.dart';
import 'package:secure_box/data/models/passkey_record.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('LanTransferService', () {
    test(
      'receiveFromPayload skips conflicts and hides secrets in result',
      () async {
        final source = await _buildHarness();
        await source.vaultService.createVault(masterPassword: 'source-master');
        await source.vaultService.unlock(masterPassword: 'source-master');
        final conflictId = await source.vaultService.createItem(
          PasswordEntry(
            title: 'GitHub',
            website: 'https://github.com',
            username: 'user@example.com',
            password: 'source-conflict-password',
            notes: 'source private notes',
            tags: const ['dev'],
            totpSecret: 'BASE32TOTPSECRET',
            passkey: const PasskeyRecord(
              relyingPartyId: 'github.com',
              credentialId: 'credential-id-secret',
              userHandle: 'user-handle-secret',
              displayName: 'passkey display',
              publicKeyAlgorithm: 'ES256',
              platform: 'android',
              platformReady: true,
            ),
          ),
        );
        await source.vaultService.addBlob(
          itemId: conflictId,
          displayName: 'recovery.txt',
          mediaType: 'text/plain',
          bytes: utf8.encode('source attachment bytes'),
        );
        final importId = await source.vaultService.createItem(
          PasswordEntry(
            title: 'Docs',
            website: 'https://docs.example',
            username: 'docs@example.com',
            password: 'source-docs-password',
            notes: 'source docs notes',
            tags: const ['docs'],
          ),
        );

        final target = await _buildHarness();
        await target.vaultService.createVault(masterPassword: 'target-master');
        await target.vaultService.unlock(masterPassword: 'target-master');
        final localConflictId = await target.vaultService.createItem(
          PasswordEntry(
            title: ' github ',
            website: 'http://www.github.com/',
            username: 'USER@example.com',
            password: 'target-conflict-password',
            notes: 'target private notes',
            tags: const ['local'],
          ),
        );

        final session = await source.lanTransferService.createSendSession(
          itemIds: [conflictId, importId],
          includeBlobs: true,
          includeHistory: false,
          senderName: 'Source',
          bindHost: '127.0.0.1',
          advertisedHost: '127.0.0.1',
        );
        addTearDown(source.lanTransferService.cancelSendSession);

        final result = await target.lanTransferService.receiveFromPayload(
          payload: session.qrPayload,
          sourceMasterPassword: 'source-master',
        );

        expect(result.importedCount, 1);
        expect(result.skippedCount, 1);
        expect(result.conflicts, hasLength(1));
        expect(result.conflicts.single.title, 'GitHub');
        expect(
          result.conflicts.single.reason,
          LanTransferConflictReason.existingLocalEntry,
        );
        expect(
          (await target.vaultService.getItem(localConflictId)).password,
          'target-conflict-password',
        );

        target.vaultService.lock();
        await target.vaultService.unlock(masterPassword: 'target-master');
        expect(
          (await target.vaultService.getItem(importId)).password,
          'source-docs-password',
        );

        final exposed = jsonEncode({
          'importedCount': result.importedCount,
          'skippedCount': result.skippedCount,
          'conflicts': result.conflicts
              .map(
                (conflict) => {
                  'title': conflict.title,
                  'website': conflict.website,
                  'username': conflict.username,
                  'reason': conflict.reason.name,
                  'string': conflict.toString(),
                },
              )
              .toList(),
          'string': result.toString(),
        });
        expect(exposed, isNot(contains('source-conflict-password')));
        expect(exposed, isNot(contains('source private notes')));
        expect(exposed, isNot(contains('BASE32TOTPSECRET')));
        expect(exposed, isNot(contains('source attachment bytes')));
        expect(exposed, isNot(contains('credential-id-secret')));
        expect(exposed, isNot(contains('user-handle-secret')));
      },
    );

    test(
      'wrong source master password imports nothing and keeps target unchanged',
      () async {
        final source = await _buildHarness();
        await source.vaultService.createVault(masterPassword: 'source-master');
        await source.vaultService.unlock(masterPassword: 'source-master');
        final sourceId = await source.vaultService.createItem(
          PasswordEntry(
            title: 'GitHub',
            website: 'https://github.com',
            username: 'user@example.com',
            password: 'source-password',
            notes: 'source notes',
            tags: const ['dev'],
          ),
        );

        final target = await _buildHarness();
        await target.vaultService.createVault(masterPassword: 'target-master');
        await target.vaultService.unlock(masterPassword: 'target-master');
        final localId = await target.vaultService.createItem(
          PasswordEntry(
            title: 'Local',
            website: 'https://local.example',
            username: 'local@example.com',
            password: 'local-password',
            notes: 'local notes',
            tags: const ['local'],
          ),
        );

        final session = await source.lanTransferService.createSendSession(
          itemIds: [sourceId],
          includeBlobs: true,
          includeHistory: false,
          senderName: 'Source',
          bindHost: '127.0.0.1',
          advertisedHost: '127.0.0.1',
        );
        addTearDown(source.lanTransferService.cancelSendSession);

        await expectLater(
          target.lanTransferService.receiveFromPayload(
            payload: session.qrPayload,
            sourceMasterPassword: 'wrong-master',
          ),
          throwsA(isA<VaultUnlockException>()),
        );
        expect(await target.vaultService.listItems(), hasLength(1));
        expect(
          (await target.vaultService.getItem(localId)).password,
          'local-password',
        );
      },
    );

    test('cancelSendSession makes payload unavailable', () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final sourceId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'source-password',
          notes: 'source notes',
          tags: const ['dev'],
        ),
      );
      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'target-master');
      await target.vaultService.unlock(masterPassword: 'target-master');

      final session = await source.lanTransferService.createSendSession(
        itemIds: [sourceId],
        includeBlobs: false,
        includeHistory: false,
        senderName: 'Source',
        bindHost: '127.0.0.1',
        advertisedHost: '127.0.0.1',
      );
      await source.lanTransferService.cancelSendSession();

      await expectLater(
        target.lanTransferService.receiveFromPayload(
          payload: session.qrPayload,
          sourceMasterPassword: 'source-master',
        ),
        throwsA(isA<LanTransferUnavailableException>()),
      );
    });

    test('maps duplicate incoming conflicts into LAN result reason', () async {
      final source = await _buildHarness();
      await source.vaultService.createVault(masterPassword: 'source-master');
      await source.vaultService.unlock(masterPassword: 'source-master');
      final firstId = await source.vaultService.createItem(
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com/',
          username: 'User@Example.com',
          password: 'first-password',
          notes: 'first wins',
          tags: const ['dev'],
        ),
      );
      final duplicateId = await source.vaultService.createItem(
        PasswordEntry(
          title: ' github ',
          website: 'http://www.github.com',
          username: 'user@example.com',
          password: 'duplicate-password',
          notes: 'duplicate loses',
          tags: const ['dev'],
        ),
      );
      final target = await _buildHarness();
      await target.vaultService.createVault(masterPassword: 'target-master');
      await target.vaultService.unlock(masterPassword: 'target-master');

      final session = await source.lanTransferService.createSendSession(
        itemIds: [firstId, duplicateId],
        includeBlobs: false,
        includeHistory: false,
        senderName: 'Source',
        bindHost: '127.0.0.1',
        advertisedHost: '127.0.0.1',
      );
      addTearDown(source.lanTransferService.cancelSendSession);

      final result = await target.lanTransferService.receiveFromPayload(
        payload: session.qrPayload,
        sourceMasterPassword: 'source-master',
      );

      expect(result.importedCount, 1);
      expect(result.skippedCount, 1);
      expect(
        result.conflicts.single.reason,
        LanTransferConflictReason.duplicateIncomingEntry,
      );
    });
  });

  group('AppServices LAN transfer lifecycle', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('lockVault cancels active real send session', () async {
      await _runWithRealHttpClient(() async {
        final sessionHarness = await _buildAppServicesLanSessionHarness();
        addTearDown(sessionHarness.services.dispose);

        await _expectLanSessionAvailableWithoutDownload(
          sessionHarness.localhostPayload,
        );
        sessionHarness.services.lockVault();
        await _allowFireAndForgetCancellation();

        await _expectLanPayloadUnavailable(
          target: sessionHarness.target,
          payload: sessionHarness.localhostPayload,
        );
      });
    });

    test('dispose cancels active real send session', () async {
      await _runWithRealHttpClient(() async {
        final sessionHarness = await _buildAppServicesLanSessionHarness();

        await _expectLanSessionAvailableWithoutDownload(
          sessionHarness.localhostPayload,
        );
        sessionHarness.services.dispose();
        await _allowFireAndForgetCancellation();

        await _expectLanPayloadUnavailable(
          target: sessionHarness.target,
          payload: sessionHarness.localhostPayload,
        );
      });
    });
  });

  group('AppServices LAN transfer wrappers', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('fake overrides are called', () async {
      var createCalled = false;
      var receiveCalled = false;
      final session = LanTransferSession(
        qrPayload: LanTransferQrPayload(
          host: '127.0.0.1',
          port: 1,
          sessionId: 'session',
          token: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          transferKey: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
          packageSha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          selectedCount: 1,
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          senderName: 'Fake',
        ),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      );

      final services = AppServices.fake(
        hasVault: true,
        unlocked: true,
        createLanSendSessionOverride:
            ({
              required itemIds,
              required includeBlobs,
              required includeHistory,
              required senderName,
            }) async {
              createCalled = true;
              expect(itemIds, ['item-1']);
              expect(includeBlobs, isTrue);
              expect(includeHistory, isFalse);
              expect(senderName, 'Sender');
              return session;
            },
        receiveLanTransferOverride:
            ({required payload, required sourceMasterPassword}) async {
              receiveCalled = true;
              expect(payload, session.qrPayload);
              expect(sourceMasterPassword, 'source-master');
              return const LanTransferImportResult(
                importedCount: 1,
                skippedCount: 0,
                conflicts: [],
              );
            },
      );
      addTearDown(services.dispose);

      await services.createLanSendSession(
        itemIds: const ['item-1'],
        includeBlobs: true,
        includeHistory: false,
        senderName: 'Sender',
      );
      final result = await services.receiveLanTransfer(
        payload: session.qrPayload,
        sourceMasterPassword: 'source-master',
      );

      expect(createCalled, isTrue);
      expect(receiveCalled, isTrue);
      expect(result.importedCount, 1);
    });

    test(
      'real wrappers call service when available and missing service throws',
      () async {
        final harness = await _buildHarness();
        final service = _RecordingLanTransferService(harness.backupService);
        final services = AppServices(
          hasVault: true,
          initialShellState: AppShellState.unlocked,
          trackActivity: false,
          lanTransferService: service,
        );
        addTearDown(services.dispose);

        final session = await services.createLanSendSession(
          itemIds: const ['item-1'],
          includeBlobs: false,
          includeHistory: true,
          senderName: 'Sender',
        );
        final result = await services.receiveLanTransfer(
          payload: session.qrPayload,
          sourceMasterPassword: 'source-master',
        );
        await services.cancelLanSendSession();

        expect(service.createCalled, isTrue);
        expect(service.receiveCalled, isTrue);
        expect(service.cancelCalled, isTrue);
        expect(result.skippedCount, 0);

        final missing = AppServices(
          hasVault: true,
          initialShellState: AppShellState.unlocked,
          trackActivity: false,
        );
        addTearDown(missing.dispose);

        await expectLater(
          missing.createLanSendSession(
            itemIds: const ['item-1'],
            includeBlobs: false,
            includeHistory: false,
            senderName: 'Sender',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'clearLocalVault cancels active send session when overridden',
      () async {
        final harness = await _buildHarness();
        final service = _RecordingLanTransferService(harness.backupService);
        var clearCalled = false;
        final services = AppServices(
          hasVault: true,
          initialShellState: AppShellState.unlocked,
          trackActivity: false,
          lanTransferService: service,
          clearLocalVaultOverride: () async {
            clearCalled = true;
          },
        );
        addTearDown(services.dispose);

        await services.clearLocalVault();

        expect(clearCalled, isTrue);
        expect(service.cancelCalled, isTrue);
      },
    );
  });

  test('LAN routes resolve while unlocked', () {
    final services = AppServices.fake(hasVault: true, unlocked: true);
    addTearDown(services.dispose);

    expect(
      services.resolveRouteName(AppServices.routeLanSync),
      AppServices.routeLanSync,
    );
    expect(
      services.resolveRouteName(AppServices.routeLanSend),
      AppServices.routeLanSend,
    );
    expect(
      services.resolveRouteName(AppServices.routeLanReceive),
      AppServices.routeLanReceive,
    );
  });
}

Future<_LanTransferHarness> _buildHarness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'secure_box_lan_transfer_',
  );
  addTearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final db = await AppDatabase.open(p.join(tempDir.path, 'vault.db'));
  addTearDown(db.close);
  final repository = VaultRepository(
    metaDao: VaultMetaDao(db),
    itemsDao: VaultItemsDao(db),
    manifestDao: VaultManifestDao(db),
    settingsDao: SettingsDao(db),
    historyDao: PasswordHistoryDao(db),
  );
  final anchorStore = MemoryVaultAnchorStore();
  final random = SecureRandom();
  final vaultService = VaultService(
    repository: repository,
    random: random,
    kdf: KdfService(),
    crypto: CryptoService(random: random),
    anchorService: VaultAnchorService(store: anchorStore),
  );
  final backupService = BackupService(
    repository: repository,
    vaultService: vaultService,
  );
  final lanTransferCrypto = _transferCrypto();
  final lanTransferService = LanTransferService(
    backupService: backupService,
    server: LanTransferServer(crypto: lanTransferCrypto),
    client: LanTransferClient(crypto: lanTransferCrypto),
  );
  addTearDown(lanTransferService.cancelSendSession);

  return _LanTransferHarness(
    repository: repository,
    vaultService: vaultService,
    backupService: backupService,
    lanTransferService: lanTransferService,
  );
}

Future<_AppServicesLanSessionHarness>
_buildAppServicesLanSessionHarness() async {
  final source = await _buildHarness();
  await source.vaultService.createVault(masterPassword: 'source-master');
  await source.vaultService.unlock(masterPassword: 'source-master');
  final sourceId = await source.vaultService.createItem(
    PasswordEntry(
      title: 'GitHub',
      website: 'https://github.com',
      username: 'user@example.com',
      password: 'source-password',
      notes: 'source notes',
      tags: const ['dev'],
    ),
  );

  final target = await _buildHarness();
  await target.vaultService.createVault(masterPassword: 'target-master');
  await target.vaultService.unlock(masterPassword: 'target-master');

  final services = AppServices(
    hasVault: true,
    initialShellState: AppShellState.unlocked,
    trackActivity: false,
    vaultService: source.vaultService,
    lanTransferService: _LocalhostLanTransferService(source.backupService),
  );
  addTearDown(services.lanTransferService.cancelSendSession);
  final session = await services.createLanSendSession(
    itemIds: [sourceId],
    includeBlobs: false,
    includeHistory: false,
    senderName: 'Source',
  );

  return _AppServicesLanSessionHarness(
    services: services,
    target: target,
    localhostPayload: session.qrPayload,
  );
}

Future<void> _allowFireAndForgetCancellation() {
  return Future<void>.delayed(const Duration(milliseconds: 25));
}

Future<void> _expectLanPayloadUnavailable({
  required _LanTransferHarness target,
  required LanTransferQrPayload payload,
}) async {
  await expectLater(
    target.lanTransferService.receiveFromPayload(
      payload: payload,
      sourceMasterPassword: 'source-master',
    ),
    throwsA(isA<LanTransferUnavailableException>()),
  );
}

Future<void> _expectLanSessionAvailableWithoutDownload(
  LanTransferQrPayload payload,
) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(payload.transferUri());
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer wrong-token');
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.unauthorized);
  } finally {
    client.close(force: true);
  }
}

Future<T> _runWithRealHttpClient<T>(Future<T> Function() action) {
  final overrides = _RealHttpOverrides();
  return HttpOverrides.runZoned(
    action,
    createHttpClient: overrides.createHttpClient,
  );
}

LanTransferCrypto _transferCrypto() {
  final random = SecureRandom();
  return LanTransferCrypto(
    crypto: CryptoService(random: random),
    random: random,
  );
}

class _LanTransferHarness {
  const _LanTransferHarness({
    required this.repository,
    required this.vaultService,
    required this.backupService,
    required this.lanTransferService,
  });

  final VaultRepository repository;
  final VaultService vaultService;
  final BackupService backupService;
  final LanTransferService lanTransferService;
}

class _AppServicesLanSessionHarness {
  const _AppServicesLanSessionHarness({
    required this.services,
    required this.target,
    required this.localhostPayload,
  });

  final AppServices services;
  final _LanTransferHarness target;
  final LanTransferQrPayload localhostPayload;
}

class _LocalhostLanTransferService extends LanTransferService {
  _LocalhostLanTransferService(BackupService backupService)
    : super(
        backupService: backupService,
        server: LanTransferServer(crypto: _transferCrypto()),
        client: LanTransferClient(crypto: _transferCrypto()),
      );

  @override
  Future<LanTransferSession> createSendSession({
    required List<String> itemIds,
    required bool includeBlobs,
    required bool includeHistory,
    required String senderName,
    Duration ttl = const Duration(minutes: 5),
    String bindHost = '0.0.0.0',
    String? advertisedHost,
  }) {
    return super.createSendSession(
      itemIds: itemIds,
      includeBlobs: includeBlobs,
      includeHistory: includeHistory,
      senderName: senderName,
      ttl: ttl,
      bindHost: '127.0.0.1',
      advertisedHost: '127.0.0.1',
    );
  }
}

class _RealHttpOverrides extends HttpOverrides {
  @override
  // ignore: unnecessary_overrides
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

class _RecordingLanTransferService extends LanTransferService {
  _RecordingLanTransferService(BackupService backupService)
    : super(
        backupService: backupService,
        server: LanTransferServer(crypto: _transferCrypto()),
        client: LanTransferClient(crypto: _transferCrypto()),
      );

  bool createCalled = false;
  bool receiveCalled = false;
  bool cancelCalled = false;

  @override
  Future<LanTransferSession> createSendSession({
    required List<String> itemIds,
    required bool includeBlobs,
    required bool includeHistory,
    required String senderName,
    Duration ttl = const Duration(minutes: 5),
    String bindHost = '0.0.0.0',
    String? advertisedHost,
  }) async {
    createCalled = true;
    expect(itemIds, ['item-1']);
    expect(includeBlobs, isFalse);
    expect(includeHistory, isTrue);
    expect(senderName, 'Sender');
    return LanTransferSession(
      qrPayload: LanTransferQrPayload(
        host: '127.0.0.1',
        port: 1,
        sessionId: 'session',
        token: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        transferKey: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
        packageSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        selectedCount: 1,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        senderName: 'Sender',
      ),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<LanTransferImportResult> receiveFromPayload({
    required LanTransferQrPayload payload,
    required String sourceMasterPassword,
  }) async {
    receiveCalled = true;
    expect(sourceMasterPassword, 'source-master');
    return const LanTransferImportResult(
      importedCount: 1,
      skippedCount: 0,
      conflicts: [],
    );
  }

  @override
  Future<void> cancelSendSession() async {
    cancelCalled = true;
  }
}
