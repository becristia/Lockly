import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key, required this.services});

  final AppServices services;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<VaultListItem> _items = const <VaultListItem>[];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await widget.services.listDeletedItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const <VaultListItem>[];
        _isLoading = false;
        _errorMessage = '暂时无法读取回收站，请重试。';
      });
    }
  }

  Future<void> _restoreItem(VaultListItem item) async {
    try {
      await widget.services.restoreItem(item.id);
      if (!mounted) return;
      setState(() {
        _items = _items.where((i) => i.id != item.id).toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('恢复失败，请重试。')));
    }
  }

  Future<bool> _confirmPermanentlyDelete(VaultListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('永久删除'),
        content: Text('确定要永久删除「${item.title}」吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: SecureVisualColors.danger,
            ),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return false;

    try {
      await widget.services.permanentlyDeleteItem(item.id);
      if (!mounted) return false;
      setState(() {
        _items = _items.where((i) => i.id != item.id).toList();
      });
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除失败，请重试。')));
      return false;
    }
  }

  Future<void> _emptyTrash() async {
    if (_items.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: Text('确定要永久删除回收站中的 ${_items.length} 条记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: SecureVisualColors.danger,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.services.emptyTrash();
      if (!mounted) return;
      setState(() {
        _items = const <VaultListItem>[];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('清空失败，请重试。')));
    }
  }

  String _relativeTime(int timestamp) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - timestamp;
    if (diff < 0) return '刚刚';

    final seconds = diff ~/ 1000;
    if (seconds < 60) return '刚刚';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分钟前';
    final hours = minutes ~/ 60;
    if (hours < 24) return '$hours 小时前';
    final days = hours ~/ 24;
    if (days < 30) return '$days 天前';
    final months = days ~/ 30;
    if (months < 12) return '$months 个月前';
    final years = days ~/ 365;
    return '$years 年前';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SecureVisualBackground(
      bottomInset: _items.isNotEmpty ? 72 : 0,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('回收站'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _buildErrorView(theme)
            : _items.isEmpty
            ? _buildEmptyView(theme)
            : _buildItemList(theme),
        bottomNavigationBar: _items.isNotEmpty
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _emptyTrash,
                      style: FilledButton.styleFrom(
                        backgroundColor: SecureVisualColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                      label: const Text('清空回收站'),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: SecureVisualColors.danger,
            ),
            const SizedBox(height: 16),
            Text('读取失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: _loadItems, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline_rounded,
              size: 64,
              color: SecureVisualColors.muted,
            ),
            const SizedBox(height: 16),
            Text('回收站为空', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '删除的密码记录会出现在这里。',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemList(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadItems,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${_items.length} 条已删除记录',
              style: theme.textTheme.titleMedium,
            ),
          ),
          SecureGlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _items.length; i++)
                  _TrashItemTile(
                    item: _items[i],
                    onRestore: () => _restoreItem(_items[i]),
                    onPermanentlyDelete: () =>
                        _confirmPermanentlyDelete(_items[i]),
                    relativeTime: _relativeTime(_items[i].deletedAt!),
                    showDivider: i < _items.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrashItemTile extends StatelessWidget {
  const _TrashItemTile({
    required this.item,
    required this.onRestore,
    required this.onPermanentlyDelete,
    required this.relativeTime,
    required this.showDivider,
  });

  final VaultListItem item;
  final VoidCallback onRestore;
  final Future<bool> Function() onPermanentlyDelete;
  final String relativeTime;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dismissible(
      key: Key('trash_item_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: SecureVisualColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.delete_forever_rounded,
          color: SecureVisualColors.danger,
          size: 28,
        ),
      ),
      confirmDismiss: (_) => onPermanentlyDelete(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: SecureVisualColors.muted.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: SecureVisualColors.muted,
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
                        item.username.isEmpty
                            ? '未填写用户名'
                            : '${item.username}  ·  $relativeTime',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _ActionChip(
                  label: '恢复',
                  icon: Icons.restore_rounded,
                  color: SecureVisualColors.blue,
                  onTap: onRestore,
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  label: '永久删除',
                  icon: Icons.delete_forever_rounded,
                  color: SecureVisualColors.danger,
                  onTap: () => onPermanentlyDelete(),
                ),
              ],
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              indent: 64,
              endIndent: 16,
              color: SecureVisualColors.line,
            ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
