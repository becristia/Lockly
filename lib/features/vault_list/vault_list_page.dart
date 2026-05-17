import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/features/vault_detail/vault_detail_page.dart';
import 'package:secure_box/features/vault_edit/vault_edit_page.dart';
import 'package:secure_box/shared/widgets/secure_panel.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class VaultListPage extends StatefulWidget {
  const VaultListPage({super.key, required this.services});

  final AppServices services;

  @override
  State<VaultListPage> createState() => _VaultListPageState();
}

class _VaultListPageState extends State<VaultListPage> {
  final TextEditingController _searchController = TextEditingController();

  List<VaultListItem> _items = const <VaultListItem>[];
  bool _isLoading = true;
  String? _errorMessage;
  int _loadSequence = 0;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final requestId = ++_loadSequence;
    final query = _searchController.text;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await widget.services.listVaultItems(query: query);
      if (!mounted || requestId != _loadSequence) {
        return;
      }
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _loadSequence) {
        return;
      }
      setState(() {
        _items = const <VaultListItem>[];
        _isLoading = false;
        _errorMessage = '暂时无法读取密码列表，请重试。';
      });
    }
  }

  Future<void> _handleAdd() async {
    widget.services.recordActivity();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => VaultEditPage(services: widget.services),
      ),
    );
    if (saved == true && mounted) {
      await _loadItems();
    }
  }

  Future<void> _openDetail(VaultListItem item) async {
    widget.services.recordActivity();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) =>
            VaultDetailPage(services: widget.services, itemId: item.id),
      ),
    );
    if (changed == true && mounted) {
      await _loadItems();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return SecureVisualBackground(
      bottomInset: 84,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
          onPressed: _handleAdd,
          tooltip: '新增密码',
          backgroundColor: SecureVisualColors.blue,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add_rounded),
        ),
        body: RefreshIndicator(
          onRefresh: _loadItems,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
            children: [
              SecureReplicaHeader(
                title: '密码库',
              ),
              const SizedBox(height: 22),
              _SecuritySummary(itemCount: _items.length, isLoading: _isLoading),
              const SizedBox(height: 16),
              SecureGlassCard(
                padding: EdgeInsets.zero,
                shadow: false,
                child: TextField(
                  controller: _searchController,
                  onTap: widget.services.recordActivity,
                  onChanged: (_) {
                    widget.services.recordActivity();
                    _loadItems();
                  },
                  decoration: const InputDecoration(
                    labelText: '搜索',
                    hintText: '搜索记录',
                    prefixIcon: Icon(Icons.search_rounded),
                    suffixIcon: Icon(Icons.tune_rounded),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                hasQuery ? '搜索结果 ${_items.length} 条' : '最近使用',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                _ListMessage(
                  title: '读取失败',
                  message: _errorMessage!,
                  actionLabel: '重试',
                  onAction: _loadItems,
                )
              else if (_items.isEmpty)
                _ListMessage(
                  title: hasQuery ? '没有匹配结果' : '还没有保存的密码',
                  message: hasQuery ? '试试缩短关键词。' : '点击右下角按钮新增第一条记录。',
                )
              else
                SecureGlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final item in _items)
                        _VaultReplicaTile(
                          item: item,
                          onTap: () => _openDetail(item),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultReplicaTile extends StatelessWidget {
  const _VaultReplicaTile({required this.item, required this.onTap});

  final VaultListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SecureVisualColors.blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.mail_outline_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      item.username.isEmpty ? '未填写用户名' : item.username,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecuritySummary extends StatelessWidget {
  const _SecuritySummary({required this.itemCount, required this.isLoading});

  final int itemCount;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('vault-list-security-summary'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B66F6), Color(0xFF5BA7FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: SecureVisualColors.blue.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.enhanced_encryption_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本地密码库',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLoading ? '正在校验本地加密记录' : '$itemCount 条记录仅保存在本机',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              SecureStatusPill(
                icon: Icons.lock_rounded,
                label: '已加密',
                color: Colors.white,
              ),
              SecureStatusPill(
                icon: Icons.offline_bolt_outlined,
                label: '本地优先',
                color: Color(0xFFB9FFD0),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ListMessage extends StatelessWidget {
  const _ListMessage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 36,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
