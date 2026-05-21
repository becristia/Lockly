import 'dart:async';

import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/password_generator/totp_service.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class TotpPage extends StatefulWidget {
  const TotpPage({super.key, required this.services});

  final AppServices services;

  @override
  State<TotpPage> createState() => _TotpPageState();
}

class _TotpPageState extends State<TotpPage> {
  final TotpService _totpService = TotpService();
  List<TotpListItem> _items = [];
  bool _isLoading = true;
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _tick++);
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

  @override
  Widget build(BuildContext context) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      body: SecureVisualBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_2_rounded,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No TOTP items',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Edit an item to add a TOTP secret',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadItems,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 54, 10, 120),
                  itemCount: _items.length,
                  itemBuilder: (context, index) => _TotpCard(
                    services: widget.services,
                    item: _items[index],
                    nowMs: nowMs,
                    totpService: _totpService,
                  ),
                ),
              ),
      ),
    );
  }
}

class _TotpCard extends StatelessWidget {
  const _TotpCard({
    required this.services,
    required this.item,
    required this.nowMs,
    required this.totpService,
  });

  final AppServices services;
  final TotpListItem item;
  final int nowMs;
  final TotpService totpService;

  @override
  Widget build(BuildContext context) {
    final remaining = totpService.remainingSeconds(nowMs);
    final progress = remaining / 30.0;
    final color = remaining > 10
        ? SecureVisualColors.success
        : remaining > 5
        ? const Color(0xFFF5A623)
        : SecureVisualColors.danger;
    final code = totpService.generate(
      base32Secret: item.totpSecret,
      timestampMs: nowMs,
    );

    return GestureDetector(
      onTap: () async {
        final copied = await services.copySensitiveTemporary(
          code,
          clearAfter: Duration(seconds: remaining),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              copied ? 'Code copied. Clipboard clears on expiry.' : 'Copy failed.',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: SecureGlassCard(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
        borderRadius: 28,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 66,
              height: 66,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 66,
                    height: 66,
                    child: CircularProgressIndicator(
                      value: progress,
                      color: color,
                      backgroundColor: SecureVisualColors.line.withValues(
                        alpha: 0.52,
                      ),
                      strokeWidth: 4,
                    ),
                  ),
                  Text(
                    '${remaining}s',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text(
              TotpService.formatCode(code),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: SecureVisualColors.text,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              item.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: SecureVisualColors.muted,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              item.username.isNotEmpty ? item.username : '-',
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
