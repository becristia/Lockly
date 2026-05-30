import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/cancellation/cancellation_token.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_server.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/features/lan_sync/lan_receive_page.dart';
import 'package:secure_box/shared/i18n/app_strings_zh.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'LAN scanner platform gate excludes desktop targets without cameras',
    () {
      expect(isLanScannerPlatformSupported(TargetPlatform.android), isTrue);
      expect(isLanScannerPlatformSupported(TargetPlatform.iOS), isTrue);
      expect(isLanScannerPlatformSupported(TargetPlatform.macOS), isTrue);
      expect(isLanScannerPlatformSupported(TargetPlatform.windows), isFalse);
      expect(isLanScannerPlatformSupported(TargetPlatform.linux), isFalse);
      expect(isLanScannerPlatformSupported(TargetPlatform.fuchsia), isFalse);
    },
  );

  testWidgets('settings opens LAN send flow and creates QR session', (
    tester,
  ) async {
    final session = LanTransferSession(
      qrPayload: _validPayload(senderName: 'Office phone'),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
    List<String>? createdItemIds;
    bool? createdIncludeBlobs;
    bool? createdIncludeHistory;

    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: '',
          tags: const ['dev'],
        ),
      ],
      createLanSendSessionOverride:
          ({
            required itemIds,
            required includeBlobs,
            required includeHistory,
            required sourceMasterPassword,
            required senderName,
          }) async {
            createdItemIds = List<String>.from(itemIds);
            createdIncludeBlobs = includeBlobs;
            createdIncludeHistory = includeHistory;
            expect(sourceMasterPassword, 'source-master');
            return session;
          },
      cancelLanSendSessionOverride: () async {},
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    services.navigatorKey.currentState!.pushNamed(AppServices.routeSettings);
    await tester.pumpAndSettle();

    final sendTile = find.byKey(const ValueKey('settings-lan-send'));
    await tester.scrollUntilVisible(sendTile, 160);
    await tester.tap(sendTile);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lan-send-page')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lan-send-item-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lan-send-create-session')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lan-send-source-master-password-field')),
      'source-master',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lan-send-confirm-password')));
    await tester.pumpAndSettle();

    expect(createdItemIds, ['item-1']);
    expect(createdIncludeBlobs, isTrue);
    expect(createdIncludeHistory, isFalse);
    expect(services.autoLockService.timeout, const Duration(minutes: 5));
    expect(find.byKey(const ValueKey('lan-send-qr')), findsOneWidget);
    expect(find.textContaining('secret-password'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('lan-send-cancel-session')));
    await tester.pumpAndSettle();

    expect(services.autoLockService.timeout, const Duration(minutes: 2));
  });

  testWidgets('LAN send can select standalone MFA entries', (tester) async {
    final session = LanTransferSession(
      qrPayload: _validPayload(senderName: 'Office phone'),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
    List<String>? createdItemIds;

    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: '',
          tags: const ['dev'],
        ),
        PasswordEntry(
          title: 'GitHub MFA',
          website: '',
          username: 'mfa@example.com',
          password: '',
          notes: '',
          tags: const ['mfa'],
          totpSecret: 'JBSWY3DPEHPK3PXP',
          isStandaloneTotp: true,
        ),
      ],
      createLanSendSessionOverride:
          ({
            required itemIds,
            required includeBlobs,
            required includeHistory,
            required sourceMasterPassword,
            required senderName,
          }) async {
            createdItemIds = List<String>.from(itemIds);
            return session;
          },
      cancelLanSendSessionOverride: () async {},
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    services.navigatorKey.currentState!.pushNamed(AppServices.routeLanSend);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lan-send-item-item-2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lan-send-item-item-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lan-send-create-session')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lan-send-source-master-password-field')),
      'source-master',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lan-send-confirm-password')));
    await tester.pumpAndSettle();

    expect(createdItemIds, ['item-2']);
    expect(find.byKey(const ValueKey('lan-send-qr')), findsOneWidget);
  });

  testWidgets('send flow does not report record loading as network failure', (
    tester,
  ) async {
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      listItemsOverride: (_) async {
        throw StateError('local list failed');
      },
      listTotpItemsOverride: () async => const [],
      trackActivity: false,
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    services.navigatorKey.currentState!.pushNamed(AppServices.routeLanSend);
    await tester.pumpAndSettle();

    const strings = AppStringsZh();
    expect(find.text(strings.text('lanRecordsLoadFailed')), findsOneWidget);
    expect(find.text(strings.text('lanNetworkUnavailable')), findsNothing);
  });

  testWidgets('send flow keeps extended auto-lock when cancel fails', (
    tester,
  ) async {
    final session = LanTransferSession(
      qrPayload: _validPayload(senderName: 'Office phone'),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );

    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: '',
          tags: const ['dev'],
        ),
      ],
      createLanSendSessionOverride:
          ({
            required itemIds,
            required includeBlobs,
            required includeHistory,
            required sourceMasterPassword,
            required senderName,
          }) async => session,
      cancelLanSendSessionOverride: () async {
        throw StateError('cancel failed');
      },
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    services.navigatorKey.currentState!.pushNamed(AppServices.routeLanSend);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lan-send-item-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lan-send-create-session')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lan-send-source-master-password-field')),
      'source-master',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lan-send-confirm-password')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lan-send-cancel-session')));
    await tester.pumpAndSettle();

    expect(services.autoLockService.timeout, const Duration(minutes: 5));
    expect(find.byKey(const ValueKey('lan-send-qr')), findsOneWidget);
    expect(
      find.text(const AppStringsZh().text('lanSessionUnavailable')),
      findsOneWidget,
    );
  });

  testWidgets(
    'send flow shows session unavailable when session creation fails',
    (tester) async {
      final services = AppServices.fake(
        hasVault: true,
        unlocked: true,
        initialVaultItems: [
          PasswordEntry(
            title: 'GitHub',
            website: 'https://github.com',
            username: 'user@example.com',
            password: 'secret-password',
            notes: '',
            tags: const ['dev'],
          ),
        ],
        createLanSendSessionOverride:
            ({
              required itemIds,
              required includeBlobs,
              required includeHistory,
              required sourceMasterPassword,
              required senderName,
            }) async {
              throw StateError('session unavailable');
            },
      );

      await tester.pumpWidget(SecureBoxApp(services: services));
      await tester.pumpAndSettle();
      services.navigatorKey.currentState!.pushNamed(AppServices.routeLanSend);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('lan-send-item-item-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lan-send-create-session')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lan-send-source-master-password-field')),
        'source-master',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lan-send-confirm-password')));
      await tester.pumpAndSettle();

      const strings = AppStringsZh();
      expect(find.text(strings.text('lanSessionUnavailable')), findsOneWidget);
      expect(find.text(strings.text('lanNoRecordsSelected')), findsNothing);
    },
  );

  testWidgets(
    'send flow cancels in-flight session creation after leaving page',
    (tester) async {
      final createCompleter = Completer<LanTransferSession>();
      var cancelCalls = 0;

      final services = AppServices.fake(
        hasVault: true,
        unlocked: true,
        initialVaultItems: [
          PasswordEntry(
            title: 'GitHub',
            website: 'https://github.com',
            username: 'user@example.com',
            password: 'secret-password',
            notes: '',
            tags: const ['dev'],
          ),
        ],
        createLanSendSessionOverride:
            ({
              required itemIds,
              required includeBlobs,
              required includeHistory,
              required sourceMasterPassword,
              required senderName,
            }) => createCompleter.future,
        cancelLanSendSessionOverride: () async {
          cancelCalls += 1;
        },
      );

      await tester.pumpWidget(SecureBoxApp(services: services));
      await tester.pumpAndSettle();
      services.navigatorKey.currentState!.pushNamed(AppServices.routeLanSend);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('lan-send-item-item-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lan-send-create-session')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lan-send-source-master-password-field')),
        'source-master',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lan-send-confirm-password')));
      await tester.pump();

      services.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      createCompleter.complete(
        LanTransferSession(
          qrPayload: _validPayload(senderName: 'Office phone'),
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        ),
      );
      await tester.pumpAndSettle();

      expect(cancelCalls, greaterThanOrEqualTo(1));
    },
  );

  testWidgets('send QR scales down on narrow screens', (tester) async {
    final originalSize = tester.view.physicalSize;
    final originalDevicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalDevicePixelRatio;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(260, 720);

    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
        PasswordEntry(
          title: 'GitHub',
          website: 'https://github.com',
          username: 'user@example.com',
          password: 'secret-password',
          notes: '',
          tags: const ['dev'],
        ),
      ],
      createLanSendSessionOverride:
          ({
            required itemIds,
            required includeBlobs,
            required includeHistory,
            required sourceMasterPassword,
            required senderName,
          }) async => LanTransferSession(
            qrPayload: _validPayload(senderName: 'Office phone'),
            expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          ),
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    services.navigatorKey.currentState!.pushNamed(AppServices.routeLanSend);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lan-send-item-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lan-send-create-session')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lan-send-source-master-password-field')),
      'source-master',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lan-send-confirm-password')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('lan-send-qr'))).width,
      lessThanOrEqualTo(236),
    );
  });

  testWidgets(
    'receive flow disables scanner on Windows and keeps paste fallback',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final services = AppServices.fake(hasVault: true, unlocked: true);

      await tester.pumpWidget(SecureBoxApp(services: services));
      await tester.pumpAndSettle();
      services.navigatorKey.currentState!.pushNamed(
        AppServices.routeLanReceive,
      );
      await tester.pumpAndSettle();

      expect(
        find.text(const AppStringsZh().text('lanScannerUnavailable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('lan-receive-paste-field')),
        findsOneWidget,
      );
      expect(find.byType(MobileScanner), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'receive flow imports accepted entries without asking for source password',
    (tester) async {
      final payload = _validPayload(senderName: 'Source device');
      var receiveCalled = false;

      final services = AppServices.fake(
        hasVault: true,
        unlocked: true,
        receiveLanTransferOverride:
            ({required payload, required cancellationToken}) async {
              receiveCalled = true;
              return const LanTransferImportResult(
                importedCount: 1,
                skippedCount: 1,
                conflicts: [
                  LanTransferConflict(
                    title: 'GitHub',
                    website: 'https://github.com',
                    username: 'user@example.com',
                    reason: LanTransferConflictReason.existingLocalEntry,
                  ),
                ],
              );
            },
      );

      await tester.pumpWidget(SecureBoxApp(services: services));
      await tester.pumpAndSettle();
      services.navigatorKey.currentState!.pushNamed(
        AppServices.routeLanReceive,
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('lan-receive-paste-field')),
        payload.encode(),
      );
      await tester.tap(
        find.byKey(const ValueKey('lan-receive-use-pasted-payload')),
      );
      await tester.pumpAndSettle();

      final pasteField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('lan-receive-paste-field')),
      );
      expect(pasteField.controller?.text, isEmpty);
      expect(find.textContaining(payload.transferKey), findsNothing);
      expect(
        find.byKey(const ValueKey('lan-source-master-password-field')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('lan-receive-import-button')));
      await tester.pumpAndSettle();

      expect(receiveCalled, isTrue);
      expect(find.textContaining('source-master'), findsNothing);
      expect(find.byKey(const ValueKey('lan-import-result')), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
    },
  );

  testWidgets('receive confirmation dialog clears pending payload on cancel', (
    tester,
  ) async {
    final payload = _validPayload(senderName: 'Source device');
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    services.navigatorKey.currentState!.pushNamed(AppServices.routeLanReceive);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('lan-receive-paste-field')),
      payload.encode(),
    );
    await tester.tap(
      find.byKey(const ValueKey('lan-receive-use-pasted-payload')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, const AppStringsZh().text('cancel')),
    );

    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('lan-source-master-password-field')),
      findsNothing,
    );
    expect(find.text('Source device'), findsNothing);
    expect(find.textContaining('source-master'), findsNothing);
  });

  testWidgets('receive confirmation can be cancelled while importing', (
    tester,
  ) async {
    final payload = _validPayload(senderName: 'Source device');
    final importCompleter = Completer<LanTransferImportResult>();
    CancellationToken? capturedCancellationToken;
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      receiveLanTransferOverride:
          ({required payload, required cancellationToken}) {
            capturedCancellationToken = cancellationToken;
            return importCompleter.future;
          },
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    services.navigatorKey.currentState!.pushNamed(AppServices.routeLanReceive);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('lan-receive-paste-field')),
      payload.encode(),
    );
    await tester.tap(
      find.byKey(const ValueKey('lan-receive-use-pasted-payload')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lan-receive-import-button')));
    await tester.pump();

    await tester.tap(
      find.widgetWithText(OutlinedButton, const AppStringsZh().text('cancel')),
    );
    await tester.pumpAndSettle();

    expect(capturedCancellationToken?.isCancelled, isTrue);
    expect(
      find.byKey(const ValueKey('lan-source-master-password-field')),
      findsNothing,
    );
    expect(find.textContaining('source-master'), findsNothing);

    importCompleter.complete(
      const LanTransferImportResult(
        importedCount: 1,
        skippedCount: 0,
        conflicts: [],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('receive confirmation cancels import when dismissed by back', (
    tester,
  ) async {
    final payload = _validPayload(senderName: 'Source device');
    final importCompleter = Completer<LanTransferImportResult>();
    CancellationToken? capturedCancellationToken;
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      receiveLanTransferOverride:
          ({required payload, required cancellationToken}) {
            capturedCancellationToken = cancellationToken;
            return importCompleter.future;
          },
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    services.navigatorKey.currentState!.pushNamed(AppServices.routeLanReceive);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('lan-receive-paste-field')),
      payload.encode(),
    );
    await tester.tap(
      find.byKey(const ValueKey('lan-receive-use-pasted-payload')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lan-receive-import-button')));
    await tester.pump();

    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await tester.pumpAndSettle();

    expect(capturedCancellationToken?.isCancelled, isTrue);
    expect(
      find.byKey(const ValueKey('lan-source-master-password-field')),
      findsNothing,
    );

    importCompleter.complete(
      const LanTransferImportResult(
        importedCount: 1,
        skippedCount: 0,
        conflicts: [],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

LanTransferQrPayload _validPayload({required String senderName}) {
  return LanTransferQrPayload(
    host: '127.0.0.1',
    port: 8719,
    sessionId: 'session-1',
    token: encodeLanTransferBase64UrlNoPadding(Uint8List(32)),
    transferKey: encodeLanTransferBase64UrlNoPadding(
      Uint8List.fromList(List<int>.filled(32, 1)),
    ),
    packagePassword: encodeLanTransferBase64UrlNoPadding(
      Uint8List.fromList(List<int>.filled(32, 2)),
    ),
    packageSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    selectedCount: 1,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    senderName: senderName,
  );
}
