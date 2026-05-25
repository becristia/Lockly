import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/emergency/emergency_crypto_service.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/features/emergency_access/emergency_access_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creating grant encrypts local plaintext before upload', (
    tester,
  ) async {
    final recipient = await EmergencyCryptoService().generateKeyPair();
    EmergencyGrantCreateRequest? capturedRequest;
    final grants = <EmergencyGrant>[];
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      listEmergencyContactsOverride: () async => [
        _contact(
          recipientPublicKey: recipient.publicKey,
          recipientKeyFingerprint: recipient.fingerprint,
        ),
      ],
      listEmergencyGrantsOverride: () async => List.unmodifiable(grants),
      createEmergencyGrantOverride: ({required request}) async {
        capturedRequest = request;
        final grant = _grant(
          id: 'grant-created',
          contactId: request.contactId,
          status: 'pending_acceptance',
          packageAad: request.packageAad,
          packageFingerprint: request.packageFingerprint,
        );
        grants.add(grant);
        return grant;
      },
      trackActivity: false,
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      MaterialApp(home: EmergencyAccessPage(services: services)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('emergency-grant-plaintext-field')),
      'plaintext-recovery-secret',
    );
    await tester.enterText(
      find.byKey(const ValueKey('emergency-grant-wait-hours-field')),
      '48',
    );
    final createGrantButton = find
        .byKey(const ValueKey('emergency-create-grant-button'))
        .last;
    await _dragPrimaryList(tester, -720);
    await tester.tap(createGrantButton);
    await tester.pumpAndSettle();

    final request = capturedRequest;
    expect(request, isNotNull);
    final payload = jsonEncode(request!.toJson());
    expect(payload, isNot(contains('plaintext-recovery-secret')));
    expect(request.contactId, 'contact-1');
    expect(request.waitingPeriodHours, 48);
    expect(request.encryptedRecoveryPackage, contains('ciphertext'));
    expect(request.packageAad, contains('lockly-emergency-package-v1'));
    expect(request.packageFingerprint, startsWith('pkg-sha256.'));
    expect(find.textContaining('plaintext-recovery-secret'), findsNothing);
  });

  testWidgets('generated key pair remains local and does not call services', (
    tester,
  ) async {
    var listContactCalls = 0;
    var listGrantCalls = 0;
    var createContactCalls = 0;
    var createGrantCalls = 0;
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      listEmergencyContactsOverride: () async {
        listContactCalls += 1;
        return const <EmergencyContact>[];
      },
      listEmergencyGrantsOverride: () async {
        listGrantCalls += 1;
        return const <EmergencyGrant>[];
      },
      createEmergencyContactOverride: ({required request}) async {
        createContactCalls += 1;
        throw StateError('key generation must not create contacts');
      },
      createEmergencyGrantOverride: ({required request}) async {
        createGrantCalls += 1;
        throw StateError('key generation must not create grants');
      },
      trackActivity: false,
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      MaterialApp(home: EmergencyAccessPage(services: services)),
    );
    await tester.pumpAndSettle();
    final initialListContactCalls = listContactCalls;
    final initialListGrantCalls = listGrantCalls;

    await tester.tap(
      find.byKey(const ValueKey('emergency-generate-keypair-button')),
    );
    await tester.pumpAndSettle();

    expect(listContactCalls, initialListContactCalls);
    expect(listGrantCalls, initialListGrantCalls);
    expect(createContactCalls, 0);
    expect(createGrantCalls, 0);
    expect(find.textContaining('lockly-x25519-public-v1.'), findsOneWidget);
    expect(find.textContaining('x25519-sha256.'), findsOneWidget);
    expect(find.textContaining('lockly-x25519-private-v1.'), findsOneWidget);
  });

  testWidgets(
    'generated private key is displayed without AppServices copy path',
    (tester) async {
      final services = AppServices(
        hasVault: true,
        initialShellState: AppShellState.unlocked,
        listEmergencyContactsOverride: () async => const <EmergencyContact>[],
        listEmergencyGrantsOverride: () async => const <EmergencyGrant>[],
        trackActivity: false,
      );
      addTearDown(services.dispose);

      await tester.pumpWidget(
        MaterialApp(home: EmergencyAccessPage(services: services)),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('emergency-generate-keypair-button')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('lockly-x25519-private-v1.'), findsOneWidget);
      expect(find.byTooltip('复制'), findsNWidgets(2));
    },
  );

  testWidgets('download decrypt flow keeps recipient private key local', (
    tester,
  ) async {
    final crypto = EmergencyCryptoService();
    final recipient = await crypto.generateKeyPair();
    final encrypted = await crypto.encryptPackage(
      plaintext: utf8.encode('plaintext-recovery-secret'),
      recipientPublicKey: recipient.publicKey,
      grantId: 'grant-ready',
      recipientKeyFingerprint: recipient.fingerprint,
    );
    String? downloadedGrantId;
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      listEmergencyContactsOverride: () async => [
        _contact(
          recipientPublicKey: recipient.publicKey,
          recipientKeyFingerprint: recipient.fingerprint,
        ),
      ],
      listEmergencyGrantsOverride: () async => [
        _grant(
          id: 'grant-ready',
          status: 'ready_for_download',
          packageAad: encrypted.packageAad,
          packageFingerprint: encrypted.packageFingerprint,
          recipientKeyFingerprint: recipient.fingerprint,
        ),
      ],
      downloadEmergencyAccessPackageOverride: (grantId) async {
        downloadedGrantId = grantId;
        return EmergencyAccessPackage(
          grantId: grantId,
          ownerUserId: 'owner-1',
          recipientUserId: 'recipient-1',
          contactId: 'contact-1',
          status: 'downloaded',
          encryptedRecoveryPackage: encrypted.encryptedRecoveryPackage,
          packageAad: encrypted.packageAad,
          packageFingerprint: encrypted.packageFingerprint,
          recipientKeyFingerprint: recipient.fingerprint,
        );
      },
      trackActivity: false,
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      MaterialApp(home: EmergencyAccessPage(services: services)),
    );
    await tester.pumpAndSettle();

    final downloadGrantButton = find
        .byKey(const ValueKey('emergency-download-grant-grant-ready'))
        .last;
    await _dragPrimaryList(tester, -1280);
    await tester.tap(downloadGrantButton);
    await tester.pumpAndSettle();

    expect(downloadedGrantId, 'grant-ready');
    expect(find.textContaining('plaintext-recovery-secret'), findsNothing);
    expect(find.textContaining(encrypted.packageFingerprint), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('emergency-package-private-key-field')),
      recipient.privateKey,
    );
    await tester.tap(
      find.byKey(const ValueKey('emergency-local-decrypt-package-button')),
    );
    await tester.pumpAndSettle();

    expect(downloadedGrantId, 'grant-ready');
    expect(find.text('plaintext-recovery-secret'), findsOneWidget);
  });

  testWidgets(
    'download action appears for ready grants and elapsed access requests',
    (tester) async {
      const packageAad =
          '{"schema":"lockly-emergency-package-v1","mac":"emergency-mac","recipient_key_fingerprint":"x25519-sha256.0000000000000000000000000000000000000000000000000000000000000000"}';
      const packageFingerprint =
          'pkg-sha256.0000000000000000000000000000000000000000000000000000000000000000';
      final now = DateTime.now().toUtc();
      final services = AppServices(
        hasVault: true,
        initialShellState: AppShellState.unlocked,
        listEmergencyContactsOverride: () async => const <EmergencyContact>[],
        listEmergencyGrantsOverride: () async => [
          _grant(
            id: 'grant-waiting',
            status: 'access_requested',
            packageAad: packageAad,
            packageFingerprint: packageFingerprint,
            readyAt: now.add(const Duration(hours: 1)).toIso8601String(),
          ),
          _grant(
            id: 'grant-elapsed',
            status: 'access_requested',
            packageAad: packageAad,
            packageFingerprint: packageFingerprint,
            readyAt: now.subtract(const Duration(hours: 1)).toIso8601String(),
          ),
          _grant(
            id: 'grant-ready',
            status: 'ready_for_download',
            packageAad: packageAad,
            packageFingerprint: packageFingerprint,
          ),
          _grant(
            id: 'grant-ready-too-early',
            status: 'ready_for_download',
            packageAad: packageAad,
            packageFingerprint: packageFingerprint,
            readyAt: now.add(const Duration(hours: 2)).toIso8601String(),
          ),
        ],
        trackActivity: false,
      );
      addTearDown(services.dispose);

      await tester.pumpWidget(
        MaterialApp(home: EmergencyAccessPage(services: services)),
      );
      await tester.pumpAndSettle();

      await _dragPrimaryList(tester, -1000);

      expect(
        find.byKey(const ValueKey('emergency-download-grant-grant-waiting')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('emergency-download-grant-grant-elapsed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('emergency-download-grant-grant-ready')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('emergency-download-grant-grant-ready-too-early'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('contact create and revoke flows use AppServices facade', (
    tester,
  ) async {
    final recipient = await EmergencyCryptoService().generateKeyPair();
    final services = AppServices.fake(hasVault: true, unlocked: true);
    addTearDown(services.dispose);

    await tester.pumpWidget(
      MaterialApp(home: EmergencyAccessPage(services: services)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('emergency-contact-email-field')),
      'backup@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('emergency-contact-public-key-field')),
      recipient.publicKey,
    );
    await tester.enterText(
      find.byKey(const ValueKey('emergency-contact-fingerprint-field')),
      recipient.fingerprint,
    );
    await tester.enterText(
      find.byKey(const ValueKey('emergency-contact-label-field')),
      'Backup contact',
    );
    final createContactButton = find
        .byKey(const ValueKey('emergency-create-contact-button'))
        .last;
    await _dragPrimaryList(tester, -420);
    await tester.tap(createContactButton);
    await tester.pumpAndSettle();

    expect(find.text('backup@example.test'), findsOneWidget);
    expect(find.textContaining('Backup contact'), findsWidgets);

    final revokeContactButton = find
        .byKey(const ValueKey('emergency-revoke-contact-contact-1'))
        .last;
    await _dragPrimaryList(tester, -900);
    await tester.tap(revokeContactButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销联系人').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('已撤销'), findsWidgets);
  });
}

EmergencyContact _contact({
  String recipientPublicKey =
      'lockly-x25519-public-v1.0000000000000000000000000000000000000000000000000000000000000000',
  String recipientKeyFingerprint =
      'x25519-sha256.0000000000000000000000000000000000000000000000000000000000000000',
}) {
  return EmergencyContact(
    id: 'contact-1',
    ownerUserId: 'owner-1',
    recipientUserId: 'recipient-1',
    recipientEmail: 'friend@example.test',
    recipientPublicKey: recipientPublicKey,
    recipientKeyFingerprint: recipientKeyFingerprint,
    recipientLabel: 'Friend',
    status: 'active',
    createdAt: '2026-05-24T00:00:00Z',
    updatedAt: '2026-05-24T00:00:00Z',
  );
}

EmergencyGrant _grant({
  required String id,
  String contactId = 'contact-1',
  required String status,
  required String packageAad,
  required String packageFingerprint,
  String? recipientKeyFingerprint,
  String? readyAt,
}) {
  return EmergencyGrant(
    id: id,
    ownerUserId: 'owner-1',
    recipientUserId: 'recipient-1',
    contactId: contactId,
    vaultId: 'vault-1',
    status: status,
    waitingPeriodHours: 48,
    packageAad: packageAad,
    packageFingerprint: packageFingerprint,
    recipientKeyFingerprint: recipientKeyFingerprint,
    readyAt: readyAt,
    createdAt: '2026-05-24T00:00:00Z',
    updatedAt: '2026-05-24T00:00:00Z',
  );
}

Future<void> _dragPrimaryList(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(ListView).first, Offset(0, dy));
  await tester.pumpAndSettle();
}
