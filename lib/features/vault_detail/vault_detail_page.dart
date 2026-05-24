import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/passkey_record.dart';
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
  bool _isExporting = false;
  String? _errorMessage;
  List<VaultBlobListItem> _attachments = [];
  bool _isLoadingAttachments = false;
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
      _loadAttachments();
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

  Future<void> _exportItem() async {
    widget.services.recordActivity();
    setState(() => _isExporting = true);
    try {
      final backupJson = await widget.services.exportEncryptedItemBackupJson(
        widget.itemId,
      );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _SingleItemExportDialog(
          services: widget.services,
          backupJson: backupJson,
        ),
      );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('导出失败，请稍后重试。')));
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
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
            onPressed: entry == null || _isLoading || _isExporting
                ? null
                : _exportItem,
            tooltip: '导出此密码',
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_outlined),
          ),
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
              if (entry.passkey != null) ...[
                const SizedBox(height: 16),
                _buildPasskeySection(context, entry.passkey!),
              ],
              const SizedBox(height: 16),
              _buildAttachmentsSection(context),
              if (_passwordHistory.isNotEmpty) ...[
                const SizedBox(height: 16),
                InkWell(
                  onTap: () =>
                      setState(() => _historyExpanded = !_historyExpanded),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '密码历史 (${_passwordHistory.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      AnimatedRotation(
                        turns: _historyExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_historyExpanded) ...[
                  const SizedBox(height: 8),
                  ..._passwordHistory.map(
                    (record) => _buildHistoryItem(record, context),
                  ),
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

  Future<void> _loadAttachments() async {
    setState(() => _isLoadingAttachments = true);
    try {
      final attachments = await widget.services.listVaultBlobs(widget.itemId);
      if (!mounted) return;
      setState(() {
        _attachments = attachments;
        _isLoadingAttachments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingAttachments = false);
    }
  }

  Widget _buildPasskeySection(BuildContext context, PasskeyRecord passkey) {
    final theme = Theme.of(context);
    final readiness = passkey.platformReady
        ? 'Platform API ready'
        : 'Platform API not enabled';

    return Semantics(
      label: 'Passkey',
      child: _DetailSection(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Icon(
                  Icons.key_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Passkey', style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          _DetailRow(label: 'RP ID', value: passkey.relyingPartyId),
          _DetailRow(label: 'Credential', value: passkey.credentialId),
          _DetailRow(label: 'User', value: _fallback(passkey.userHandle)),
          _DetailRow(label: 'Display', value: _fallback(passkey.displayName)),
          _DetailRow(
            label: 'Algorithm',
            value: _fallback(passkey.publicKeyAlgorithm),
          ),
          _DetailRow(label: 'Platform', value: _fallback(passkey.platform)),
          _DetailRow(label: 'Readiness', value: readiness),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Attachments',
      child: _DetailSection(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Icon(
                  Icons.attach_file_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Attachments', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (_isLoadingAttachments)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    key: const ValueKey('attachment-add-button'),
                    onPressed: _showAddAttachmentDialog,
                    tooltip: 'Add attachment',
                    icon: const Icon(Icons.add_rounded),
                  ),
              ],
            ),
          ),
          if (!_isLoadingAttachments && _attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'No attachments',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ..._attachments.map((attachment) {
              return _AttachmentRow(
                attachment: attachment,
                onOpen: () => _openAttachment(attachment.blobId),
                onDelete: () => _deleteAttachment(attachment.blobId),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showAddAttachmentDialog() async {
    widget.services.recordActivity();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _AddAttachmentDialog(
          onSave:
              ({required displayName, required mediaType, required content}) {
                return widget.services.addVaultBlob(
                  itemId: widget.itemId,
                  displayName: displayName,
                  mediaType: mediaType,
                  bytes: Uint8List.fromList(utf8.encode(content)),
                );
              },
        );
      },
    );

    if (saved == true && mounted) {
      await _loadAttachments();
    }
  }

  Future<void> _openAttachment(String blobId) async {
    widget.services.recordActivity();
    try {
      final blob = await widget.services.openVaultBlob(blobId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          final text = utf8.decode(blob.bytes, allowMalformed: true);
          return AlertDialog(
            title: Text(blob.displayName),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DialogMetadataRow(
                      label: 'Media type',
                      value: blob.mediaType,
                    ),
                    _DialogMetadataRow(
                      label: 'Size',
                      value: _formatAttachmentSize(blob.bytes.length),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(text),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attachment open failed')));
    }
  }

  Future<void> _deleteAttachment(String blobId) async {
    widget.services.recordActivity();
    try {
      await widget.services.deleteVaultBlob(blobId);
      if (!mounted) return;
      await _loadAttachments();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attachment delete failed')));
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
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
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
                  isRevealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
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
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isRestoring = true);
              try {
                await widget.services.restorePassword(
                  widget.itemId,
                  record['id'] as int,
                );
                if (!mounted) return;
                await _loadItem();
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('密码已恢复')));
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('恢复失败')));
              } finally {
                if (mounted) setState(() => _isRestoring = false);
              }
            },
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
  }
}

class _SingleItemExportDialog extends StatefulWidget {
  const _SingleItemExportDialog({
    required this.services,
    required this.backupJson,
  });

  final AppServices services;
  final String backupJson;

  @override
  State<_SingleItemExportDialog> createState() =>
      _SingleItemExportDialogState();
}

class _SingleItemExportDialogState extends State<_SingleItemExportDialog> {
  bool _copied = false;

  Future<void> _copyBackupJson() async {
    final copied = await widget.services.copySensitiveTemporary(
      widget.backupJson,
      clearAfter: const Duration(seconds: 30),
    );
    if (!mounted) {
      return;
    }
    setState(() => _copied = copied);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(copied ? '单条加密备份已复制，30 秒后将自动清理剪贴板。' : '复制失败，请重试。'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(Icons.ios_share_outlined, color: theme.colorScheme.primary),
      title: const Text('导出单个密码'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '导出内容已加密，仅包含当前记录。导入时需要此备份对应的主密码，导入后会使用本地密钥重新加密保存。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    widget.backupJson,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: _copyBackupJson,
          icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
          label: Text(_copied ? '已复制' : '复制备份'),
        ),
      ],
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

String _formatAttachmentSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kib = bytes / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(kib >= 10 ? 0 : 1)} KB';
  }
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib >= 10 ? 0 : 1)} MB';
}

class _AddAttachmentDialog extends StatefulWidget {
  const _AddAttachmentDialog({required this.onSave});

  final Future<void> Function({
    required String displayName,
    required String mediaType,
    required String content,
  })
  onSave;

  @override
  State<_AddAttachmentDialog> createState() => _AddAttachmentDialogState();
}

class _AddAttachmentDialogState extends State<_AddAttachmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mediaTypeController = TextEditingController(text: 'text/plain');
  final _contentController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.clear();
    _mediaTypeController.clear();
    _contentController.clear();
    _nameController.dispose();
    _mediaTypeController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final mediaType = _mediaTypeController.text.trim().isEmpty
          ? 'text/plain'
          : _mediaTypeController.text.trim();
      await widget.onSave(
        displayName: _nameController.text.trim(),
        mediaType: mediaType,
        content: _contentController.text,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attachment add failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add attachment'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('attachment-name-input'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Display name'),
                textInputAction: TextInputAction.next,
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Display name is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('attachment-media-type-input'),
                controller: _mediaTypeController,
                decoration: const InputDecoration(labelText: 'Media type'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('attachment-content-input'),
                controller: _contentController,
                decoration: const InputDecoration(labelText: 'Content'),
                minLines: 3,
                maxLines: 6,
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Content is required'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('attachment-save-button'),
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _DialogMetadataRow extends StatelessWidget {
  const _DialogMetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.onOpen,
    required this.onDelete,
  });

  final VaultBlobListItem attachment;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 22,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.displayName,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatAttachmentSize(attachment.sizeBytes),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('attachment-open-${attachment.blobId}'),
            onPressed: onOpen,
            tooltip: 'Open attachment',
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          IconButton(
            key: ValueKey('attachment-delete-${attachment.blobId}'),
            onPressed: onDelete,
            tooltip: 'Delete attachment',
            icon: const Icon(Icons.delete_outline_rounded),
          ),
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
