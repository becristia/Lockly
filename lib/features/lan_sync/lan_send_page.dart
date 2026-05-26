import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_server.dart';
import 'package:secure_box/core/vault/vault_manifest_service.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/core/vault/vault_session.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_panel.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class LanSendPage extends StatefulWidget {
  const LanSendPage({super.key, required this.services});

  final AppServices services;

  @override
  State<LanSendPage> createState() => _LanSendPageState();
}

class _LanSendPageState extends State<LanSendPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};

  List<VaultListItem> _items = const <VaultListItem>[];
  bool _loading = true;
  bool _creating = false;
  bool _includeBlobs = true;
  bool _includeHistory = false;
  String? _errorKey;
  LanTransferSession? _session;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    if (_session != null || _creating) {
      _cancelLanSendSessionBestEffort();
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final items = await widget.services.listVaultItems();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = items;
        _loading = false;
      });
    } on VaultLockedException {
      if (!mounted) {
        return;
      }
      setState(() {
        _items = const <VaultListItem>[];
        _loading = false;
        _errorKey = 'lanLocalVaultLocked';
      });
    } on VaultIntegrityException {
      if (!mounted) {
        return;
      }
      setState(() {
        _items = const <VaultListItem>[];
        _loading = false;
        _errorKey = 'lanPackageIntegrityFailed';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _items = const <VaultListItem>[];
        _loading = false;
        _errorKey = 'lanNetworkUnavailable';
      });
    }
  }

  Future<void> _createSession() async {
    if (_selectedIds.isEmpty || _creating) {
      return;
    }
    final sourceMasterPassword = await _promptSourceMasterPassword();
    if (sourceMasterPassword == null || !mounted) {
      return;
    }
    setState(() {
      _creating = true;
      _errorKey = null;
    });
    try {
      final session = await widget.services.createLanSendSession(
        itemIds: _selectedIds.toList(growable: false),
        includeBlobs: _includeBlobs,
        includeHistory: _includeHistory,
        sourceMasterPassword: sourceMasterPassword,
        senderName: AppStrings.of(context).appName,
      );
      if (!mounted) {
        _cancelLanSendSessionBestEffort();
        return;
      }
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
      setState(() {
        _session = session;
        _creating = false;
      });
    } on VaultUnlockException {
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
        _errorKey = 'lanSourcePasswordWrong';
      });
    } on VaultLockedException {
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
        _errorKey = 'lanLocalVaultLocked';
      });
    } on VaultIntegrityException {
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
        _errorKey = 'lanPackageIntegrityFailed';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
        _errorKey = 'lanSessionUnavailable';
      });
    }
  }

  Future<String?> _promptSourceMasterPassword() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _LanSendSourcePasswordDialog(),
    );
  }

  Future<void> _cancelSession() async {
    setState(() {
      _creating = true;
      _errorKey = null;
    });
    try {
      await widget.services.cancelLanSendSession();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
        _errorKey = 'lanSessionUnavailable';
      });
      return;
    }
    if (!mounted) {
      return;
    }
    _countdownTimer?.cancel();
    _countdownTimer = null;
    setState(() {
      _session = null;
      _creating = false;
    });
  }

  void _cancelLanSendSessionBestEffort() {
    try {
      unawaited(widget.services.cancelLanSendSession());
    } catch (_) {
      // Best-effort cleanup; fakes may not provide a LAN service.
    }
  }

  List<VaultListItem> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _items;
    }
    return _items
        .where((item) {
          final haystack = <String>[
            item.title,
            item.website,
            item.username,
            ...item.tags,
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final session = _session;

    return SecureVisualBackground(
      child: KeyedSubtree(
        key: const ValueKey('lan-send-page'),
        child: session == null
            ? _buildSelectionState(context, strings)
            : _buildSessionState(context, strings, session),
      ),
    );
  }

  Widget _buildSelectionState(BuildContext context, AppStrings strings) {
    final theme = Theme.of(context);
    final items = _filteredItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SecureReplicaHeader(title: strings.text('lanSelectRecords')),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              TextField(
                key: const ValueKey('lan-send-search-field'),
                controller: _searchController,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: strings.text('lanSearchRecords'),
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeBlobs,
                title: Text(strings.text('lanIncludeAttachments')),
                onChanged: (value) => setState(() => _includeBlobs = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeHistory,
                title: Text(strings.text('lanIncludePasswordHistory')),
                onChanged: (value) => setState(() => _includeHistory = value),
              ),
              if (_includeHistory) ...[
                const SizedBox(height: 6),
                SecureStatusSurface(
                  color: SecureVisualColors.warning,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: SecureVisualColors.warning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(strings.text('lanPasswordHistoryRisk')),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (_errorKey != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    strings.text(_errorKey!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              Text(
                _formatCount(strings, 'lanSelectedCount', _selectedIds.length),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              SecurePanel(
                padding: EdgeInsets.zero,
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(strings.text('lanNoMatchingRecords')),
                      )
                    : Column(
                        children: [
                          for (final item in items) _buildItemTile(item),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('lan-send-create-session'),
            onPressed: _selectedIds.isEmpty || _creating
                ? null
                : _createSession,
            icon: _creating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_2_rounded),
            label: Text(strings.text('lanCreateQr')),
          ),
        ),
      ],
    );
  }

  Widget _buildItemTile(VaultListItem item) {
    final selected = _selectedIds.contains(item.id);
    final subtitle = [
      if (item.website.trim().isNotEmpty) item.website,
      if (item.username.trim().isNotEmpty) item.username,
      if (item.tags.isNotEmpty)
        item.tags.join(AppStrings.of(context).text('listSeparator')),
    ].join(' - ');

    return CheckboxListTile(
      key: ValueKey('lan-send-item-${item.id}'),
      value: selected,
      title: Text(item.title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (value) {
        setState(() {
          if (value == true) {
            _selectedIds.add(item.id);
          } else {
            _selectedIds.remove(item.id);
          }
        });
      },
    );
  }

  Widget _buildSessionState(
    BuildContext context,
    AppStrings strings,
    LanTransferSession session,
  ) {
    final theme = Theme.of(context);
    final payload = session.qrPayload;
    final remaining = _remaining(session.expiresAt);

    return ListView(
      children: [
        SecureReplicaHeader(title: strings.text('lanQrReady')),
        const SizedBox(height: 16),
        Text(strings.text('lanScanQr'), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final qrSize = (constraints.maxWidth - 24).clamp(120.0, 260.0);
            return Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    key: const ValueKey('lan-send-qr'),
                    data: payload.encode(),
                    size: qrSize,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        SecurePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                label: strings.text('lanSelectedCountLabel'),
                value: payload.selectedCount.toString(),
              ),
              _InfoRow(
                label: strings.text('lanHostPort'),
                value: '${payload.host}:${payload.port}',
              ),
              _InfoRow(label: strings.text('lanQrExpires'), value: remaining),
            ],
          ),
        ),
        if (_errorKey != null) ...[
          const SizedBox(height: 10),
          Text(
            strings.text(_errorKey!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _creating ? null : _cancelSession,
          icon: const Icon(Icons.close_rounded),
          label: Text(
            strings.text(
              _creating ? 'lanCancellingSession' : 'lanCancelSession',
            ),
          ),
        ),
      ],
    );
  }

  String _remaining(DateTime expiresAt) {
    final remaining = expiresAt.toUtc().difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      return AppStrings.of(context).text('lanQrExpired');
    }
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _LanSendSourcePasswordDialog extends StatefulWidget {
  const _LanSendSourcePasswordDialog();

  @override
  State<_LanSendSourcePasswordDialog> createState() =>
      _LanSendSourcePasswordDialogState();
}

class _LanSendSourcePasswordDialogState
    extends State<_LanSendSourcePasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    _controller.clear();
    Navigator.of(context).pop();
  }

  void _confirm() {
    final password = _controller.text;
    _controller.clear();
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return AlertDialog(
      title: Text(strings.text('lanSourceMasterPassword')),
      content: TextFormField(
        key: const ValueKey('lan-send-source-master-password-field'),
        controller: _controller,
        obscureText: _obscure,
        enableSuggestions: false,
        autocorrect: false,
        autofocus: true,
        decoration: InputDecoration(
          labelText: strings.text('lanSourceMasterPassword'),
          suffixIcon: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
            ),
          ),
        ),
        onChanged: (_) => setState(() {}),
        onFieldSubmitted: (_) {
          if (_controller.text.isNotEmpty) {
            _confirm();
          }
        },
      ),
      actions: [
        TextButton(onPressed: _cancel, child: Text(strings.text('cancel'))),
        FilledButton(
          key: const ValueKey('lan-send-confirm-password'),
          onPressed: _controller.text.isEmpty ? null : _confirm,
          child: Text(strings.text('lanCreateQr')),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCount(AppStrings strings, String key, int count) {
  final template = strings.text(key);
  if (template.contains('{count}')) {
    return template.replaceAll('{count}', '$count');
  }
  return '$count $template';
}
