import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/data/db/sync_state_dao.dart';
import 'package:secure_box/features/security_center/security_center_page.dart';

void main() {
  testWidgets('security center summarizes core safety areas', (tester) async {
    var healthCalls = 0;
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      analyzePasswordHealthOverride: () async {
        healthCalls += 1;
        return const HealthReport(
          totalItems: 4,
          findings: <HealthFinding>[],
          score: 96,
          categoryCounts: <HealthCategory, int>{},
        );
      },
      cloudDevices: const [
        SyncDevice(
          id: 'device-1',
          deviceName: 'Pixel',
          deviceType: 'android',
          trusted: true,
          lastSyncAt: '2026-05-23T09:00:00Z',
          createdAt: '2026-05-22T09:00:00Z',
        ),
      ],
      emergencyContacts: const [
        EmergencyContact(
          id: 'contact-1',
          ownerUserId: 'owner-1',
          recipientUserId: 'recipient-1',
          recipientEmail: 'friend@example.test',
          recipientPublicKey:
              'lockly-x25519-public-v1.0000000000000000000000000000000000000000000000000000000000000000',
          recipientKeyFingerprint:
              'x25519-sha256.0000000000000000000000000000000000000000000000000000000000000000',
          status: 'active',
          createdAt: '2026-05-24T00:00:00Z',
        ),
      ],
      emergencyGrants: const [
        EmergencyGrant(
          id: 'grant-1',
          ownerUserId: 'owner-1',
          recipientUserId: 'recipient-1',
          contactId: 'contact-1',
          vaultId: 'vault-1',
          status: 'ready_for_download',
          waitingPeriodHours: 24,
          packageAad:
              '{"schema":"lockly-emergency-package-v1","mac":"emergency-mac","recipient_key_fingerprint":"x25519-sha256.0000000000000000000000000000000000000000000000000000000000000000"}',
          packageFingerprint:
              'pkg-sha256.0000000000000000000000000000000000000000000000000000000000000000',
          recipientKeyFingerprint:
              'x25519-sha256.0000000000000000000000000000000000000000000000000000000000000000',
          createdAt: '2026-05-24T00:00:00Z',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: SecurityCenterPage(services: services)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('security-center-page')), findsOneWidget);
    expect(find.text('安全中心'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('security-center-health-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('security-center-conflicts-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('security-center-devices-card')),
      findsOneWidget,
    );
    await _dragPrimaryList(tester, -520);
    expect(
      find.byKey(const ValueKey('security-center-emergency-card')),
      findsOneWidget,
    );
    expect(find.text('紧急访问'), findsOneWidget);
    expect(find.textContaining('1 个活动联系人'), findsOneWidget);
    expect(find.textContaining('1 个授权'), findsOneWidget);
    expect(healthCalls, 0);

    await _dragPrimaryList(tester, 520);
    await tester.tap(find.text('运行本地检查'));
    await tester.pumpAndSettle();

    await _dragPrimaryList(tester, 240);
    expect(healthCalls, 1);
    expect(find.text('96/100 健康分'), findsOneWidget);

    expect(
      find.byKey(
        const ValueKey('security-center-migration'),
        skipOffstage: false,
      ),
      findsWidgets,
    );
    expect(
      find.byKey(
        const ValueKey('security-center-attachments'),
        skipOffstage: false,
      ),
      findsWidgets,
    );
    expect(
      find.byKey(
        const ValueKey('security-center-passkeys'),
        skipOffstage: false,
      ),
      findsWidgets,
    );
    expect(
      find.byKey(
        const ValueKey('security-center-emergency-access'),
        skipOffstage: false,
      ),
      findsWidgets,
    );
  });

  testWidgets('security center opens emergency access management page', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(
      MaterialApp(home: SecurityCenterPage(services: services)),
    );
    await tester.pumpAndSettle();

    final manageEmergencyButton = find
        .byKey(const ValueKey('security-center-manage-emergency-access'))
        .last;
    await _dragPrimaryList(tester, -720);
    await tester.tap(manageEmergencyButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('emergency-access-page')), findsOneWidget);
  });

  testWidgets('security center shows conflict count without payload bytes', (
    tester,
  ) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      analyzePasswordHealthOverride: () async => const HealthReport(
        totalItems: 1,
        findings: <HealthFinding>[],
        score: 100,
        categoryCounts: <HealthCategory, int>{},
      ),
      syncConflicts: const [
        SyncConflictRecord(
          itemId: 'item-1',
          clientRevision: 1,
          serverRevision: 2,
          remotePayload: 'remote-secret-ciphertext',
          createdAt: 1770000000000,
        ),
        SyncConflictRecord(
          itemId: 'item-2',
          clientRevision: 3,
          serverRevision: 4,
          remotePayload: 'another-remote-secret',
          createdAt: 1770000001000,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: SecurityCenterPage(services: services)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2 个未解决冲突'), findsOneWidget);
    expect(find.textContaining('remote-secret-ciphertext'), findsNothing);
    expect(find.textContaining('another-remote-secret'), findsNothing);
  });

  testWidgets('security center includes encrypted blob sync conflicts', (
    tester,
  ) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      syncBlobConflicts: const [
        SyncBlobConflictRecord(
          blobId: 'blob-1',
          clientRevision: 1,
          serverRevision: 3,
          remotePayload:
              '{"ciphertext":"blob-secret-ciphertext","filename":"recovery.txt","attachment":"plaintext"}',
          createdAt: 1770000002000,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: SecurityCenterPage(services: services)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1 个未解决冲突'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('security-center-conflicts-card')),
    );
    await tester.pumpAndSettle();

    expect(find.text('加密数据块'), findsOneWidget);
    expect(find.text('blob-1'), findsOneWidget);
    expect(find.text('本地版本 1'), findsOneWidget);
    expect(find.text('云端版本 3'), findsOneWidget);
    expect(find.textContaining('blob-secret-ciphertext'), findsNothing);
    expect(find.textContaining('recovery.txt'), findsNothing);
    expect(find.textContaining('plaintext'), findsNothing);
  });

  testWidgets('conflict card opens safe metadata list without payload data', (
    tester,
  ) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      syncConflicts: const [
        SyncConflictRecord(
          itemId: 'item-1',
          clientRevision: 1,
          serverRevision: 2,
          remotePayload:
              '{"ciphertext":"remote-secret-ciphertext","title":"Bank","username":"alice","password":"secret","note":"private","totp":"123456","passkey":"credential","attachment":"file"}',
          createdAt: 1770000000000,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: SecurityCenterPage(services: services)),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('security-center-conflicts-card')),
    );
    await tester.pumpAndSettle();

    expect(find.text('同步冲突'), findsOneWidget);
    expect(find.text('item-1'), findsOneWidget);
    expect(find.text('本地版本 1'), findsOneWidget);
    expect(find.text('云端版本 2'), findsOneWidget);
    expect(find.text('本地时间戳 1770000000000'), findsOneWidget);
    expect(find.textContaining('remote-secret-ciphertext'), findsNothing);
    expect(find.textContaining('Bank'), findsNothing);
    expect(find.textContaining('alice'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('private'), findsNothing);
    expect(find.textContaining('123456'), findsNothing);
    expect(find.textContaining('credential'), findsNothing);
    expect(find.textContaining('file'), findsNothing);
  });

  testWidgets(
    'conflict dialog downloads after master password confirmation and refreshes count',
    (tester) async {
      final conflicts = <SyncConflictRecord>[
        const SyncConflictRecord(
          itemId: 'item-1',
          clientRevision: 1,
          serverRevision: 2,
          remotePayload: 'remote-secret-ciphertext',
          createdAt: 1770000000000,
        ),
      ];
      String? unlockPassword;
      String? downloadPassword;
      final services = AppServices(
        hasVault: true,
        initialShellState: AppShellState.unlocked,
        unlockOverride: (masterPassword) async {
          unlockPassword = masterPassword;
          return true;
        },
        cloudDownloadOverride: (masterPassword) async {
          downloadPassword = masterPassword;
          conflicts.clear();
          return 1;
        },
        listSyncConflictsOverride: () async => List.unmodifiable(conflicts),
        listSyncBlobConflictsOverride: () async =>
            const <SyncBlobConflictRecord>[],
        listCloudDevicesOverride: () async => const <SyncDevice>[],
        trackActivity: false,
      );
      addTearDown(services.dispose);

      await tester.pumpWidget(
        MaterialApp(home: SecurityCenterPage(services: services)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1 个未解决冲突'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('security-center-conflicts-card')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载最新加密密码库'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sync-conflict-master-password-field')),
        'local-master-password',
      );
      await tester.tap(find.text('下载'));
      await tester.pumpAndSettle();

      expect(unlockPassword, 'local-master-password');
      expect(downloadPassword, 'local-master-password');
      expect(find.textContaining('local-master-password'), findsNothing);
      expect(find.textContaining('没有未解决冲突'), findsOneWidget);
    },
  );

  testWidgets(
    'security center summarizes device trust risk without payload data',
    (tester) async {
      final services = AppServices.fake(
        hasVault: true,
        unlocked: true,
        cloudDevices: const [
          SyncDevice(
            id: 'device-1',
            deviceName: 'Current laptop',
            deviceType: 'desktop',
            platform: 'windows',
            clientVersion: '1.4.2',
            trusted: true,
            lastSyncAt: '2099-05-23T09:00:00Z',
            lastIpAddress: '203.0.113.10',
            lastUserAgent: 'Lockly/1.4.2 Windows',
            createdAt: '2026-05-22T09:00:00Z',
          ),
          SyncDevice(
            id: 'device-2',
            deviceName: 'Unknown phone',
            deviceType: 'mobile',
            trusted: false,
            lastSyncAt: '2020-01-01T00:00:00Z',
            createdAt: '2026-05-22T09:00:00Z',
          ),
          SyncDevice(
            id: 'device-3',
            deviceName: 'Old tablet',
            deviceType: 'tablet',
            trusted: true,
            lastSyncAt: 'ciphertext-payload-should-not-render',
            createdAt: '2026-05-20T09:00:00Z',
            revokedAt: '2026-05-23T08:00:00Z',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: SecurityCenterPage(services: services)),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 / 2 台活动设备受信任'), findsOneWidget);
      expect(find.textContaining('1 已撤销'), findsOneWidget);
      expect(find.textContaining('3 个风险指标'), findsOneWidget);
      expect(
        find.textContaining('ciphertext-payload-should-not-render'),
        findsNothing,
      );
    },
  );

  testWidgets('vault shell opens security center tab', (tester) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      analyzePasswordHealthOverride: () async => const HealthReport(
        totalItems: 0,
        findings: <HealthFinding>[],
        score: 100,
        categoryCounts: <HealthCategory, int>{},
      ),
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('vault-shell-security-tab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('security-center-page')), findsOneWidget);
  });
}

Future<void> _dragPrimaryList(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(ListView).first, Offset(0, dy));
  await tester.pumpAndSettle();
}
