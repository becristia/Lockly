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

  Widget _buildScoreCard(HealthReport report) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SecureVisualColors.blue, SecureVisualColors.cyan],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            '密码健康分',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${report.score}',
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            '共 ${report.totalItems} 条记录',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(HealthReport report) {
    final highRisk = (report.categoryCounts[HealthCategory.weak] ?? 0) +
        (report.categoryCounts[HealthCategory.reused] ?? 0);
    final warnings = (report.categoryCounts[HealthCategory.stale] ?? 0) +
        (report.categoryCounts[HealthCategory.similar] ?? 0);
    final healthy = report.totalItems - report.findings.length;

    return Row(
      children: [
        _buildStatItem('高风险', highRisk, SecureVisualColors.danger, context),
        const SizedBox(width: 12),
        _buildStatItem('提醒', warnings, const Color(0xFFF5A623), context),
        const SizedBox(width: 12),
        _buildStatItem('健康', healthy, SecureVisualColors.success, context),
      ],
    );
  }

  Widget _buildStatItem(
    String label,
    int count,
    Color color,
    BuildContext context,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white10
              : SecureVisualColors.paleBlue.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList(HealthReport report) {
    final categories = [
      (
        HealthCategory.weak,
        '弱密码',
        '密码长度不足或字符类型单一',
        SecureVisualColors.danger,
      ),
      (
        HealthCategory.reused,
        '重复密码',
        '多个条目使用相同密码',
        SecureVisualColors.danger,
      ),
      (
        HealthCategory.stale,
        '过期密码',
        '超过365天未更新',
        SecureVisualColors.success,
      ),
      (
        HealthCategory.similar,
        '相似密码',
        '密码包含标题或网站名',
        SecureVisualColors.success,
      ),
      (
        HealthCategory.neverEdited,
        '从未更新',
        '创建后从未修改过密码',
        SecureVisualColors.muted,
      ),
    ];

    final findingMap = <HealthCategory, List<HealthFinding>>{};
    for (final f in report.findings) {
      for (final c in f.categories) {
        findingMap.putIfAbsent(c, () => []).add(f);
      }
    }

    return SecureGlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < categories.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _CategoryTile(
              category: categories[i].$1,
              title: categories[i].$2,
              subtitle: categories[i].$3,
              color: categories[i].$4,
              count: report.categoryCounts[categories[i].$1] ?? 0,
              findings: findingMap[categories[i].$1] ?? [],
              services: widget.services,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _analyze,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.verified_user_rounded,
            size: 64,
            color: SecureVisualColors.success,
          ),
          const SizedBox(height: 12),
          Text(
            '密码库很健康',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '没有发现安全风险',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('密码健康')),
      body: SecureVisualBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildError(context)
                : _report!.findings.isEmpty
                    ? _buildEmpty(context)
                    : RefreshIndicator(
                        onRefresh: () async => _analyze(),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                          children: [
                            _buildScoreCard(_report!),
                            const SizedBox(height: 16),
                            _buildStatRow(_report!),
                            const SizedBox(height: 20),
                            _buildCategoryList(_report!),
                          ],
                        ),
                      ),
      ),
    );
  }
}

class _CategoryTile extends StatefulWidget {
  const _CategoryTile({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.count,
    required this.findings,
    required this.services,
  });
  final HealthCategory category;
  final String title;
  final String subtitle;
  final Color color;
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
    final theme = Theme.of(context);
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.count > 0
                        ? widget.color
                        : SecureVisualColors.success,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (widget.count > 0
                            ? widget.color
                            : SecureVisualColors.success)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.count}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.count > 0
                          ? widget.color
                          : SecureVisualColors.success,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.chevron_right_rounded, size: 20),
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
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

class _FindingList extends StatelessWidget {
  const _FindingList({required this.findings, required this.services});
  final List<HealthFinding> findings;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 16, 12),
      child: Column(
        children: [
          for (final finding in findings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.05)
            : SecureVisualColors.paleBlue.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      finding.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (finding.username.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        finding.username,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            finding.detail,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
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
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('修改密码'),
            ),
          ),
        ],
      ),
    );
  }
}
