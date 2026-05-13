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

class _SecureBoxAppState extends State<SecureBoxApp> {
  final FocusNode _activityFocusNode = FocusNode(debugLabel: 'app-activity');

  @override
  void initState() {
    super.initState();
    widget.services.recordActivity();
  }

  @override
  void dispose() {
    _activityFocusNode.dispose();
    widget.services.dispose();
    super.dispose();
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
            child: child ?? const SizedBox.shrink(),
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
