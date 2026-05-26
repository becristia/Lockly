import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class SecurityCenterPage extends StatefulWidget {
  const SecurityCenterPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SecurityCenterPage> createState() => _SecurityCenterPageState();
}

class _SecurityCenterPageState extends State<SecurityCenterPage> {
  late Future<_SecurityCenterSnapshot> _snapshot;
  HealthReport? _healthReport;
  bool _healthLoading = false;
  Object? _healthError;

  @override
  void initState() {
    super.initState();
    _snapshot = _loadSnapshot();
  }

  Future<_SecurityCenterSnapshot> _loadSnapshot() async {
    return const _SecurityCenterSnapshot();
  }

  Future<void> _refresh() async {
    widget.services.recordActivity();
    setState(() {
      _snapshot = _loadSnapshot();
    });
    await _snapshot;
  }

  Future<void> _analyzeHealth() async {
    widget.services.recordActivity();
    setState(() {
      _healthLoading = true;
      _healthError = null;
    });
    try {
      final report = await widget.services.analyzePasswordHealth();
      if (!mounted) return;
      setState(() {
        _healthReport = report;
        _healthLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _healthLoading = false;
        _healthError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SecureVisualBackground(
      key: const ValueKey('security-center-page'),
      bottomInset: 84,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: FutureBuilder<_SecurityCenterSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              children: [
                SecureReplicaHeader(
                  title: strings.text('securityCenterTitle'),
                  subtitle: strings.text('securityCenterSubtitle'),
                  trailing: IconButton(
                    tooltip: strings.text('refresh'),
                    onPressed: snapshot.connectionState == ConnectionState.done
                        ? _refresh
                        : null,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
                const SizedBox(height: 18),
                if (data == null) ...[
                  const _LoadingCard(),
                ] else ...[
                  _PasswordHealthCard(
                    key: const ValueKey('security-center-health-card'),
                    report: _healthReport,
                    isLoading: _healthLoading,
                    error: _healthError,
                    onAnalyze: _analyzeHealth,
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 18),
                  _RoadmapGrid(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SecurityCenterSnapshot {
  const _SecurityCenterSnapshot();
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SecureGlassCard(
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 12),
          Text(strings.text('loadingSecurityPosture')),
        ],
      ),
    );
  }
}

class _PasswordHealthCard extends StatelessWidget {
  const _PasswordHealthCard({
    super.key,
    required this.report,
    required this.isLoading,
    required this.onAnalyze,
    this.error,
  });

  final HealthReport? report;
  final bool isLoading;
  final VoidCallback onAnalyze;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final report = this.report;
    if (isLoading) {
      return _StatusCard(
        icon: Icons.health_and_safety_outlined,
        title: strings.text('healthTitle'),
        headline: strings.text('checkingLocalVault'),
        detail: strings.text('checkingLocalVault'),
        tone: SecureVisualColors.blue,
        action: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    if (report == null) {
      return _StatusCard(
        icon: Icons.health_and_safety_outlined,
        title: strings.text('healthTitle'),
        headline: error == null
            ? strings.text('localCheckNotRun')
            : strings.text('localCheckFailed'),
        detail: error == null
            ? strings.text('localCheckNotRunDetail')
            : strings.text('localCheckFailedDetail'),
        tone: error == null
            ? SecureVisualColors.blue
            : SecureVisualColors.warning,
        action: OutlinedButton.icon(
          onPressed: onAnalyze,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(strings.text('runLocalCheck')),
        ),
      );
    }

    final weak = report.categoryCounts[HealthCategory.weak] ?? 0;
    final reused = report.categoryCounts[HealthCategory.reused] ?? 0;
    final stale = report.categoryCounts[HealthCategory.stale] ?? 0;
    final headline = '${report.score}/100 ${strings.text('healthScoreSuffix')}';
    final detail = report.findings.isEmpty
        ? '${report.totalItems} ${strings.text('savedItemsCheckedLocally')}'
        : '$weak ${strings.text('weakCountLabel')}, $reused ${strings.text('reusedCountLabel')}, $stale ${strings.text('staleCountLabel')} ${strings.text('foundLocallySuffix')}';

    return _StatusCard(
      icon: Icons.health_and_safety_outlined,
      title: strings.text('healthTitle'),
      headline: headline,
      detail: detail,
      tone: report.score >= 80
          ? SecureVisualColors.success
          : SecureVisualColors.warning,
      action: TextButton.icon(
        onPressed: onAnalyze,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(strings.text('runAgain')),
      ),
    );
  }
}

class _RoadmapGrid extends StatelessWidget {
  const _RoadmapGrid();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final items = [
      _RoadmapItem(
        keyValue: 'security-center-migration',
        icon: Icons.move_up_rounded,
        title: strings.text('migration'),
        detail: strings.text('roadmapMigrationDetail'),
      ),
      _RoadmapItem(
        keyValue: 'security-center-attachments',
        icon: Icons.attach_file_rounded,
        title: strings.text('attachments'),
        detail: strings.text('roadmapAttachmentsDetail'),
      ),
      _RoadmapItem(
        keyValue: 'security-center-passkeys',
        icon: Icons.key_rounded,
        title: strings.text('passkeys'),
        detail: strings.text('roadmapPasskeysDetail'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          childAspectRatio: columns == 1 ? 4.2 : 3.8,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: items,
        );
      },
    );
  }
}

class _RoadmapItem extends StatelessWidget {
  const _RoadmapItem({
    required this.keyValue,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final String keyValue;
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SecureGlassCard(
      key: ValueKey(keyValue),
      borderRadius: 14,
      padding: const EdgeInsets.all(14),
      shadow: false,
      child: Row(
        children: [
          _IconTile(icon: icon, color: SecureVisualColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: SecureVisualColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: SecureVisualColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.headline,
    required this.detail,
    required this.tone,
    this.action,
  });

  final IconData icon;
  final String title;
  final String headline;
  final String detail;
  final Color tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = SecureGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      shadow: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: icon, color: tone),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: SecureVisualColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: SecureVisualColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: SecureVisualColors.text.withValues(alpha: 0.72),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: action!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return card;
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 23),
    );
  }
}
