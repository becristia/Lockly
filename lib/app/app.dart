import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
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
      AppServices.routeSetup => const _SetupPlaceholderPage(),
      AppServices.routeVault => const _VaultPlaceholderPage(),
      AppServices.routeGenerator => const _GeneratorPlaceholderPage(),
      AppServices.routeSettings => const _SettingsPlaceholderPage(),
      _ => const _UnlockPlaceholderPage(),
    };
  }
}

class _SetupPlaceholderPage extends StatelessWidget {
  const _SetupPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return SecureScaffold(
      title: '创建主密码',
      subtitle: '主密码仅保存在本地，无法找回，请务必牢记。',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            obscureText: true,
            decoration: const InputDecoration(labelText: '主密码'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            obscureText: true,
            decoration: const InputDecoration(labelText: '确认主密码'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () {}, child: const Text('创建密码库')),
          ),
        ],
      ),
      footer: const Text('后续版本会在此接入完整校验、创建流程和生物识别开关。'),
    );
  }
}

class _UnlockPlaceholderPage extends StatelessWidget {
  const _UnlockPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return SecureScaffold(
      title: '解锁密码库',
      subtitle: '输入主密码以解锁本地加密密码库。',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            obscureText: true,
            decoration: const InputDecoration(labelText: '主密码'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () {}, child: const Text('解锁')),
          ),
        ],
      ),
      footer: const Text('Task 11 将在这里接入真实解锁和错误反馈。'),
    );
  }
}

class _VaultPlaceholderPage extends StatelessWidget {
  const _VaultPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return const SecureScaffold(
      title: '密码库',
      subtitle: '已完成壳层接线，后续页面会在此展开。',
      body: SizedBox.shrink(),
    );
  }
}

class _GeneratorPlaceholderPage extends StatelessWidget {
  const _GeneratorPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return const SecureScaffold(
      title: '密码生成器',
      subtitle: '路由已预留，Task 13 会补全生成规则与保存流程。',
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
