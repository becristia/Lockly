import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/features/settings/settings_page.dart';
import 'package:secure_box/shared/theme/app_theme.dart';

void main() {
  testWidgets('app theme provides a dark security console surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            return Scaffold(
              body: Text(
                '${theme.brightness.name}:${theme.colorScheme.surface}',
              ),
            );
          },
        ),
      ),
    );

    expect(find.textContaining('dark:'), findsOneWidget);
    expect(
      find.textContaining('Color(alpha: 1.0000, red: 1.0000'),
      findsNothing,
    );
  });

  testWidgets('vault list shows a security summary above records', (
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
          password: 'secret-1',
          notes: '',
          tags: const [],
        ),
        PasswordEntry(
          title: 'Mail',
          website: 'https://mail.example.com',
          username: 'mail@example.com',
          password: 'secret-2',
          notes: '',
          tags: const [],
        ),
      ],
    );

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('vault-list-security-summary')),
      findsOneWidget,
    );
    expect(find.text('本地密码库'), findsOneWidget);
    expect(find.text('2 条记录仅保存在本机'), findsOneWidget);
  });

  testWidgets('settings page uses grouped security sections', (tester) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vault-shell-settings-tab')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-section-unlock')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-section-privacy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-section-backup')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-section-cloud-sync')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-section-autofill')),
      160,
    );
    expect(
      find.byKey(const ValueKey('settings-section-autofill')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Download cloud vault'), 160);
    expect(find.text('Download cloud vault'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-section-danger')),
      160,
    );
    expect(
      find.byKey(const ValueKey('settings-section-danger')),
      findsOneWidget,
    );
  });

  testWidgets('cloud sync asks for master password before importing updates', (
    tester,
  ) async {
    var syncCalled = false;
    String? submittedPassword;
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      biometricEnabledOverride: () async => false,
      autoLockTimeoutOverride: () async => const Duration(minutes: 2),
      clipboardCleanupTimeoutOverride: () async => const Duration(seconds: 30),
      cloudSyncNowOverride: (masterPassword) async {
        syncCalled = true;
        submittedPassword = masterPassword;
        return const CloudSyncResult(importedCount: 1);
      },
      trackActivity: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsPage(services: services)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sync encrypted vault'), 160);
    await tester.tap(find.text('Sync encrypted vault'));
    await tester.pumpAndSettle();

    expect(syncCalled, isFalse);
    expect(find.text('Sync encrypted vault'), findsNWidgets(2));
    expect(find.byType(TextFormField), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'local-master');
    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();

    expect(syncCalled, isTrue);
    expect(submittedPassword, 'local-master');
  });

  testWidgets('cloud download recovery asks for master password separately', (
    tester,
  ) async {
    var downloadCalled = false;
    String? submittedPassword;
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      biometricEnabledOverride: () async => false,
      autoLockTimeoutOverride: () async => const Duration(minutes: 2),
      clipboardCleanupTimeoutOverride: () async => const Duration(seconds: 30),
      cloudDownloadOverride: (masterPassword) async {
        downloadCalled = true;
        submittedPassword = masterPassword;
        return 2;
      },
      trackActivity: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsPage(services: services)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Download cloud vault'), 160);
    await tester.tap(find.text('Download cloud vault'));
    await tester.pumpAndSettle();

    expect(downloadCalled, isFalse);
    expect(find.text('Download cloud vault'), findsNWidgets(2));

    await tester.enterText(find.byType(TextFormField), 'local-master');
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(downloadCalled, isTrue);
    expect(submittedPassword, 'local-master');
  });

  testWidgets(
    'settings opens Android Autofill settings without plaintext access',
    (tester) async {
      var openSettingsCalls = 0;
      final services = AppServices.fake(
        hasVault: true,
        unlocked: true,
        autofillSupported: true,
        autofillEnabled: false,
        openAutofillSettingsOverride: () async {
          openSettingsCalls += 1;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsPage(services: services)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-section-autofill')),
        160,
      );

      expect(find.text('Android Autofill'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(find.textContaining('master password'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('settings-open-autofill')));
      await tester.pumpAndSettle();

      expect(openSettingsCalls, 1);
    },
  );

  testWidgets('cloud devices dialog displays sync device metadata', (
    tester,
  ) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      cloudDevices: const [
        SyncDevice(
          id: 'device-1',
          deviceName: 'Travel laptop',
          deviceType: 'desktop',
          platform: 'windows',
          clientVersion: '1.4.2',
          trusted: true,
          lastSyncAt: '2026-05-23T09:00:00Z',
          lastIpAddress: '203.0.113.10',
          lastUserAgent: 'Lockly/1.4.2 Windows',
          createdAt: '2026-05-22T09:00:00Z',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsPage(services: services)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cloud devices'), 160);
    await tester.tap(find.text('Cloud devices'));
    await tester.pumpAndSettle();

    expect(find.text('Travel laptop'), findsOneWidget);
    expect(find.textContaining('windows'), findsOneWidget);
    expect(find.textContaining('1.4.2'), findsOneWidget);
    expect(find.textContaining('2026-05-23T09:00:00Z'), findsOneWidget);
    expect(find.textContaining('203.0.113.10'), findsOneWidget);
    expect(find.textContaining('Lockly/1.4.2 Windows'), findsOneWidget);
  });

  testWidgets('cloud devices dialog ignores blank sync device metadata', (
    tester,
  ) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      cloudDevices: const [
        SyncDevice(
          id: 'device-1',
          deviceName: 'Office desktop',
          deviceType: 'desktop',
          platform: '',
          clientVersion: '',
          trusted: true,
          lastSyncAt: '',
          lastIpAddress: '',
          lastUserAgent: '',
          createdAt: '2026-05-22T09:00:00Z',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsPage(services: services)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cloud devices'), 160);
    await tester.tap(find.text('Cloud devices'));
    await tester.pumpAndSettle();

    expect(find.text('Office desktop'), findsOneWidget);
    expect(find.text('desktop'), findsOneWidget);
    expect(find.textContaining('v |'), findsNothing);
    expect(find.textContaining('Last sync  |'), findsNothing);
    expect(find.textContaining('IP  |'), findsNothing);
  });

  testWidgets('vault shell uses side navigation on desktop width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('generator presents generated password in a result panel', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vault-shell-generator-tab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('generator-generate-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('generator-result-panel')),
      findsOneWidget,
    );
    expect(find.text('生成结果'), findsOneWidget);
  });
}
