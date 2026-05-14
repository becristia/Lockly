import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/features/setup/setup_page.dart';
import 'package:secure_box/features/unlock/unlock_page.dart';
import 'package:secure_box/features/vault_list/vault_list_page.dart';
import 'package:secure_box/shared/theme/app_theme.dart';
import 'package:secure_box/shared/widgets/secure_scaffold.dart';

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activityFocusNode.dispose();
    _privacyCoverVisible.dispose();
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Box',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
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
        return Focus(
          focusNode: _activityFocusNode,
          autofocus: true,
          onFocusChange: (hasFocus) => widget.services.recordActivity(),
          onKeyEvent: (node, event) {
            widget.services.recordActivity();
            return KeyEventResult.ignored;
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => widget.services.recordActivity(),
            onPointerSignal: (_) => widget.services.recordActivity(),
            child: ValueListenableBuilder<bool>(
              valueListenable: _privacyCoverVisible,
              builder: (context, coverVisible, _) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    child ?? const SizedBox.shrink(),
                    if (coverVisible) const _PrivacyCover(),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageForRoute(String routeName) {
    return switch (routeName) {
      AppServices.routeSetup => SetupPage(services: widget.services),
      AppServices.routeVault => VaultListPage(services: widget.services),
      AppServices.routeGenerator => const _GeneratorPlaceholderPage(),
      AppServices.routeSettings => const _SettingsPlaceholderPage(),
      _ => UnlockPage(services: widget.services),
    };
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('Secure Box', style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _GeneratorPlaceholderPage extends StatelessWidget {
  const _GeneratorPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return const SecureScaffold(
      title: '密码生成器',
      subtitle: '此页面的路由已预留，后续任务会补齐生成规则与保存流程。',
      body: SizedBox.shrink(),
    );
  }
}

class _SettingsPlaceholderPage extends StatelessWidget {
  const _SettingsPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return const SecureScaffold(
      title: '设置',
      subtitle: '这里将承载主密码修改、生物识别、自动锁定和备份设置。',
      body: SizedBox.shrink(),
    );
  }
}
