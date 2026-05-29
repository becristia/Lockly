import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/password_generator/totp_service.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_dialog.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class TotpPage extends StatefulWidget {
  const TotpPage({super.key, required this.services});

  final AppServices services;

  @override
  State<TotpPage> createState() => _TotpPageState();
}

class _TotpPageState extends State<TotpPage> {
  static const _standaloneTotpTags = ['mfa'];

  final TotpService _totpService = TotpService();
  List<TotpListItem> _items = [];
  bool _isLoading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    try {
      final items = await widget.services.listTotpItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showManualEntryDialog() async {
    widget.services.recordActivity();
    final draft = await showDialog<_StandaloneTotpDraft>(
      context: context,
      builder: (context) => const _StandaloneTotpDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    await _saveStandaloneTotp(draft);
  }

  Future<void> _showScanDialog() async {
    widget.services.recordActivity();
    final rawValue = await showDialog<String>(
      context: context,
      builder: (context) => const _TotpScanDialog(),
    );
    if (rawValue == null || rawValue.trim().isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    final strings = AppStrings.of(context);
    try {
      await _saveStandaloneTotp(_draftFromRaw(rawValue, strings));
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.text('totpSecretInvalid'))),
      );
    }
  }

  Future<void> _saveStandaloneTotp(_StandaloneTotpDraft draft) async {
    final strings = AppStrings.of(context);
    final normalizedSecret = draft.normalizedSecret;
    if (normalizedSecret == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.text('totpSecretInvalid'))),
      );
      return;
    }
    try {
      await widget.services.createVaultItem(
        PasswordEntry(
          title: draft.title,
          website: '',
          username: draft.username,
          password: '',
          notes: '',
          tags: _standaloneTotpTags,
          totpSecret: normalizedSecret,
          isStandaloneTotp: true,
        ),
      );
      if (!mounted) return;
      await _loadItems();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('totpSaveFailed'))));
    }
  }

  Future<void> _editStandaloneTotp(TotpListItem item) async {
    widget.services.recordActivity();
    final strings = AppStrings.of(context);
    try {
      final entry = await widget.services.getVaultItem(item.id);
      if (!mounted || !entry.isStandaloneTotp) {
        return;
      }
      final draft = await showDialog<_StandaloneTotpDraft>(
        context: context,
        builder: (context) => _StandaloneTotpDialog(
          titleKey: 'totpEditStandaloneTitle',
          submitLabelKey: 'save',
          initialTitle: entry.title,
          initialUsername: entry.username,
          secretRequired: false,
          secretHelperKey: 'totpSecretEditHelper',
        ),
      );
      if (draft == null || !mounted) {
        return;
      }
      await widget.services.updateVaultItem(
        item.id,
        PasswordEntry(
          title: draft.title,
          website: entry.website,
          username: draft.username,
          password: entry.password,
          notes: entry.notes,
          tags: entry.tags.isEmpty ? _standaloneTotpTags : entry.tags,
          totpSecret: draft.normalizedSecret ?? entry.totpSecret,
          passkey: entry.passkey,
          isStandaloneTotp: true,
        ),
      );
      if (!mounted) {
        return;
      }
      await _loadItems();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('totpSaveFailed'))));
    }
  }

  Future<void> _deleteStandaloneTotp(TotpListItem item) async {
    widget.services.recordActivity();
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return SecureDialog(
          icon: Icons.delete_forever_rounded,
          title: strings.text('totpDeleteStandaloneTitle'),
          message: strings
              .text('totpDeleteStandaloneMessage')
              .replaceAll('{title}', item.title),
          destructive: true,
          actions: [
            SecureDialogAction.destructive(
              label: strings.text('delete'),
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
    try {
      await widget.services.deleteVaultItem(item.id);
      if (!mounted) {
        return;
      }
      await _loadItems();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('deleteFailed'))));
    }
  }

  _StandaloneTotpDraft _draftFromRaw(String rawValue, AppStrings strings) {
    final normalizedSecret = TotpService.normalizeSecret(rawValue);
    var title = strings.text('totpStandaloneDefaultTitle');
    var username = '';

    if (rawValue.trim().toLowerCase().startsWith('otpauth://')) {
      final parsed = TotpService.parseOtpauthUrl(rawValue.trim());
      title = (parsed.issuer?.trim().isNotEmpty ?? false)
          ? parsed.issuer!.trim()
          : (parsed.label?.trim().isNotEmpty ?? false)
          ? parsed.label!.trim()
          : title;
      final label = parsed.label ?? '';
      final separator = label.indexOf(':');
      if (separator >= 0 && separator + 1 < label.length) {
        username = label.substring(separator + 1).trim();
      }
    }

    return _StandaloneTotpDraft(
      title: title,
      username: username,
      normalizedSecret: normalizedSecret,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final standaloneCount = _items.where((item) => item.isStandalone).length;
    final linkedCount = _items.length - standaloneCount;

    return SecureVisualBackground(
      bottomInset: 84,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadItems,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 112),
                children: [
                  _TotpHeader(
                    itemCount: _items.length,
                    linkedCount: linkedCount,
                    standaloneCount: standaloneCount,
                    onScan: _showScanDialog,
                    onManual: _showManualEntryDialog,
                  ),
                  const SizedBox(height: 16),
                  if (_items.isEmpty)
                    _EmptyTotpState(
                      onScan: _showScanDialog,
                      onManual: _showManualEntryDialog,
                    )
                  else
                    for (final item in _items) ...[
                      _TotpCard(
                        key: ValueKey('totp-card-${item.id}'),
                        services: widget.services,
                        item: item,
                        nowMs: nowMs,
                        totpService: _totpService,
                        onEdit: item.isStandalone
                            ? () => _editStandaloneTotp(item)
                            : null,
                        onDelete: item.isStandalone
                            ? () => _deleteStandaloneTotp(item)
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
    );
  }
}

class _TotpHeader extends StatelessWidget {
  const _TotpHeader({
    required this.itemCount,
    required this.linkedCount,
    required this.standaloneCount,
    required this.onScan,
    required this.onManual,
  });

  final int itemCount;
  final int linkedCount;
  final int standaloneCount;
  final VoidCallback onScan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);

    return SecureGlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      borderRadius: 18,
      color: theme.colorScheme.surface,
      borderColor: theme.colorScheme.outlineVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SecureIconTile(
                icon: Icons.qr_code_2_rounded,
                color: SecureVisualColors.cyan,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text('totpPageTitle'),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      strings.text('totpPageSubtitle'),
                      style: theme.textTheme.bodyMedium,
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
            children: [
              _TotpHeaderChip(
                icon: Icons.password_rounded,
                label: strings
                    .text('totpHeaderVaultLinked')
                    .replaceAll('{count}', '$linkedCount'),
                color: SecureVisualColors.blue,
              ),
              _TotpHeaderChip(
                icon: Icons.verified_user_outlined,
                label: strings
                    .text('totpHeaderStandalone')
                    .replaceAll('{count}', '$standaloneCount'),
                color: SecureVisualColors.success,
              ),
              _TotpHeaderChip(
                icon: Icons.pin_outlined,
                label: strings
                    .text('totpHeaderTotal')
                    .replaceAll('{count}', '$itemCount'),
                color: SecureVisualColors.cyan,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TotpActions(onScan: onScan, onManual: onManual),
        ],
      ),
    );
  }
}

