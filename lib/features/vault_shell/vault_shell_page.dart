import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/features/password_generator/password_generator_page.dart';
import 'package:secure_box/features/security_center/security_center_page.dart';
import 'package:secure_box/features/settings/settings_page.dart';
import 'package:secure_box/features/totp/totp_page.dart';
import 'package:secure_box/features/vault_list/vault_list_page.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
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
    final strings = AppStrings.of(context);
    final isDesktopWidth = MediaQuery.sizeOf(context).width >= 900;
    final page = switch (_selectedIndex) {
      0 => VaultListPage(services: widget.services),
      1 => SecurityCenterPage(services: widget.services),
      2 => TotpPage(services: widget.services),
      3 => PasswordGeneratorPage(
        services: widget.services,
        onSavedToVault: () => setState(() => _selectedIndex = 0),
      ),
      _ => SettingsPage(services: widget.services),
    };

    if (isDesktopWidth) {
      return _withLockNowAction(
        Scaffold(
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
                      destinations: [
                        NavigationRailDestination(
                          icon: const Icon(Icons.lock_outline_rounded),
                          selectedIcon: const Icon(Icons.lock_rounded),
                          label: Text(strings.vaultTab),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.security_outlined),
                          selectedIcon: const Icon(Icons.security_rounded),
                          label: Text(strings.text('securityCenterTitle')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.qr_code_2_outlined),
                          selectedIcon: const Icon(Icons.qr_code_2_rounded),
                          label: Text(strings.totpTab),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.auto_awesome_outlined),
                          selectedIcon: const Icon(Icons.auto_awesome_rounded),
                          label: Text(strings.generatorTab),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.settings_outlined),
                          selectedIcon: const Icon(Icons.settings_rounded),
                          label: Text(strings.settingsTab),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: page),
            ],
          ),
        ),
      );
    }

    return _withLockNowAction(
      Scaffold(
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
              destinations: [
                NavigationDestination(
                  key: const ValueKey('vault-shell-vault-tab'),
                  icon: const Icon(Icons.lock_outline_rounded),
                  selectedIcon: const Icon(Icons.lock_rounded),
                  label: strings.vaultTab,
                ),
                NavigationDestination(
                  key: const ValueKey('vault-shell-security-tab'),
                  icon: const Icon(Icons.security_outlined),
                  selectedIcon: const Icon(Icons.security_rounded),
                  label: strings.text('securityCenterTitle'),
                ),
                NavigationDestination(
                  key: const ValueKey('vault-shell-totp-tab'),
                  icon: const Icon(Icons.qr_code_2_outlined),
                  selectedIcon: const Icon(Icons.qr_code_2_rounded),
                  label: strings.totpTab,
                ),
                NavigationDestination(
                  key: const ValueKey('vault-shell-generator-tab'),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  selectedIcon: const Icon(Icons.auto_awesome_rounded),
                  label: strings.generatorTab,
                ),
                NavigationDestination(
                  key: const ValueKey('vault-shell-settings-tab'),
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings_rounded),
                  label: strings.settingsTab,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _withLockNowAction(Widget child) {
    final strings = AppStrings.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        PositionedDirectional(
          top: 12,
          end: 16,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Tooltip(
                message: strings.text('lockNow'),
                child: IconButton.filledTonal(
                  key: const ValueKey('vault-shell-lock-now'),
                  onPressed: () {
                    widget.services.recordActivity();
                    widget.services.lockVault();
                  },
                  icon: const Icon(Icons.lock_rounded),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
