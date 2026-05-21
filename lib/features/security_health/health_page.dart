import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/security/password_health_service.dart';
import 'package:secure_box/features/vault_edit/vault_edit_page.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key, required this.services});

  final AppServices services;

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  HealthReport? _report;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final report = await widget.services.analyzePasswordHealth();
      if (!mounted) return;
      setState(() {
        _report = report;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '分析失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return SecureVisualBackground(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: Column(
        children: [
          SecureReplicaHeader(
            title: '密码健康',
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? _ErrorState(message: _errorMessage!, onRetry: _analyze)
                : report == null || report.findings.isEmpty
                ? const _HealthyState()
                : RefreshIndicator(
                    onRefresh: _analyze,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 104),
                      children: [
                        _ScoreCard(report: report),
                        const SizedBox(height: 14),
                        _StatsCard(report: report),
                        const SizedBox(height: 18),
                        _CategoryList(
                          report: report,
                          services: widget.services,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.report});

  final HealthReport report;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A70FF), Color(0xFF27D6E6)],
          ),
          boxShadow: [
            BoxShadow(
              color: SecureVisualColors.blue.withValues(alpha: 0.26),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: 22,
              top: 30,
              child: Icon(
                Icons.verified_user_rounded,
                size: 112,
                color: Colors.white.withValues(alpha: 0.34),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '密码健康分',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${report.score}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 74,
                      height: 0.96,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '共 ${report.totalItems} 条记录',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.report});

  final HealthReport report;

  @override
  Widget build(BuildContext context) {
    final highRisk =
        (report.categoryCounts[HealthCategory.weak] ?? 0) +
        (report.categoryCounts[HealthCategory.reused] ?? 0);
    final warnings =
        (report.categoryCounts[HealthCategory.stale] ?? 0) +
        (report.categoryCounts[HealthCategory.similar] ?? 0);
    final healthy = report.totalItems - report.findings.length;

    return SecureGlassCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      borderRadius: 22,
      child: Row(
        children: [
          _StatItem(
            label: '高风险',
            count: highRisk,
            color: SecureVisualColors.danger,
          ),
          Container(width: 1, height: 42, color: SecureVisualColors.line),
          _StatItem(
            label: '提醒',
            count: warnings,
            color: SecureVisualColors.warning,
          ),
          Container(width: 1, height: 42, color: SecureVisualColors.line),
          _StatItem(
            label: '健康',
            count: healthy,
            color: SecureVisualColors.success,
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.86),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.report, required this.services});

  final HealthReport report;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final findingMap = <HealthCategory, List<HealthFinding>>{};
    for (final finding in report.findings) {
      for (final category in finding.categories) {
        findingMap.putIfAbsent(category, () => []).add(finding);
      }
    }

    final categories = [
      _CategorySpec(
        category: HealthCategory.weak,
        title: '弱密码',
        subtitle: '密码长度不足或字符类型单一',
        color: SecureVisualColors.danger,
        icon: Icons.gpp_bad_outlined,
      ),
      _CategorySpec(
        category: HealthCategory.reused,
        title: '重复密码',
        subtitle: '多个条目使用相同密码',
        color: SecureVisualColors.success,
        icon: Icons.copy_rounded,
      ),
      _CategorySpec(
        category: HealthCategory.stale,
        title: '过期密码',
        subtitle: '超过 365 天未更新',
        color: SecureVisualColors.warning,
        icon: Icons.history_rounded,
      ),
      _CategorySpec(
        category: HealthCategory.similar,
        title: '相似密码',
        subtitle: '密码包含标题或网站名',
        color: SecureVisualColors.blue,
        icon: Icons.groups_rounded,
      ),
      _CategorySpec(
        category: HealthCategory.neverEdited,
        title: '从未更新',
        subtitle: '创建后从未修改过密码',
        color: SecureVisualColors.muted,
        icon: Icons.update_rounded,
      ),
    ];

    return Column(
      children: [
        for (final spec in categories) ...[
          _CategoryTile(
            spec: spec,
            count: report.categoryCounts[spec.category] ?? 0,
            findings: findingMap[spec.category] ?? const [],
            services: services,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _CategorySpec {
  const _CategorySpec({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final HealthCategory category;
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
}

class _CategoryTile extends StatefulWidget {
  const _CategoryTile({
    required this.spec,
    required this.count,
    required this.findings,
    required this.services,
  });

  final _CategorySpec spec;
  final int count;
  final List<HealthFinding> findings;
  final AppServices services;

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.count > 0 ? widget.spec.color : SecureVisualColors.success;
    return SecureGlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 18,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(widget.spec.icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.spec.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: SecureVisualColors.text,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.spec.subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _CountPill(count: widget.count, color: color),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? -0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _FindingList(
              findings: widget.findings,
              services: widget.services,
            ),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 42),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FindingList extends StatelessWidget {
  const _FindingList({required this.findings, required this.services});

  final List<HealthFinding> findings;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    if (findings.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          for (final finding in findings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _FindingItem(finding: finding, services: services),
            ),
        ],
      ),
    );
  }
}

class _FindingItem extends StatelessWidget {
  const _FindingItem({required this.finding, required this.services});

  final HealthFinding finding;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SecureVisualColors.softSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SecureVisualColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              finding.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: SecureVisualColors.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (finding.username.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(finding.username, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Text(finding.detail, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => VaultEditPage(
                        services: services,
                        itemId: finding.itemId,
                      ),
                    ),
                  );
                },
                child: const Text('修改密码'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthyState extends StatelessWidget {
  const _HealthyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SecureGlassCard(
        borderRadius: 26,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SecureIconBadge(
              icon: Icons.verified_user_rounded,
              color: SecureVisualColors.success,
            ),
            const SizedBox(height: 16),
            Text('密码库很健康', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('没有发现安全风险', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SecureGlassCard(
        borderRadius: 24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
