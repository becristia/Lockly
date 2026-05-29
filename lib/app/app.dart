import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/features/lan_sync/lan_receive_page.dart';
import 'package:secure_box/features/lan_sync/lan_send_page.dart';
import 'package:secure_box/features/lan_sync/lan_sync_page.dart';
import 'package:secure_box/features/password_generator/password_generator_page.dart';
import 'package:secure_box/features/settings/settings_page.dart';
import 'package:secure_box/features/setup/setup_page.dart';
import 'package:secure_box/features/unlock/unlock_page.dart';
import 'package:secure_box/features/vault_shell/vault_shell_page.dart';
import 'package:secure_box/shared/i18n/app_language.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/i18n/app_strings_en.dart';
import 'package:secure_box/shared/i18n/app_strings_scope.dart';
import 'package:secure_box/shared/i18n/app_strings_zh.dart';
import 'package:secure_box/shared/theme/app_theme.dart';
import 'package:secure_box/shared/widgets/windows_window_controls.dart';

class SecureBoxApp extends StatefulWidget {
  const SecureBoxApp({super.key, required this.services});

  final AppServices services;

  @override
  State<SecureBoxApp> createState() => _SecureBoxAppState();
}

class _SecureBoxAppState extends State<SecureBoxApp>
    with WidgetsBindingObserver {
  final FocusNode _activityFocusNode = FocusNode(debugLabel: 'app-activity');
  final ValueNotifier<bool> _privacyCoverVisible = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.services.recordActivity();
    widget.services.themeModeNotifier.addListener(_onThemeModeChanged);
    widget.services.languageNotifier.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activityFocusNode.dispose();
    _privacyCoverVisible.dispose();
    widget.services.themeModeNotifier.removeListener(_onThemeModeChanged);
    widget.services.languageNotifier.removeListener(_onLanguageChanged);
    widget.services.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _privacyCoverVisible.value = false;
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _privacyCoverVisible.value = true;
        return;
    }
  }

  void _onThemeModeChanged() {
    setState(() {});
  }

  void _onLanguageChanged() {
    setState(() {});
  }

  void _recordForegroundActivity() {
    _privacyCoverVisible.value = false;
    widget.services.recordActivity();
  }

  @override
  Widget build(BuildContext context) {
    final strings = _stringsFor(widget.services.language);
    return MaterialApp(
      title: strings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: widget.services.themeMode,
      navigatorKey: widget.services.navigatorKey,
      onGenerateInitialRoutes: (initialRouteName) => [
        MaterialPageRoute<void>(
          settings: RouteSettings(name: widget.services.currentRouteName),
          builder: (context) =>
              _buildPageForRoute(widget.services.currentRouteName),
        ),
      ],
      onGenerateRoute: (settings) {
        final routeName = widget.services.resolveRouteName(settings.name);
        return MaterialPageRoute<void>(
          settings: RouteSettings(name: routeName),
          builder: (context) => _buildPageForRoute(routeName),
        );
      },
      builder: (context, child) {
        return AppStringsScope(
          strings: strings,
          child: Focus(
            focusNode: _activityFocusNode,
            autofocus: true,
            onFocusChange: (hasFocus) {
              if (hasFocus) {
                _recordForegroundActivity();
              }
            },
            onKeyEvent: (node, event) {
              _recordForegroundActivity();
              return KeyEventResult.ignored;
            },
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _recordForegroundActivity(),
              onPointerSignal: (_) => _recordForegroundActivity(),
              child: ValueListenableBuilder<bool>(
                valueListenable: _privacyCoverVisible,
                builder: (context, coverVisible, _) {
                  return WindowsWindowFrame(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        child ?? const SizedBox.shrink(),
                        if (coverVisible) const _PrivacyCover(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageForRoute(String routeName) {
    return switch (routeName) {
      AppServices.routeSetup => SetupPage(services: widget.services),
      AppServices.routeVault => VaultShellPage(services: widget.services),
      AppServices.routeGenerator => PasswordGeneratorPage(
        services: widget.services,
      ),
      AppServices.routeSettings => SettingsPage(services: widget.services),
      AppServices.routeLanSync => LanSyncPage(services: widget.services),
      AppServices.routeLanSend => LanSendPage(services: widget.services),
      AppServices.routeLanReceive => LanReceivePage(services: widget.services),
      _ => UnlockPage(services: widget.services),
    };
  }

  AppStrings _stringsFor(AppLanguage language) {
    return switch (language) {
      AppLanguage.zh => const AppStringsZh(),
      AppLanguage.en => const AppStringsEn(),
    };
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 80,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(strings.appName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              strings.privacyCoverMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
