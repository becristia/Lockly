import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/features/password_generator/password_generator_page.dart';
import 'package:secure_box/features/settings/settings_page.dart';
import 'package:secure_box/features/vault_list/vault_list_page.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class VaultShellPage extends StatefulWidget {
  const VaultShellPage({super.key, required this.services});

  final AppServices services;

  @override
  State<VaultShellPage> createState() => _VaultShellPageState();
}

class _VaultShellPageState extends State<VaultShellPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: switch (_selectedIndex) {
        0 => VaultListPage(services: widget.services),
        1 => PasswordGeneratorPage(services: widget.services),
        _ => SettingsPage(services: widget.services),
      },
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SecureGlassCard(
          padding: EdgeInsets.zero,
          borderRadius: 28,
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              widget.services.recordActivity();
              setState(() => _selectedIndex = index);
            },
            destinations: const [
              NavigationDestination(
                key: ValueKey('vault-shell-vault-tab'),
                icon: Icon(Icons.lock_outline_rounded),
                selectedIcon: Icon(Icons.lock_rounded),
                label: '密码库',
              ),
              NavigationDestination(
                key: ValueKey('vault-shell-generator-tab'),
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome_rounded),
                label: '生成器',
              ),
              NavigationDestination(
                key: ValueKey('vault-shell-settings-tab'),
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
