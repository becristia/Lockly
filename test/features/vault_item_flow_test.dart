import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/features/vault_detail/vault_detail_page.dart';
import 'package:secure_box/features/vault_list/vault_list_page.dart';
import 'package:secure_box/shared/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
          switch (methodCall.method) {
            case 'Clipboard.setData':
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': ''};
          }

          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'user can add an item and password stays hidden by default in detail',
    (tester) async {
      final services = AppServices.fake(hasVault: true, unlocked: true);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      await tester.pumpWidget(SecureBoxApp(services: services));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('新增密码'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, '标题'),
        'GitHub',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '网址'),
        'https://github.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '用户名'),
        'user@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '密码'),
        'super-secret-123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '备注'),
        '双重验证已开启',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '标签'),
        '开发, 常用',
      );

      await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);

      await tester.tap(find.text('GitHub'));
      await tester.pumpAndSettle();

      expect(find.text('https://github.com'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);
      expect(find.text('super-secret-123'), findsNothing);
      expect(find.text('已隐藏'), findsOneWidget);

      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();

      expect(find.text('super-secret-123'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(find.text('Lockly'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
  );

  testWidgets(
    'user can add passkey preparation metadata and see it in detail',
    (tester) async {
      final services = AppServices.fake(hasVault: true, unlocked: true);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      await tester.pumpWidget(SecureBoxApp(services: services));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('新增密码'));
      await tester.pumpAndSettle();
      final editFields = find.byType(TextFormField);
      await tester.enterText(editFields.at(0), 'GitHub');
      await tester.enterText(editFields.at(1), 'https://github.com');
      await tester.enterText(editFields.at(2), 'alice');
      await tester.enterText(editFields.at(3), 'local-password');

      await tester.ensureVisible(
        find.byKey(const ValueKey('passkey-add-button')),
      );
      await tester.tap(find.byKey(const ValueKey('passkey-add-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('passkey-rp-id-input')),
        'github.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('passkey-credential-id-input')),
        'credential-id',
      );
      await tester.enterText(
        find.byKey(const ValueKey('passkey-user-handle-input')),
        'user-handle',
      );
      await tester.enterText(
        find.byKey(const ValueKey('passkey-display-name-input')),
        'Alice',
      );
      await tester.enterText(
        find.byKey(const ValueKey('passkey-algorithm-input')),
        'ES256',
      );
      await tester.enterText(
        find.byKey(const ValueKey('passkey-platform-input')),
        'android',
      );
      await tester.tap(find.byKey(const ValueKey('passkey-save-button')));
      await tester.pumpAndSettle();

      await tester.dragFrom(const Offset(400, 520), const Offset(0, -900));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GitHub'));
      await tester.pumpAndSettle();

      expect(find.text('通行密钥'), findsOneWidget);
      expect(find.text('github.com'), findsWidgets);
      expect(find.text('credential-id'), findsOneWidget);
      expect(find.text('平台 API 未启用'), findsOneWidget);
    },
  );

  testWidgets('stale search results cannot replace the latest query', (
    tester,
  ) async {
    final broadQuery = Completer<List<VaultListItem>>();
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      trackActivity: false,
      listItemsOverride: (query) {
        if (query == 'g') {
          return broadQuery.future;
        }
        if (query == 'gi') {
          return Future.value([
            VaultListItem(
              id: 'github',
              title: 'GitHub',
              website: 'https://github.com',
              username: 'user@example.com',
              tags: const [],
              createdAt: 1,
              updatedAt: 2,
            ),
          ]);
        }
        return Future.value(const <VaultListItem>[]);
      },
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: VaultListPage(services: services),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '搜索'), 'g');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '搜索'), 'gi');
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);

    broadQuery.complete([
      VaultListItem(
        id: 'google',
        title: 'Google',
        website: 'https://google.com',
        username: 'google@example.com',
        tags: const [],
        createdAt: 1,
        updatedAt: 1,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Google'), findsNothing);
  });

  testWidgets('detail page shows decrypted attachment names and sizes', (
    tester,
  ) async {
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      trackActivity: false,
      getItemOverride: (_) async => PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: '',
        tags: const [],
      ),
      listVaultBlobsOverride: (_) async => [
        VaultBlobListItem(
          blobId: 'blob-1',
          itemId: 'item-1',
          displayName: 'recovery-codes.txt',
          mediaType: 'text/plain',
          sizeBytes: 20,
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
      openVaultBlobOverride: (_) async => DecryptedVaultBlob(
        blobId: 'blob-1',
        itemId: 'item-1',
        displayName: 'recovery-codes.txt',
        mediaType: 'text/plain',
        bytes: Uint8List.fromList('plain recovery bytes'.codeUnits),
        createdAt: 1,
        updatedAt: 1,
      ),
      deleteVaultBlobOverride: (_) async {},
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: VaultDetailPage(services: services, itemId: 'item-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('附件'), findsOneWidget);
    expect(find.text('recovery-codes.txt'), findsOneWidget);
    expect(find.text('20 B'), findsOneWidget);
  });

  testWidgets('attachment add open and delete flow keeps plaintext gated', (
    tester,
  ) async {
    final attachments = <VaultBlobListItem>[];
    Uint8List? addedBytes;
    String? addedItemId;
    String? addedDisplayName;
    String? addedMediaType;

    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      trackActivity: false,
      getItemOverride: (_) async => PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: '',
        tags: const [],
      ),
      addVaultBlobOverride:
          ({
            required itemId,
            required displayName,
            required mediaType,
            required bytes,
          }) async {
            addedItemId = itemId;
            addedDisplayName = displayName;
            addedMediaType = mediaType;
            addedBytes = Uint8List.fromList(bytes);
            attachments
              ..clear()
              ..add(
                VaultBlobListItem(
                  blobId: 'blob-1',
                  itemId: itemId,
                  displayName: displayName,
                  mediaType: mediaType,
                  sizeBytes: bytes.length,
                  createdAt: 1,
                  updatedAt: 1,
                ),
              );
            return 'blob-1';
          },
      listVaultBlobsOverride: (_) async => List.unmodifiable(attachments),
      openVaultBlobOverride: (blobId) async => DecryptedVaultBlob(
        blobId: blobId,
        itemId: 'item-1',
        displayName: 'recovery-codes.txt',
        mediaType: 'text/plain',
        bytes: Uint8List.fromList('plain recovery bytes'.codeUnits),
        createdAt: 1,
        updatedAt: 1,
      ),
      deleteVaultBlobOverride: (blobId) async {
        attachments.removeWhere((attachment) => attachment.blobId == blobId);
      },
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: VaultDetailPage(services: services, itemId: 'item-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('没有附件'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('attachment-add-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('attachment-name-input')),
      'recovery-codes.txt',
    );
    await tester.enterText(
      find.byKey(const ValueKey('attachment-media-type-input')),
      'text/plain',
    );
    await tester.enterText(
      find.byKey(const ValueKey('attachment-content-input')),
      'plain recovery bytes',
    );
    await tester.tap(find.byKey(const ValueKey('attachment-save-button')));
    await tester.pumpAndSettle();

    expect(addedItemId, 'item-1');
    expect(addedDisplayName, 'recovery-codes.txt');
    expect(addedMediaType, 'text/plain');
    expect(addedBytes, Uint8List.fromList('plain recovery bytes'.codeUnits));
    expect(find.text('recovery-codes.txt'), findsOneWidget);
    expect(find.text('20 B'), findsOneWidget);
    expect(find.text('plain recovery bytes'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('attachment-open-blob-1')));
    await tester.pumpAndSettle();

    expect(find.text('recovery-codes.txt'), findsWidgets);
    expect(find.text('text/plain'), findsOneWidget);
    expect(find.text('20 B'), findsWidgets);
    expect(find.text('plain recovery bytes'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attachment-delete-blob-1')));
    await tester.pumpAndSettle();

    expect(find.text('没有附件'), findsOneWidget);
    expect(find.text('recovery-codes.txt'), findsNothing);
    expect(find.text('plain recovery bytes'), findsNothing);
  });
}
