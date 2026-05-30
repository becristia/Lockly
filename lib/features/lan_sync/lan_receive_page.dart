import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/cancellation/cancellation_token.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_client.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/core/vault/vault_session.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_dialog.dart';
import 'package:secure_box/shared/widgets/secure_panel.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class LanReceivePage extends StatefulWidget {
  const LanReceivePage({super.key, required this.services});

  final AppServices services;

  @override
  State<LanReceivePage> createState() => _LanReceivePageState();
}

class _LanReceivePageState extends State<LanReceivePage> {
  final TextEditingController _pasteController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();

  bool _scannerPaused = false;
  bool _dialogOpen = false;
  String? _errorKey;
  LanTransferQrPayload? _payload;
  LanTransferImportResult? _result;

  @override
  void dispose() {
    _pasteController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _usePastedPayload() async {
    await _handlePayloadText(_pasteController.text);
  }

  Future<void> _handlePayloadText(String rawValue) async {
    final strings = AppStrings.of(context);
    final LanTransferQrPayload payload;
    try {
      payload = LanTransferQrPayload.decode(rawValue.trim());
    } on Object {
      setState(() => _errorKey = 'lanTransferMalformed');
      _resumeScanner();
      return;
    }
    _pasteController.clear();
    setState(() {
      _payload = payload;
      _errorKey = null;
    });
    _pauseScanner();
    await _confirmAndImportPayload(payload, strings);
  }

  Future<void> _confirmAndImportPayload(
    LanTransferQrPayload payload,
    AppStrings strings,
  ) async {
    if (_dialogOpen) {
      return;
    }
    _dialogOpen = true;
    final result = await showDialog<LanTransferImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _LanTransferImportDialog(
        title: _formatWithSender(
          strings,
          'lanImportFromSenderTitle',
          payload.senderName,
        ),
        onImport: (cancellationToken) => widget.services.receiveLanTransfer(
          payload: payload,
          cancellationToken: cancellationToken,
        ),
      ),
    );
    _dialogOpen = false;
    if (!mounted) {
      return;
    }
    if (result != null) {
      setState(() {
        _result = result;
        _errorKey = null;
      });
    } else {
      setState(() {
        _payload = null;
        _result = null;
      });
      _resumeScanner();
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scannerPaused || _dialogOpen) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null || rawValue.trim().isEmpty) {
        continue;
      }
      _pauseScanner();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handlePayloadText(rawValue);
        }
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);

    return SecureVisualBackground(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SecureReplicaHeader(title: strings.text('lanReceiveData')),
            const SizedBox(height: 16),
            Text(
              strings.text('lanReceiveDataSubtitle'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            SecurePanel(child: _buildScannerArea(strings)),
            const SizedBox(height: 14),
            SecurePanel(child: _buildPasteFallback(strings)),
            if (_payload != null && _result == null) ...[
              const SizedBox(height: 12),
              _PayloadSummary(payload: _payload!),
            ],
            if (_errorKey != null) ...[
              const SizedBox(height: 12),
              Text(
                strings.text(_errorKey!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              _ImportResultView(result: _result!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScannerArea(AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.qr_code_scanner_rounded),
            const SizedBox(width: 8),
            Text(
              strings.text('lanScanQr'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _shouldBuildScanner()
              ? AspectRatio(
                  aspectRatio: 4 / 3,
                  child: MobileScanner(
                    controller: _scannerController,
                    onDetect: _onDetect,
                  ),
                )
              : SizedBox(
                  height: 132,
                  width: double.infinity,
                  child: ColoredBox(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: Text(strings.text('lanScannerUnavailable')),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPasteFallback(AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.content_paste_rounded),
            const SizedBox(width: 8),
            Text(
              strings.text('lanPasteQrPayload'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('lan-receive-paste-field'),
          controller: _pasteController,
          enableSuggestions: false,
          autocorrect: false,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: strings.text('lanPastePayloadLabel'),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('lan-receive-use-pasted-payload'),
            onPressed: _usePastedPayload,
            icon: const Icon(Icons.check_rounded),
            label: Text(strings.text('lanPasteQrPayload')),
          ),
        ),
      ],
    );
  }

  bool _shouldBuildScanner() {
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    if (bindingName.toLowerCase().contains('test')) {
      return false;
    }
    return kIsWeb || isLanScannerPlatformSupported(defaultTargetPlatform);
  }

  void _pauseScanner() {
    if (_scannerPaused) {
      return;
    }
    _scannerPaused = true;
    if (_shouldBuildScanner()) {
      unawaited(_scannerController.stop());
    }
  }

  void _resumeScanner() {
    if (!_scannerPaused) {
      return;
    }
    setState(() => _scannerPaused = false);
    if (_shouldBuildScanner()) {
      unawaited(_scannerController.start());
    }
  }
}

bool isLanScannerPlatformSupported(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.windows => false,
  };
}

class _LanTransferImportDialog extends StatefulWidget {
  const _LanTransferImportDialog({required this.title, required this.onImport});

  final String title;
  final Future<LanTransferImportResult> Function(
    CancellationToken cancellationToken,
  )
  onImport;

  @override
  State<_LanTransferImportDialog> createState() =>
      _LanTransferImportDialogState();
}

class _LanTransferImportDialogState extends State<_LanTransferImportDialog> {
  bool _importing = false;
  String? _errorKey;
  CancellationToken? _activeCancellationToken;

  @override
  void dispose() {
    _activeCancellationToken?.cancel();
    super.dispose();
  }

  void _cancel() {
    _activeCancellationToken?.cancel();
    Navigator.of(context).pop();
  }

  Future<void> _import() async {
    if (_importing) {
      return;
    }
    final cancellationToken = CancellationToken();
    _activeCancellationToken = cancellationToken;
    setState(() {
      _importing = true;
      _errorKey = null;
    });
    try {
      final result = await widget.onImport(cancellationToken);
      if (!mounted) {
        return;
      }
      _activeCancellationToken = null;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _activeCancellationToken = null;
      setState(() {
        _importing = false;
        _errorKey = _mapImportError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return SecureDialog(
      icon: Icons.lock_outline_rounded,
      title: widget.title,
      actions: [
        SecureDialogAction.primary(
          key: const ValueKey('lan-receive-import-button'),
          label: strings.text('import'),
          icon: Icons.download_done_rounded,
          onPressed: _import,
          busy: _importing,
        ),
        SecureDialogAction.cancel(context, onPressed: _cancel),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.text('lanOneTimeImportSubtitle')),
          if (_errorKey != null) ...[
            const SizedBox(height: 10),
            Text(
              strings.text(_errorKey!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _PayloadSummary extends StatelessWidget {
  const _PayloadSummary({required this.payload});

  final LanTransferQrPayload payload;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return SecureStatusSurface(
      color: SecureVisualColors.blue,
      child: Text(
        _formatWithSender(strings, 'lanPayloadAccepted', payload.senderName),
      ),
    );
  }
}

class _ImportResultView extends StatelessWidget {
  const _ImportResultView({required this.result});

  final LanTransferImportResult result;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);

    return SecurePanel(
      child: KeyedSubtree(
        key: const ValueKey('lan-import-result'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.text('lanImportComplete'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SecureStatusPill(
                  icon: Icons.download_done_rounded,
                  label: _formatCount(
                    strings,
                    'lanImportedCount',
                    result.importedCount,
                  ),
                  color: SecureVisualColors.success,
                ),
                SecureStatusPill(
                  icon: Icons.block_rounded,
                  label: _formatCount(
                    strings,
                    'lanSkippedCount',
                    result.skippedCount,
                  ),
                  color: SecureVisualColors.warning,
                ),
              ],
            ),
            if (result.conflicts.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                strings.text('lanConflicts'),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              for (final conflict in result.conflicts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(conflict.title),
                  subtitle: Text(
                    [
                      if (conflict.website.isNotEmpty) conflict.website,
                      if (conflict.username.isNotEmpty) conflict.username,
                      _reasonLabel(strings, conflict.reason),
                    ].join(' - '),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _mapImportError(Object error) {
  if (error is LanTransferExpiredException) {
    return 'lanQrExpired';
  }
  if (error is LanTransferUnavailableException) {
    return 'lanNetworkUnavailable';
  }
  if (error is LanTransferUnauthorizedException) {
    return 'lanSessionUnavailable';
  }
  if (error is LanTransferIntegrityException ||
      error is VaultIntegrityException) {
    return 'lanPackageIntegrityFailed';
  }
  if (error is VaultUnlockException) {
    return 'lanPackageUnlockFailed';
  }
  if (error is VaultLockedException) {
    return 'lanLocalVaultLocked';
  }
  if (error is LanTransferMalformedException ||
      error is LanTransferFormatException ||
      error is FormatException) {
    return 'lanTransferMalformed';
  }
  if (error is StateError && error.message.toLowerCase().contains('unlock')) {
    return 'lanLocalVaultLocked';
  }
  return 'lanSessionUnavailable';
}

String _reasonLabel(AppStrings strings, LanTransferConflictReason reason) {
  return switch (reason) {
    LanTransferConflictReason.existingLocalEntry => strings.text(
      'lanConflictExisting',
    ),
    LanTransferConflictReason.duplicateIncomingEntry => strings.text(
      'lanConflictDuplicate',
    ),
  };
}

String _formatCount(AppStrings strings, String key, int count) {
  final template = strings.text(key);
  if (template.contains('{count}')) {
    return template.replaceAll('{count}', '$count');
  }
  return '$count $template';
}

String _formatWithSender(AppStrings strings, String key, String sender) {
  return strings.text(key).replaceAll('{sender}', sender);
}
