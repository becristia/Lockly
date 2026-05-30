import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/passkey_record.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/features/vault_edit/vault_edit_page.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_dialog.dart';

const _maxAttachmentPreviewCharacters = 8000;

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
        _errorMessage = AppStrings.of(context).text('vaultItemMissing');
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = AppStrings.of(context).text('vaultDetailLoadFailed');
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
      SnackBar(
        content: Text(
          copied ? successMessage : AppStrings.of(context).copyFailed,
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    widget.services.recordActivity();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final strings = AppStrings.of(context);
        return SecureDialog(
          icon: Icons.delete_forever_rounded,
          title: strings.text('deleteRecord'),
          message: strings.text('deleteRecordMessage'),
          destructive: true,
          actions: [
            SecureDialogAction.destructive(
              label: strings.text('confirmDelete'),
              icon: Icons.delete_forever_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            SecureDialogAction.cancel(
              context,
              onPressed: () => Navigator.of(context).pop(false),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('vaultItemMissing')),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('deleteRecordFailed')),
        ),
      );
    }
  }

  Future<void> _exportItem() async {
    widget.services.recordActivity();
    final masterPassword = await _promptMasterPasswordForExport();
    if (masterPassword == null) {
      return;
    }
    setState(() => _isExporting = true);
    try {
      await widget.services.verifyMasterPassword(masterPassword);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('vaultItemMissing')),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('exportFailed'))),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<String?> _promptMasterPasswordForExport() {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscure = true;

    void submit(BuildContext context) {
      final form = formKey.currentState;
      if (form == null || !form.validate()) {
        return;
      }
      Navigator.of(context).pop(controller.text);
    }

    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final strings = AppStrings.of(context);
          return SecureDialog(
            icon: Icons.lock_outline_rounded,
            title: strings.text('exportSinglePassword'),
            actions: [
              SecureDialogAction.primary(
                label: strings.text('continue'),
                icon: Icons.arrow_forward_rounded,
                onPressed: () => submit(context),
              ),
              SecureDialogAction.cancel(context),
            ],
            child: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                obscureText: obscure,
                enableSuggestions: false,
                autocorrect: false,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: strings.text('masterPassword'),
                  helperText: strings.text('reauthenticateExportSubtitle'),
                  suffixIcon: IconButton(
                    tooltip: obscure
                        ? strings.text('showMasterPassword')
                        : strings.text('hideMasterPassword'),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? strings.text('requiredMasterPassword')
                    : null,
                onFieldSubmitted: (_) => submit(context),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      controller.clear();
      controller.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(entry?.title ?? strings.text('passwordDetail')),
        actions: [
          IconButton(
            onPressed: entry == null || _isLoading || _isExporting
                ? null
                : _exportItem,
            tooltip: strings.text('exportPassword'),
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
            tooltip: strings.text('edit'),
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
                title: strings.text('detailUnavailable'),
                message: _errorMessage!,
                actionLabel: strings.retry,
                onAction: _loadItem,
              )
            else if (entry != null) ...[
              _DetailSection(
                children: [
                  _DetailRow(
                    label: strings.text('titleField'),
                    value: entry.title,
                  ),
                  _DetailRow(
                    label: strings.text('websiteField'),
                    value: _fallback(entry.website),
                  ),
                  _DetailRow(
                    label: strings.text('usernameField'),
                    value: _fallback(entry.username),
                    trailing: IconButton(
                      onPressed: entry.username.isEmpty
                          ? null
                          : () => _copyValue(
                              action: () =>
                                  widget.services.copyUsername(entry.username),
                              successMessage: strings.text('usernameCopied'),
                            ),
                      tooltip: strings.text('copyUsername'),
                      icon: const Icon(Icons.content_copy_outlined),
                    ),
                  ),
                  _DetailRow(
                    label: strings.text('passwordField'),
                    value: _isPasswordVisible
                        ? entry.password
                        : strings.text('hidden'),
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
                          tooltip: _isPasswordVisible
                              ? strings.text('hidePassword')
                              : strings.text('showPassword'),
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
                            successMessage: strings.passwordCopied,
                          ),
                          tooltip: strings.copyPasswordTooltip,
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
                        '${strings.text('passwordHistory')} (${_passwordHistory.length})',
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
                  _DetailRow(
                    label: strings.text('notesField'),
                    value: _fallback(entry.notes),
                  ),
                  _DetailRow(
                    label: strings.text('tagsField'),
                    value: entry.tags.isEmpty
                        ? strings.text('notFilled')
                        : entry.tags.join(strings.text('listSeparator')),
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
                label: Text(strings.text('delete')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fallback(String value) {
    if (value.trim().isEmpty) {
      return AppStrings.of(context).text('notFilled');
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
    final strings = AppStrings.of(context);
    final readiness = passkey.platformReady
        ? strings.text('platformApiReady')
        : strings.text('platformApiNotEnabled');

    return Semantics(
      label: strings.text('passkeys'),
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
                Text(
                  strings.text('passkeys'),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
          _DetailRow(
            label: strings.text('rpId'),
            value: passkey.relyingPartyId,
          ),
          _DetailRow(
            label: strings.text('credential'),
            value: passkey.credentialId,
          ),
          _DetailRow(
            label: strings.text('user'),
            value: _fallback(passkey.userHandle),
          ),
          _DetailRow(
            label: strings.text('display'),
            value: _fallback(passkey.displayName),
          ),
          _DetailRow(
            label: strings.text('algorithm'),
            value: _fallback(passkey.publicKeyAlgorithm),
          ),
          _DetailRow(
            label: strings.text('platform'),
            value: _fallback(passkey.platform),
          ),
          _DetailRow(label: strings.text('readiness'), value: readiness),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return Semantics(
      label: strings.text('attachments'),
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
                Text(
                  strings.text('attachments'),
                  style: theme.textTheme.titleSmall,
                ),
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
                    tooltip: strings.text('addAttachment'),
                    icon: const Icon(Icons.add_rounded),
                  ),
              ],
            ),
          ),
          if (!_isLoadingAttachments && _attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                strings.text('noAttachments'),
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
                onDelete: () => _deleteAttachment(attachment),
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
      barrierDismissible: false,
      builder: (dialogContext) {
        return _AddAttachmentDialog(
          onSave:
              ({required displayName, required mediaType, required content}) {
                final bytes = Uint8List.fromList(utf8.encode(content));
                if (bytes.length > maxVaultBlobBytes) {
                  throw VaultBlobTooLargeException(bytes.length);
                }
                return widget.services.addVaultBlob(
                  itemId: widget.itemId,
                  displayName: displayName,
                  mediaType: mediaType,
                  bytes: bytes,
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
          final decoded = utf8.decode(blob.bytes, allowMalformed: true);
          final text = decoded.length > _maxAttachmentPreviewCharacters
              ? '${decoded.substring(0, _maxAttachmentPreviewCharacters)}\n...'
              : decoded;
          return SecureDialog(
            icon: Icons.insert_drive_file_outlined,
            title: blob.displayName,
            actions: [SecureDialogAction.close(context)],
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DialogMetadataRow(
                    label: AppStrings.of(context).text('mediaType'),
                    value: blob.mediaType,
                  ),
                  _DialogMetadataRow(
                    label: AppStrings.of(context).text('size'),
                    value: _formatAttachmentSize(blob.bytes.length),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(text),
                ],
              ),
            ),
          );
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('attachmentOpenFailed')),
        ),
      );
    }
  }

  Future<void> _deleteAttachment(VaultBlobListItem attachment) async {
    widget.services.recordActivity();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final strings = AppStrings.of(context);
        return SecureDialog(
          icon: Icons.delete_forever_rounded,
          title: strings.text('deleteAttachment'),
          message: strings
              .text('deleteAttachmentMessage')
              .replaceFirst('{name}', attachment.displayName),
          destructive: true,
          actions: [
            SecureDialogAction.destructive(
              label: strings.text('confirmDelete'),
              icon: Icons.delete_forever_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            SecureDialogAction.cancel(
              context,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    try {
      await widget.services.deleteVaultBlob(attachment.blobId);
      if (!mounted) return;
      await _loadAttachments();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('attachmentDeleteFailed')),
        ),
      );
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
                label: Text(
                  AppStrings.of(context).text('restore'),
                  style: const TextStyle(fontSize: 12),
                ),
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
    if (diff.inDays > 0) {
      return '${diff.inDays} ${AppStrings.of(context).text('daysAgo')}';
    }
    if (diff.inHours > 0) {
      return '${diff.inHours} ${AppStrings.of(context).text('hoursAgo')}';
    }
    if (diff.inMinutes > 0) {
      return '${diff.inMinutes} ${AppStrings.of(context).text('minutesAgo')}';
    }
    return AppStrings.of(context).text('justNow');
  }

  void _confirmRestore(Map<String, dynamic> record) {
    showDialog(
      context: context,
      builder: (ctx) {
        final strings = AppStrings.of(ctx);
        return SecureDialog(
          icon: Icons.restore_rounded,
          title: strings.text('restorePassword'),
          message: strings.text('restorePasswordMessage'),
          actions: [
            SecureDialogAction.primary(
              label: strings.text('confirmRestore'),
              icon: Icons.restore_rounded,
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
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
                  messenger.showSnackBar(
                    SnackBar(content: Text(strings.text('passwordRestored'))),
                  );
                } catch (_) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(strings.text('restorePasswordFailed')),
                    ),
                  );
                } finally {
                  if (mounted) setState(() => _isRestoring = false);
                }
              },
            ),
            SecureDialogAction.cancel(ctx),
          ],
        );
      },
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final strings = AppStrings.of(context);
        return SecureDialog(
          icon: Icons.warning_amber_rounded,
          title: strings.text('copyBackupConfirmTitle'),
          message: strings.text('copyBackupConfirmMessage'),
          destructive: true,
          actions: [
            SecureDialogAction.primary(
              label: strings.text('copyBackup'),
              icon: Icons.copy_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            SecureDialogAction.cancel(
              context,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
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
        content: Text(
          copied
              ? AppStrings.of(context).text('singleBackupCopied')
              : AppStrings.of(context).copyFailed,
        ),
      ),
    );
  }

  Future<void> _clearClipboardNow() async {
    final cleared = await widget.services.clearSensitiveClipboardNow();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cleared
              ? AppStrings.of(context).text('clipboardCleared')
              : AppStrings.of(context).text('clipboardClearNoPendingSecret'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return SecureDialog(
      icon: Icons.ios_share_outlined,
      title: strings.text('exportSinglePassword'),
      actions: [
        SecureDialogAction.primary(
          label: _copied ? strings.text('copied') : strings.text('copyBackup'),
          icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
          onPressed: _copyBackupJson,
        ),
        SecureDialogAction.secondary(
          label: strings.text('clearClipboardNow'),
          icon: Icons.cleaning_services_outlined,
          onPressed: _clearClipboardNow,
        ),
        SecureDialogAction.close(context),
      ],
      child: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.text('exportSinglePasswordSubtitle'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  strings
                      .text('backupPreparedNoPreview')
                      .replaceFirst(
                        '{bytes}',
                        widget.backupJson.length.toString(),
                      ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
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
    } on VaultBlobTooLargeException {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context)
                .text('attachmentTooLarge')
                .replaceFirst(
                  '{max}',
                  _formatAttachmentSize(maxVaultBlobBytes),
                ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('attachmentAddFailed')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return PopScope(
      canPop: !_isSaving,
      child: SecureDialog(
        icon: Icons.attach_file_rounded,
        title: strings.text('addAttachment'),
        actions: [
          SecureDialogAction.primary(
            key: const ValueKey('attachment-save-button'),
            label: strings.text('save'),
            icon: Icons.save_outlined,
            onPressed: _isSaving ? null : _save,
            busy: _isSaving,
          ),
          SecureDialogAction.cancel(
            context,
            onPressed: () => Navigator.of(context).pop(false),
            enabled: !_isSaving,
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('attachment-name-input'),
                controller: _nameController,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: strings.text('displayName'),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? strings.text('displayNameRequired')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('attachment-media-type-input'),
                controller: _mediaTypeController,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: strings.text('mediaType'),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('attachment-content-input'),
                controller: _contentController,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(labelText: strings.text('content')),
                minLines: 3,
                maxLines: 6,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return strings.text('contentRequired');
                  }
                  if (utf8.encode(value).length > maxVaultBlobBytes) {
                    return strings
                        .text('attachmentTooLarge')
                        .replaceFirst(
                          '{max}',
                          _formatAttachmentSize(maxVaultBlobBytes),
                        );
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
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
    final strings = AppStrings.of(context);

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
            tooltip: strings.text('openAttachment'),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          IconButton(
            key: ValueKey('attachment-delete-${attachment.blobId}'),
            onPressed: onDelete,
            tooltip: strings.text('deleteAttachment'),
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
