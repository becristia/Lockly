import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_dialog.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class BackupExportWizardPage extends StatefulWidget {
  const BackupExportWizardPage({super.key, required this.services});

  final AppServices services;

  @override
  State<BackupExportWizardPage> createState() => _BackupExportWizardPageState();
}

class _BackupExportWizardPageState extends State<BackupExportWizardPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _masterPasswordController =
      TextEditingController();

  bool _busy = false;
  bool _copied = false;
  bool _obscureMasterPassword = true;
  String? _backupJson;
  String? _error;
  _BackupExportSummary? _summary;

  @override
  void dispose() {
    _masterPasswordController.clear();
    _masterPasswordController.dispose();
    super.dispose();
  }

  Future<void> _prepareBackup() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    widget.services.recordActivity();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _copied = false;
    });

    try {
      await widget.services.verifyMasterPassword(
        _masterPasswordController.text,
      );
      final backupJson = await widget.services.exportEncryptedBackupJson();
      final summary = _BackupExportSummary.parse(backupJson);
      _masterPasswordController.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _backupJson = backupJson;
        _summary = summary;
        _busy = false;
      });
    } catch (_) {
      _masterPasswordController.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = AppStrings.of(context).text('exportFailed');
      });
    }
  }

  Future<void> _copyBackupJson() async {
    final backupJson = _backupJson;
    if (backupJson == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => SecureDialog(
        icon: Icons.copy_rounded,
        title: AppStrings.of(context).text('copyBackupConfirmTitle'),
        message: AppStrings.of(context).text('copyBackupConfirmMessage'),
        destructive: true,
        actions: [
          SecureDialogAction.destructive(
            label: AppStrings.of(context).text('copyBackup'),
            icon: Icons.copy_rounded,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          SecureDialogAction.cancel(
            context,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final copied = await widget.services.copySensitiveTemporary(
      backupJson,
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
              ? AppStrings.of(context).text('backupCopied')
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
    final strings = AppStrings.of(context);
    final summary = _summary;

    return PopScope(
      canPop: !_busy,
      child: SecureVisualBackground(
        key: const ValueKey('backup-export-wizard-page'),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: ListView(
          children: [
            SecureReplicaHeader(
              title: strings.text('backupExportTitle'),
              subtitle: strings.text('backupExportWizardSubtitle'),
              leading: IconButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (summary == null)
              _BackupPrepareCard(
                formKey: _formKey,
                controller: _masterPasswordController,
                busy: _busy,
                error: _error,
                obscureMasterPassword: _obscureMasterPassword,
                onToggleObscure: () {
                  setState(
                    () => _obscureMasterPassword = !_obscureMasterPassword,
                  );
                },
                onPrepare: _prepareBackup,
              )
            else
              _BackupReadyCard(
                summary: summary,
                copied: _copied,
                onCopy: _copyBackupJson,
                onClearClipboard: _clearClipboardNow,
              ),
          ],
        ),
      ),
    );
  }
}

class _BackupPrepareCard extends StatelessWidget {
  const _BackupPrepareCard({
    required this.formKey,
    required this.controller,
    required this.busy,
    required this.error,
    required this.obscureMasterPassword,
    required this.onToggleObscure,
    required this.onPrepare,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final bool busy;
  final String? error;
  final bool obscureMasterPassword;
  final VoidCallback onToggleObscure;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);

    return SecureGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SecureStatusSurface(
              color: SecureVisualColors.blue,
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: SecureVisualColors.blue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      strings.text('backupExportPrepareDetail'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('backup-export-master-password-input'),
              controller: controller,
              obscureText: obscureMasterPassword,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: strings.text('masterPassword'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: obscureMasterPassword
                      ? strings.text('showMasterPassword')
                      : strings.text('hideMasterPassword'),
                  onPressed: busy ? null : onToggleObscure,
                  icon: Icon(
                    obscureMasterPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return strings.text('requiredMasterPassword');
                }
                return null;
              },
              onFieldSubmitted: (_) {
                if (!busy) {
                  onPrepare();
                }
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('backup-export-prepare-button'),
              onPressed: busy ? null : onPrepare,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.inventory_2_outlined),
              label: Text(
                busy
                    ? strings.text('backupExportPreparing')
                    : strings.text('backupExportPrepare'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupReadyCard extends StatelessWidget {
  const _BackupReadyCard({
    required this.summary,
    required this.copied,
    required this.onCopy,
    required this.onClearClipboard,
  });

  final _BackupExportSummary summary;
  final bool copied;
  final VoidCallback onCopy;
  final VoidCallback onClearClipboard;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SecureGlassCard(
      key: const ValueKey('backup-export-ready-summary'),
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SecureStatusSurface(
            color: SecureVisualColors.success,
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: SecureVisualColors.success,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(strings.text('backupExportReadyDetail'))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SummaryRow(
            icon: Icons.key_rounded,
            label: strings.text('backupExportItems'),
            value: summary.itemCount.toString(),
          ),
          _SummaryRow(
            icon: Icons.attach_file_rounded,
            label: strings.text('backupExportAttachments'),
            value: summary.blobCount.toString(),
          ),
          _SummaryRow(
            icon: Icons.history_rounded,
            label: strings.text('backupExportHistory'),
            value: summary.historyCount.toString(),
          ),
          _SummaryRow(
            icon: Icons.data_object_rounded,
            label: strings.text('backupExportSize'),
            value: _formatExportSize(summary.bytes),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('backup-export-copy-button'),
            onPressed: onCopy,
            icon: Icon(copied ? Icons.check_rounded : Icons.copy_rounded),
            label: Text(
              copied ? strings.text('copied') : strings.text('copyBackup'),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onClearClipboard,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(strings.text('clearClipboardNow')),
          ),
        ],
      ),
    );
  }

  String _formatExportSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(mb.truncateToDouble() == mb ? 0 : 1)} MB';
    }
    if (bytes >= 1024) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(kb.truncateToDouble() == kb ? 0 : 1)} KB';
    }
    return '$bytes B';
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupExportSummary {
  const _BackupExportSummary({
    required this.itemCount,
    required this.blobCount,
    required this.historyCount,
    required this.bytes,
  });

  factory _BackupExportSummary.parse(String backupJson) {
    final decoded = jsonDecode(backupJson);
    if (decoded is! Map) {
      throw const FormatException('Invalid backup JSON');
    }
    final json = Map<String, Object?>.from(decoded);
    return _BackupExportSummary(
      itemCount: _count(json, 'item_count', 'items'),
      blobCount: _count(json, 'blob_count', 'blobs'),
      historyCount: _count(json, 'history_count', 'history'),
      bytes: utf8.encode(backupJson).length,
    );
  }

  final int itemCount;
  final int blobCount;
  final int historyCount;
  final int bytes;

  static int _count(
    Map<String, Object?> json,
    String countKey,
    String listKey,
  ) {
    final count = json[countKey];
    if (count is int) {
      return count;
    }
    final list = json[listKey];
    if (list is List) {
      return list.length;
    }
    if (list is int) {
      return list;
    }
    return 0;
  }
}
