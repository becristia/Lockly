import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/shared/i18n/app_language.dart';

void main() {
  testWidgets('TOTP page exposes scan and manual standalone entry actions', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);
    services.language = AppLanguage.en;

    await tester.pumpWidget(SecureBoxApp(services: services));
    await _openTotpTab(tester);

    expect(find.byKey(const ValueKey('totp-scan-entry')), findsWidgets);
    expect(find.byKey(const ValueKey('totp-manual-entry')), findsWidgets);
    expect(find.byKey(const ValueKey('totp-empty-state')), findsOneWidget);
  });

  testWidgets('manual standalone TOTP save creates encrypted vault entry', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);
    services.language = AppLanguage.en;

    await tester.pumpWidget(SecureBoxApp(services: services));
    await _openTotpTab(tester);
    await tester.tap(find.byKey(const ValueKey('totp-manual-entry')).first);
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('totp-standalone-title-field')),
      'GitHub MFA',
    );
    await tester.enterText(
      find.byKey(const ValueKey('totp-standalone-username-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('totp-standalone-secret-field')),
      'jbsw y3dp-ehpk 3pxp',
    );
    await tester.tap(find.byKey(const ValueKey('totp-standalone-save-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final totpItems = await services.listTotpItems();
    expect(totpItems.single.title, 'GitHub MFA');
    expect(totpItems.single.username, 'user@example.com');
    expect(totpItems.single.totpSecret, 'JBSWY3DPEHPK3PXP');
    expect(totpItems.single.isStandalone, isTrue);
    expect(find.text('Standalone MFA'), findsOneWidget);
  });

  testWidgets('manual standalone TOTP validates malformed secrets', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);
    services.language = AppLanguage.en;

    await tester.pumpWidget(SecureBoxApp(services: services));
    await _openTotpTab(tester);
    await tester.tap(find.byKey(const ValueKey('totp-manual-entry')).first);
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('totp-standalone-title-field')),
      'GitHub MFA',
    );
    await tester.enterText(
      find.byKey(const ValueKey('totp-standalone-secret-field')),
      'not-valid-0',
    );
    await tester.tap(find.byKey(const ValueKey('totp-standalone-save-button')));
    await tester.pump();

    expect(find.text('Enter a valid Base32 or otpauth secret'), findsOneWidget);
    expect(await services.listTotpItems(), isEmpty);
  });

  testWidgets('standalone and vault-linked cards show source labels', (
    tester,
  ) async {
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
          totpSecret: 'JBSWY3DPEHPK3PXP',
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
    );
    services.language = AppLanguage.en;

    await tester.pumpWidget(SecureBoxApp(services: services));
    await _openTotpTab(tester);

    await tester.scrollUntilVisible(find.text('Vault linked'), 160);
    expect(find.text('Vault linked'), findsOneWidget);
    expect(find.text('Standalone MFA'), findsOneWidget);
  });

  testWidgets('invalid stored TOTP secret does not crash the page', (
    tester,
  ) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
        PasswordEntry(
          title: 'Imported MFA',
          website: '',
          username: 'mfa@example.com',
          password: '',
          notes: '',
          tags: const ['mfa'],
          totpSecret: '123456',
          isStandaloneTotp: true,
        ),
      ],
    );
    services.language = AppLanguage.en;

    await tester.pumpWidget(SecureBoxApp(services: services));
    await _openTotpTab(tester);

    expect(find.text('Enter a valid Base32 or otpauth secret'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone TOTP entries can be edited', (tester) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
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
    );
    services.language = AppLanguage.en;

    await tester.pumpWidget(SecureBoxApp(services: services));
    await _openTotpTab(tester);

    await tester.tap(find.byKey(const ValueKey('totp-standalone-menu-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('totp-standalone-edit-item-1')));
    await tester.pumpAndSettle();

    expect(find.text('JBSWY3DPEHPK3PXP'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('totp-standalone-title-field')),
      'GitLab MFA',
    );
    await tester.enterText(
      find.byKey(const ValueKey('totp-standalone-username-field')),
      'gitlab@example.com',
    );
    await tester.tap(find.byKey(const ValueKey('totp-standalone-save-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final totpItems = await services.listTotpItems();
    expect(totpItems.single.title, 'GitLab MFA');
    expect(totpItems.single.username, 'gitlab@example.com');
    expect(totpItems.single.totpSecret, 'JBSWY3DPEHPK3PXP');
    expect(totpItems.single.isStandalone, isTrue);
  });

  testWidgets('standalone TOTP edit can replace the secret explicitly', (
    tester,
  ) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
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
    );
    services.language = AppLanguage.en;

    await tester.pumpWidget(SecureBoxApp(services: services));
    await _openTotpTab(tester);

    await tester.tap(find.byKey(const ValueKey('totp-standalone-menu-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('totp-standalone-edit-item-1')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('totp-standalone-secret-field')),
      'MZXW 6YTB OI======',
    );
    await tester.tap(find.byKey(const ValueKey('totp-standalone-save-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final totpItems = await services.listTotpItems();
    expect(totpItems.single.totpSecret, 'MZXW6YTBOI');
  });

  testWidgets('standalone TOTP entries can be deleted', (tester) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      initialVaultItems: [
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
    );
    services.language = AppLanguage.en;

    await tester.pumpWidget(SecureBoxApp(services: services));
    await _openTotpTab(tester);

    await tester.tap(find.byKey(const ValueKey('totp-standalone-menu-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('totp-standalone-delete-item-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(await services.listTotpItems(), isEmpty);
  });
}

Future<void> _openTotpTab(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('vault-shell-totp-tab')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}
