import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/features/vault_detail/vault_detail_page.dart';
import 'package:secure_box/features/vault_edit/vault_edit_page.dart';
import 'package:secure_box/shared/widgets/secure_panel.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('密码库')),
      floatingActionButton: FloatingActionButton(
        onPressed: _handleAdd,
        tooltip: '新增密码',
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadItems,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              _SecuritySummary(itemCount: _items.length, isLoading: _isLoading),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onTap: widget.services.recordActivity,
                onChanged: (_) {
                  widget.services.recordActivity();
                  _loadItems();
                },
                decoration: const InputDecoration(
                  labelText: '搜索',
                  hintText: '标题、网站、用户名、备注或标签',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                hasQuery ? '搜索结果 ${_items.length} 条' : '共 ${_items.length} 条记录',
                style: theme.textTheme.bodyMedium,
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
                ..._items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _openDetail(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.lock_outline_rounded,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.username.isEmpty
                                          ? '未填写用户名'
                                          : item.username,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    if (item.website.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.website,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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

    return SecurePanel(
      key: const ValueKey('vault-list-security-summary'),
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      borderColor: theme.colorScheme.primary.withValues(alpha: 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.enhanced_encryption_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('本地密码库', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      isLoading ? '正在校验本地加密记录' : '$itemCount 条记录仅保存在本机',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SecureStatusPill(
                icon: Icons.lock_rounded,
                label: '已加密',
                color: theme.colorScheme.primary,
              ),
              SecureStatusPill(
                icon: Icons.offline_bolt_outlined,
                label: '本地优先',
                color: theme.colorScheme.tertiary,
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