class _TotpHeaderChip extends StatelessWidget {
  const _TotpHeaderChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotpActions extends StatelessWidget {
  const _TotpActions({required this.onScan, required this.onManual});

  final VoidCallback onScan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        final scanButton = FilledButton.icon(
          key: const ValueKey('totp-scan-entry'),
          onPressed: onScan,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: Text(
            strings.text('scanQrCode'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
        final manualButton = OutlinedButton.icon(
          key: const ValueKey('totp-manual-entry'),
          onPressed: onManual,
          icon: const Icon(Icons.edit_note_rounded),
          label: Text(
            strings.text('manualInput'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 52, child: scanButton),
              const SizedBox(height: 10),
              SizedBox(height: 52, child: manualButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: SizedBox(height: 52, child: scanButton)),
            const SizedBox(width: 12),
            Expanded(child: SizedBox(height: 52, child: manualButton)),
          ],
        );
      },
    );
  }
}

class _EmptyTotpState extends StatelessWidget {
  const _EmptyTotpState({required this.onScan, required this.onManual});

  final VoidCallback onScan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);

    return SecureGlassCard(
      key: const ValueKey('totp-empty-state'),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      borderRadius: 18,
      child: Column(
        children: [
          const SecureIconBadge(
            icon: Icons.verified_user_outlined,
            color: SecureVisualColors.cyan,
            size: 76,
          ),
          const SizedBox(height: 16),
          Text(
            strings.text('totpEmptyTitle'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            strings.text('totpEmptyMessage'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          _TotpActions(onScan: onScan, onManual: onManual),
        ],
      ),
    );
  }
}

class _TotpCard extends StatelessWidget {
  const _TotpCard({
    super.key,
    required this.services,
    required this.item,
    required this.nowMs,
    required this.totpService,
    this.onEdit,
    this.onDelete,
  });

  final AppServices services;
  final TotpListItem item;
  final int nowMs;
  final TotpService totpService;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final remaining = totpService.remainingSeconds(nowMs);
    final progress = remaining / 30.0;
    final color = remaining > 10
        ? SecureVisualColors.success
        : remaining > 5
        ? const Color(0xFFF5A623)
        : SecureVisualColors.danger;
    String? code;
    try {
      code = totpService.generate(
        base32Secret: item.totpSecret,
        timestampMs: nowMs,
      );
    } on FormatException {
      code = null;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: code == null
          ? null
          : () async {
              final copied = await services.copySensitiveTemporary(
                code!,
                clearAfter: Duration(seconds: remaining),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    copied
                        ? strings.text('totpCodeCopied')
                        : strings.copyFailed,
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
      child: SecureGlassCard(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        borderRadius: 18,
        child: Row(
          children: [
            SizedBox.square(
              dimension: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    color: color,
                    backgroundColor: SecureVisualColors.line.withValues(
                      alpha: 0.52,
                    ),
                    strokeWidth: 4,
                  ),
                  Text(
                    '${remaining}s',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      code == null
                          ? strings.text('totpSecretInvalid')
                          : TotpService.formatCode(code),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: SecureVisualColors.text,
                            fontSize: code == null ? 16 : null,
                            fontWeight: FontWeight.w900,
                            letterSpacing: code == null ? 0 : 4,
                          ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: SecureVisualColors.text,
                      fontWeight: FontWeight.w900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.username.isNotEmpty ? item.username : '-',
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _SourcePill(
                    label: item.isStandalone
                        ? strings.text('totpStandaloneLabel')
                        : strings.text('totpVaultLinkedLabel'),
                    color: item.isStandalone
                        ? SecureVisualColors.success
                        : SecureVisualColors.blue,
                  ),
                ],
              ),
            ),
            if (item.isStandalone) ...[
              const SizedBox(width: 8),
              PopupMenuButton<_TotpItemAction>(
                key: ValueKey('totp-standalone-menu-${item.id}'),
                tooltip: strings.text('edit'),
                onSelected: (action) {
                  switch (action) {
                    case _TotpItemAction.edit:
                      onEdit?.call();
                      break;
                    case _TotpItemAction.delete:
                      onDelete?.call();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: ValueKey('totp-standalone-edit-${item.id}'),
                    value: _TotpItemAction.edit,
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined, size: 18),
                        const SizedBox(width: 10),
                        Text(strings.text('edit')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    key: ValueKey('totp-standalone-delete-${item.id}'),
                    value: _TotpItemAction.delete,
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Text(strings.text('delete')),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _TotpItemAction { edit, delete }

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _StandaloneTotpDialog extends StatefulWidget {
  const _StandaloneTotpDialog({
    this.titleKey = 'totpManualTitle',
    this.submitLabelKey = 'totpSaveStandalone',
    this.initialTitle = '',
    this.initialUsername = '',
    this.secretRequired = true,
    this.secretHelperKey = 'totpSecretHelper',
  });

  final String titleKey;
  final String submitLabelKey;
  final String initialTitle;
  final String initialUsername;
  final bool secretRequired;
  final String secretHelperKey;

  @override
  State<_StandaloneTotpDialog> createState() => _StandaloneTotpDialogState();
}

class _StandaloneTotpDialogState extends State<_StandaloneTotpDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.initialTitle;
    _usernameController.text = widget.initialUsername;
  }

  @override
  void dispose() {
    _titleController.clear();
    _usernameController.clear();
    _titleController.dispose();
    _usernameController.dispose();
    _secretController.clear();
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SecureDialog(
      icon: Icons.password_rounded,
      title: strings.text(widget.titleKey),
      actions: [
        SecureDialogAction.primary(
          key: const ValueKey('totp-standalone-save-button'),
          label: strings.text(widget.submitLabelKey),
          icon: Icons.check_rounded,
          onPressed: _submit,
        ),
        SecureDialogAction.cancel(context),
      ],
      child: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('totp-standalone-title-field'),
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: strings.text('totpStandaloneNameLabel'),
                  hintText: strings.text('totpStandaloneNameHint'),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return strings.text('enterTitle');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('totp-standalone-username-field'),
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: strings.text('totpStandaloneAccountLabel'),
                  hintText: strings.text('totpStandaloneAccountHint'),
                ),
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('totp-standalone-secret-field'),
                controller: _secretController,
                decoration: InputDecoration(
                  labelText: strings.text('totpStandaloneSecretLabel'),
                  hintText: strings.text('totpSecretHint'),
                  helperText: strings.text(widget.secretHelperKey),
                ),
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return widget.secretRequired
                        ? strings.text('totpSecretInvalid')
                        : null;
                  }
                  if (!TotpService.isValidSecret(value)) {
                    return strings.text('totpSecretInvalid');
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    Navigator.of(context).pop(
      _StandaloneTotpDraft(
        title: _titleController.text.trim(),
        username: _usernameController.text.trim(),
        normalizedSecret: _secretController.text.trim().isEmpty
            ? null
            : TotpService.normalizeSecret(_secretController.text),
      ),
    );
  }
}

class _TotpScanDialog extends StatefulWidget {
  const _TotpScanDialog();

  @override
  State<_TotpScanDialog> createState() => _TotpScanDialogState();
}

class _TotpScanDialogState extends State<_TotpScanDialog> {
  final TextEditingController _pasteController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();
  bool _accepted = false;

  @override
  void dispose() {
    _pasteController.clear();
    _pasteController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SecureDialog(
      icon: Icons.qr_code_scanner_rounded,
      title: strings.text('totpScanTitle'),
      actions: [
        SecureDialogAction.primary(
          key: const ValueKey('totp-use-pasted-otpauth'),
          label: strings.text('totpUsePastedOtpAuth'),
          icon: Icons.check_rounded,
          onPressed: () => _accept(_pasteController.text),
        ),
        SecureDialogAction.cancel(context),
      ],
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.text('totpScanSubtitle')),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _shouldBuildScanner()
                  ? AspectRatio(
                      aspectRatio: 4 / 3,
                      child: MobileScanner(
                        controller: _scannerController,
                        onDetect: _onDetect,
                      ),
                    )
                  : SecureStatusSurface(
                      color: SecureVisualColors.cyan,
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        strings.text('totpScannerUnavailable'),
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('totp-scan-paste-field'),
              controller: _pasteController,
              minLines: 2,
              maxLines: 4,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: strings.text('totpPasteOtpAuthLabel'),
                hintText: strings.text('totpPasteOtpAuthHint'),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_accepted) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null || rawValue.trim().isEmpty) {
        continue;
      }
      _accept(rawValue);
      return;
    }
  }

  void _accept(String rawValue) {
    if (_accepted || rawValue.trim().isEmpty) {
      return;
    }
    _accepted = true;
    Navigator.of(context).pop(rawValue.trim());
  }

  bool _shouldBuildScanner() {
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    if (bindingName.toLowerCase().contains('test')) {
      return false;
    }
    return kIsWeb || _isScannerPlatformSupported(defaultTargetPlatform);
  }
}

bool _isScannerPlatformSupported(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.windows => false,
  };
}

class _StandaloneTotpDraft {
  const _StandaloneTotpDraft({
    required this.title,
    required this.username,
    required this.normalizedSecret,
  });

  final String title;
  final String username;
  final String? normalizedSecret;
}
