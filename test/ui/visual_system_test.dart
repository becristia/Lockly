import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/features/settings/settings_page.dart';
import 'package:secure_box/shared/theme/app_theme.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

void main() {
  test('app theme provides calm security ops tokens', () {
    final theme = AppTheme.light();
    final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
    final radius = shape.borderRadius as BorderRadius;

    expect(theme.scaffoldBackgroundColor, const Color(0xFFF6F7F9));
    expect(theme.colorScheme.primary, const Color(0xFF0369A1));
    expect(theme.colorScheme.secondary, const Color(0xFF0F766E));
    expect(theme.colorScheme.tertiary, const Color(0xFF15803D));
    expect(theme.colorScheme.error, const Color(0xFFB42318));
    expect(radius.topLeft.x, 12);
  });

  testWidgets('shared visual text follows dark theme surface contrast', (
    tester,
  ) async {
    final darkTheme = AppTheme.dark();

    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: const Scaffold(
          body: SecureGlassCard(
            child: Column(
              children: [
                SecureSectionTitle(title: 'Dark section'),
                SecureMetricCard(
                  icon: Icons.lock_rounded,
                  label: 'Records',
                  value: '12',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final sectionText = tester.widget<Text>(find.text('Dark section'));
    final metricText = tester.widget<Text>(find.text('12'));

    expect(sectionText.style?.color, darkTheme.colorScheme.onSurface);
    expect(metricText.style?.color, darkTheme.colorScheme.onSurface);
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
    expect(
      find.byKey(const ValueKey('settings-section-autofill')),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-cloud-download')),
      160,
    );
    expect(
      find.byKey(const ValueKey('settings-cloud-download')),
      findsOneWidget,
    );
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
      cloudAccountEmailOverride: () async => 'sync@example.test',
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-cloud-sync-now')),
      160,
    );
    await tester.tap(find.byKey(const ValueKey('settings-cloud-sync-now')));
    await tester.pumpAndSettle();

    expect(syncCalled, isFalse);
    expect(find.text('同步加密密码库'), findsNWidgets(2));
    expect(find.byType(TextFormField), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'local-master');
    await tester.tap(find.text('同步'));
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
      cloudAccountEmailOverride: () async => 'sync@example.test',
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-cloud-download')),
      160,
    );
    await tester.tap(find.byKey(const ValueKey('settings-cloud-download')));
    await tester.pumpAndSettle();

    expect(downloadCalled, isFalse);
    expect(find.text('下载云端密码库'), findsWidgets);

    await tester.enterText(find.byType(TextFormField), 'local-master');
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();

    expect(downloadCalled, isTrue);
    expect(submittedPassword, 'local-master');
  });

  testWidgets('settings hides Android Autofill while feature is disabled', (
    tester,
  ) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsPage(services: services)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-section-autofill')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('settings-open-autofill')), findsNothing);
  });

  testWidgets('cloud devices dialog displays sync device metadata', (
    tester,
  ) async {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      cloudAccountEmail: 'sync@example.test',
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-cloud-devices')),
      160,
    );
    await tester.tap(find.byKey(const ValueKey('settings-cloud-devices')));
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
      cloudAccountEmail: 'sync@example.test',
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-cloud-devices')),
      160,
    );
    await tester.tap(find.byKey(const ValueKey('settings-cloud-devices')));
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
