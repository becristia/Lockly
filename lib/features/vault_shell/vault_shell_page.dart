import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/features/password_generator/password_generator_page.dart';
import 'package:secure_box/features/security_center/security_center_page.dart';
import 'package:secure_box/features/settings/settings_page.dart';
import 'package:secure_box/features/totp/totp_page.dart';
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
    final isDesktopWidth = MediaQuery.sizeOf(context).width >= 900;
    final page = switch (_selectedIndex) {
      0 => VaultListPage(services: widget.services),
      1 => SecurityCenterPage(services: widget.services),
      2 => TotpPage(services: widget.services),
      3 => PasswordGeneratorPage(services: widget.services),
      _ => SettingsPage(services: widget.services),
    };

    if (isDesktopWidth) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                child: SecureGlassCard(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  borderRadius: 16,
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) {
                      widget.services.recordActivity();
                      setState(() => _selectedIndex = index);
                    },
                    labelType: NavigationRailLabelType.all,
                    minWidth: 96,
                    groupAlignment: -0.92,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.lock_outline_rounded),
                        selectedIcon: Icon(Icons.lock_rounded),
                        label: Text('Vault'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(
                          Icons.security_outlined,
                          key: ValueKey('vault-shell-security-tab'),
                        ),
                        selectedIcon: Icon(Icons.security_rounded),
                        label: Text('Security'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.qr_code_2_outlined),
                        selectedIcon: Icon(Icons.qr_code_2_rounded),
                        label: Text('TOTP'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.auto_awesome_outlined),
                        selectedIcon: Icon(Icons.auto_awesome_rounded),
                        label: Text('Generator'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings_rounded),
                        label: Text('Settings'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: page),
          ],
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: page,
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
                label: 'Vault',
              ),
              NavigationDestination(
                key: ValueKey('vault-shell-security-tab'),
                icon: Icon(Icons.security_outlined),
                selectedIcon: Icon(Icons.security_rounded),
                label: 'Security',
              ),
              NavigationDestination(
                key: ValueKey('vault-shell-totp-tab'),
                icon: Icon(Icons.qr_code_2_outlined),
                selectedIcon: Icon(Icons.qr_code_2_rounded),
                label: 'TOTP',
              ),
              NavigationDestination(
                key: ValueKey('vault-shell-generator-tab'),
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome_rounded),
                label: 'Generator',
              ),
              NavigationDestination(
                key: ValueKey('vault-shell-settings-tab'),
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
