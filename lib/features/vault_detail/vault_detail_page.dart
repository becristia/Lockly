import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/features/vault_edit/vault_edit_page.dart';

class VaultDetailPage extends StatefulWidget {
  const VaultDetailPage({
    super.key,
    required this.services,
    required this.itemId,
  });

  final AppServices services;
  final String itemId;

  @override
  State<VaultDetailPage> createState() => _VaultDetailPageState();
}

class _VaultDetailPageState extends State<VaultDetailPage> {
  PasswordEntry? _entry;
  bool _isLoading = true;
  bool _isPasswordVisible = false;
  bool _isDeleting = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _passwordHistory = [];
  bool _historyExpanded = false;
  final Set<int> _revealedHistoryIds = {};
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _loadItem();
  }

  @override
  void dispose() {
    _entry = null;
    _isPasswordVisible = false;
    super.dispose();
  }

  Future<void> _loadItem() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final entry = await widget.services.getVaultItem(widget.itemId);
      if (!mounted) {
        return;
      }
      setState(() {
        _entry = entry;
        _isLoading = false;
      });
      _loadHistory();
    } on VaultItemNotFoundException {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = '这条记录不存在或已删除。';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = '暂时无法读取详情，请重试。';
      });
    }
  }

  Future<void> _openEdit() async {
    widget.services.recordActivity();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) =>
            VaultEditPage(services: widget.services, itemId: widget.itemId),
      ),
    );
    if (saved == true && mounted) {
      await _loadItem();
    }
  }

  Future<void> _copyValue({
    required Future<bool> Function() action,
    required String successMessage,
  }) async {
    widget.services.recordActivity();
    final messenger = ScaffoldMessenger.of(context);
    final copied = await action();
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(copied ? successMessage : '复制失败，请重试。')),
    );
  }

  Future<void> _confirmDelete() async {
    widget.services.recordActivity();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除记录'),
          content: const Text('删除后此条记录将无法在列表中显示。确认删除？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await widget.services.deleteVaultItem(widget.itemId);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on VaultItemNotFoundException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这条记录不存在或已删除。')));
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;

    return Scaffold(
      appBar: AppBar(
        title: Text(entry?.title ?? '密码详情'),
        actions: [
          IconButton(
            onPressed: entry == null || _isLoading ? null : _openEdit,
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              _DetailMessage(
                title: '无法显示详情',
                message: _errorMessage!,
                actionLabel: '重试',
                onAction: _loadItem,
              )
            else if (entry != null) ...[
              _DetailSection(
                children: [
                  _DetailRow(label: '标题', value: entry.title),
                  _DetailRow(label: '网址', value: _fallback(entry.website)),
                  _DetailRow(
                    label: '用户名',
                    value: _fallback(entry.username),
                    trailing: IconButton(
                      onPressed: entry.username.isEmpty
                          ? null
                          : () => _copyValue(
                              action: () =>
                                  widget.services.copyUsername(entry.username),
                              successMessage: '用户名已复制。',
                            ),
                      tooltip: '复制用户名',
                      icon: const Icon(Icons.content_copy_outlined),
                    ),
                  ),
                  _DetailRow(
                    label: '密码',
                    value: _isPasswordVisible ? entry.password : '已隐藏',
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          onPressed: () {
                            widget.services.recordActivity();
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                          tooltip: _isPasswordVisible ? '隐藏密码' : '显示密码',
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _copyValue(
                            action: () =>
                                widget.services.copyPassword(entry.password),
                            successMessage: '密码已复制，30 秒后将自动清理剪贴板。',
                          ),
                          tooltip: '复制密码',
                          icon: const Icon(Icons.content_copy_outlined),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_passwordHistory.isNotEmpty) ...[
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => setState(() => _historyExpanded = !_historyExpanded),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('密码历史 (${_passwordHistory.length})', style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      AnimatedRotation(
                        turns: _historyExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.chevron_right_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                if (_historyExpanded) ...[
                  const SizedBox(height: 8),
                  ..._passwordHistory.map((record) => _buildHistoryItem(record, context)),
                ],
              ],
              const SizedBox(height: 16),
              _DetailSection(
                children: [
                  _DetailRow(label: '备注', value: _fallback(entry.notes)),
                  _DetailRow(
                    label: '标签',
                    value: entry.tags.isEmpty ? '未填写' : entry.tags.join('、'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: _isDeleting ? null : _confirmDelete,
                icon: _isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded),
                label: const Text('删除'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fallback(String value) {
    if (value.trim().isEmpty) {
      return '未填写';
    }
    return value;
  }

  Future<void> _loadHistory() async {
    try {
      final history = await widget.services.listPasswordHistory(widget.itemId);
      if (!mounted) return;
      setState(() => _passwordHistory = history);
    } catch (_) {
      // History is optional; silently fail
    }
  }

  Widget _buildHistoryItem(Map<String, dynamic> record, BuildContext context) {
    final id = record['id'] as int;
    final password = record['password'] as String;
    final recordedAt = record['recordedAt'] as int;
    final isRevealed = _revealedHistoryIds.contains(id);
    final dateStr = _formatRelativeTime(recordedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(dateStr, style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              TextButton.icon(
                onPressed: _isRestoring ? null : () => _confirmRestore(record),
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: const Text('恢复', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  isRevealed ? password : '••••••••',
                  style: TextStyle(
                    fontFamily: isRevealed ? 'monospace' : null,
                    fontSize: isRevealed ? 14 : 16,
                    letterSpacing: isRevealed ? 0 : 2,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  isRevealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18,
                ),
                onPressed: () {
                  setState(() {
                    if (isRevealed) {
                      _revealedHistoryIds.remove(id);
                    } else {
                      _revealedHistoryIds.add(id);
                    }
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(int timestampMs) {
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestampMs));
    if (diff.inDays > 0) return '${diff.inDays} 天前';
    if (diff.inHours > 0) return '${diff.inHours} 小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes} 分钟前';
    return '刚刚';
  }

  void _confirmRestore(Map<String, dynamic> record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复密码'),
        content: const Text('将当前密码归档到历史记录，并用此密码替换。确认恢复？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () async {
            Navigator.pop(ctx);
            setState(() => _isRestoring = true);
            try {
              await widget.services.restorePassword(widget.itemId, record['id'] as int);
              if (!mounted) return;
              await _loadItem();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('密码已恢复')),
              );
            } catch (_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('恢复失败')),
              );
            } finally {
              if (mounted) setState(() => _isRestoring = false);
            }
          }, child: const Text('确认恢复')),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(value, style: theme.textTheme.bodyLarge),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({
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
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(
            Icons.lock_person_outlined,
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
