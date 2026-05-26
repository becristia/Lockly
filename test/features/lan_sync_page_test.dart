import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_server.dart';
import 'package:secure_box/data/models/password_entry.dart';

void main() {
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
            required senderName,
          }) async {
            createdItemIds = List<String>.from(itemIds);
            createdIncludeBlobs = includeBlobs;
            createdIncludeHistory = includeHistory;
            return session;
          },
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

    expect(createdItemIds, ['item-1']);
    expect(createdIncludeBlobs, isTrue);
    expect(createdIncludeHistory, isFalse);
    expect(find.byKey(const ValueKey('lan-send-qr')), findsOneWidget);
    expect(find.textContaining('secret-password'), findsNothing);
  });

  testWidgets(
    'receive flow imports accepted entries and hides source password',
    (tester) async {
      final payload = _validPayload(senderName: 'Source device');
      String? capturedSourcePassword;

      final services = AppServices.fake(
        hasVault: true,
        unlocked: true,
        receiveLanTransferOverride:
            ({required payload, required sourceMasterPassword}) async {
              capturedSourcePassword = sourceMasterPassword;
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

      await tester.enterText(
        find.byKey(const ValueKey('lan-source-master-password-field')),
        'source-master',
      );
      await tester.tap(find.byKey(const ValueKey('lan-receive-import-button')));
      await tester.pumpAndSettle();

      expect(capturedSourcePassword, 'source-master');
      expect(find.textContaining('source-master'), findsNothing);
      expect(find.byKey(const ValueKey('lan-import-result')), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
    },
  );
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
    packageSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    selectedCount: 1,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    senderName: senderName,
  );
}
