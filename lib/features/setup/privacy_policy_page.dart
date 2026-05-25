import 'package:flutter/material.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('privacyPolicy')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SecureVisualBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('privacyTermsTitle'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.text('privacyTermsIntro'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('privacySectionService'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.text('privacySectionServiceBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('privacySectionStorage'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.text('privacySectionStorageBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('privacySectionUserDuty'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.text('privacySectionUserDutyBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('privacySectionDisclaimer'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.text('privacySectionDisclaimerBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('privacySectionTermsUpdate'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.text('privacySectionTermsUpdateBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              Text(
                strings.text('privacyPolicyTitle'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.text('privacyPolicyIntro'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('privacySectionCollect'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.text('privacySectionCollectBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('privacySectionUse'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.text('privacySectionUseBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('privacySectionSecurity'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.text('privacySectionSecurityBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('privacySectionThirdParty'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.text('privacySectionThirdPartyBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('privacySectionRights'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.text('privacySectionRightsBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('privacySectionPolicyUpdate'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.text('privacySectionPolicyUpdateBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
