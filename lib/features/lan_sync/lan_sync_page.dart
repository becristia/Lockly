import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_panel.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class LanSyncPage extends StatelessWidget {
  const LanSyncPage({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return SecureVisualBackground(
      child: ListView(
        children: [
          SecureReplicaHeader(title: strings.text('lanExchangeTitle')),
          const SizedBox(height: 18),
          Text(
            strings.text('lanExchangeSubtitle'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          SecurePanel(
            child: Column(
              children: [
                _LanActionTile(
                  icon: Icons.ios_share_rounded,
                  title: strings.text('lanSendData'),
                  subtitle: strings.text('lanSendDataSubtitle'),
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppServices.routeLanSend),
                ),
                const Divider(height: 24),
                _LanActionTile(
                  icon: Icons.qr_code_scanner_rounded,
                  title: strings.text('lanReceiveData'),
                  subtitle: strings.text('lanReceiveDataSubtitle'),
                  onTap: () => Navigator.of(
                    context,
                  ).pushNamed(AppServices.routeLanReceive),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanActionTile extends StatelessWidget {
  const _LanActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SecureIconTile(icon: icon),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
