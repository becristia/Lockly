import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/shared/widgets/secure_dialog.dart';

void main() {
  test('feature dialogs use the shared secure dialog surface', () {
    final dialogFiles = [
      File('lib/features/lan_sync/lan_send_page.dart'),
      File('lib/features/lan_sync/lan_receive_page.dart'),
      File('lib/features/trash/trash_page.dart'),
      File('lib/features/tag_management/tag_management_page.dart'),
      File('lib/features/totp/totp_page.dart'),
      File('lib/features/vault_detail/vault_detail_page.dart'),
      File('lib/features/vault_edit/vault_edit_page.dart'),
      File('lib/features/settings/settings_page.dart'),
    ];
    final offenders = <String>[];

    for (final file in dialogFiles) {
      final content = file.readAsStringSync();
      if (content.contains('AlertDialog(')) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('save-in-progress dialogs block route dismissal paths', () {
    final settings = File(
      'lib/features/settings/settings_page.dart',
    ).readAsStringSync();
    final vaultDetail = File(
      'lib/features/vault_detail/vault_detail_page.dart',
    ).readAsStringSync();

    expect(
      settings,
      matches(
        RegExp(
          r'Future<bool\?> _showMasterPasswordChangeDialog[\s\S]*?showDialog<bool>\([\s\S]*?barrierDismissible: false',
        ),
      ),
    );
    expect(
      settings,
      matches(
        RegExp(
          r'class _MasterPasswordChangeDialogState[\s\S]*?return PopScope\([\s\S]*?canPop: !_isSaving',
        ),
      ),
    );
    expect(
      vaultDetail,
      matches(
        RegExp(
          r'Future<void> _showAddAttachmentDialog[\s\S]*?showDialog<bool>\([\s\S]*?barrierDismissible: false',
        ),
      ),
    );
    expect(
      vaultDetail,
      matches(
        RegExp(
          r'class _AddAttachmentDialogState[\s\S]*?return PopScope\([\s\S]*?canPop: !_isSaving',
        ),
      ),
    );
  });

  testWidgets(
    'secure dialog action row gives cancel a soft full-width surface',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => SecureDialog(
                        icon: Icons.lock_outline_rounded,
                        title: 'Title',
                        message: 'Message',
                        actions: [
                          SecureDialogAction.cancel(context),
                          SecureDialogAction.primary(
                            label: 'Confirm',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(SecureDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('secure-dialog-cancel-action')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('secure-dialog-cancel-action')))
            .width,
        greaterThan(120),
      );
    },
  );

  testWidgets('secure dialog cancel action can be disabled explicitly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => SecureDialog(
                      icon: Icons.lock_outline_rounded,
                      title: 'Saving',
                      message: 'Please wait while the secure change finishes.',
                      actions: [
                        SecureDialogAction.primary(
                          label: 'Save',
                          onPressed: null,
                          busy: true,
                        ),
                        SecureDialogAction.cancel(context, enabled: false),
                      ],
                    ),
                  );
                },
                child: const Text('Open disabled cancel'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open disabled cancel'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const ValueKey('secure-dialog-cancel-action')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SecureDialog), findsOneWidget);
  });

  testWidgets(
    'secure dialog scrolls long message content before actions overflow',
    (tester) async {
      final longMessage = List.filled(
        36,
        'A very long dynamic item name remains readable in the secure dialog.',
      ).join(' ');

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 360),
              textScaler: TextScaler.linear(2),
            ),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (context) => SecureDialog(
                          icon: Icons.delete_outline_rounded,
                          title: 'Delete item',
                          message: longMessage,
                          destructive: true,
                          actions: [
                            SecureDialogAction.destructive(
                              label: 'Delete',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            SecureDialogAction.cancel(context),
                          ],
                        ),
                      );
                    },
                    child: const Text('Open long dialog'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open long dialog'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SecureDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('secure-dialog-cancel-action')),
        findsOneWidget,
      );
    },
  );
}
