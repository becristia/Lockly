import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/features/settings/settings_page.dart';
import 'package:secure_box/shared/i18n/app_language.dart';
import 'package:secure_box/shared/theme/app_theme.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

void main() {
  test('app theme provides brighter security ops tokens and dialogs', () {
    final theme = AppTheme.light();
    final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
    final radius = shape.borderRadius as BorderRadius;
    final dialogShape = theme.dialogTheme.shape! as RoundedRectangleBorder;
    final dialogRadius = dialogShape.borderRadius as BorderRadius;

    expect(theme.scaffoldBackgroundColor, const Color(0xFFFCFEFF));
    expect(theme.colorScheme.primary, const Color(0xFF0284C7));
    expect(theme.colorScheme.secondary, const Color(0xFF06B6D4));
    expect(theme.colorScheme.tertiary, const Color(0xFF16A34A));
    expect(theme.colorScheme.error, const Color(0xFFDC2626));
    expect(theme.colorScheme.surfaceContainerHighest, const Color(0xFFF0F9FF));
    expect(SecureVisualColors.softSurface, const Color(0xFFFCFEFF));
    expect(SecureVisualColors.paleBlue, const Color(0xFFF0F9FF));
    expect(radius.topLeft.x, 12);
    expect(dialogRadius.topLeft.x, 20);
    expect(dialogShape.side.color, theme.colorScheme.outlineVariant);
    expect(
      theme.dialogTheme.titleTextStyle?.color,
      theme.colorScheme.onSurface,
    );
    expect(
      theme.dialogTheme.contentTextStyle?.color,
      theme.colorScheme.onSurface,
    );
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
      find.byKey(const ValueKey('settings-section-lan-sync')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-section-autofill')),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-lan-send')),
      160,
    );
    expect(find.byKey(const ValueKey('settings-lan-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-lan-receive')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-section-danger')),
      160,
    );
    expect(
      find.byKey(const ValueKey('settings-section-danger')),
      findsOneWidget,
    );
  });

  testWidgets('settings cards and segmented controls stretch consistently', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SettingsPage(services: services)),
      ),
    );
    await tester.pumpAndSettle();

    final scrollWidth = tester
        .getSize(find.byType(SingleChildScrollView))
        .width;
    final languageButtonWidth = tester
        .getSize(find.byType(SegmentedButton<AppLanguage>))
        .width;
    final themeButtonWidth = tester
        .getSize(find.byType(SegmentedButton<ThemeMode>))
        .width;

    expect(languageButtonWidth, greaterThanOrEqualTo(scrollWidth * 0.90));
    expect(themeButtonWidth, greaterThanOrEqualTo(scrollWidth * 0.90));
  });

  testWidgets('settings leaves vertical spacing before LAN exchange section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = AppServices.fake(hasVault: true, unlocked: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SettingsPage(services: services)),
      ),
    );
    await tester.pumpAndSettle();

    final tagsBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('settings-section-tags')))
        .dy;
    final lanTop = tester
        .getTopLeft(find.byKey(const ValueKey('settings-section-lan-sync')))
        .dy;

    expect(lanTop - tagsBottom, greaterThanOrEqualTo(20));
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

  testWidgets('settings load failure shows retry state', (tester) async {
    var shouldFail = true;
    final services = AppServices(
      hasVault: true,
      initialShellState: AppShellState.unlocked,
      trackActivity: false,
      biometricEnabledOverride: () async {
        if (shouldFail) {
          throw StateError('settings unavailable');
        }
        return true;
      },
      autoLockTimeoutOverride: () async => const Duration(minutes: 5),
      clipboardCleanupTimeoutOverride: () async => const Duration(minutes: 1),
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SettingsPage(services: services)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-load-error')), findsOneWidget);
    expect(find.text('设置加载失败，请重试。'), findsOneWidget);

    shouldFail = false;
    await tester.tap(find.byKey(const ValueKey('settings-load-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-load-error')), findsNothing);
    expect(find.text('5 分钟'), findsOneWidget);
    expect(find.text('1 分钟'), findsOneWidget);
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
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations, hasLength(5));
    expect(find.text('安全中心'), findsOneWidget);
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
