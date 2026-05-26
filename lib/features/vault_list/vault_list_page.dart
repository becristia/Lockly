import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/features/trash/trash_page.dart';
import 'package:secure_box/features/vault_detail/vault_detail_page.dart';
import 'package:secure_box/features/vault_edit/vault_edit_page.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_panel.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

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

  List<String> _allTags = [];
  String? _selectedTag;
  int _deletedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadTags();
    _loadDeletedCount();
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
      var items = await widget.services.listVaultItems(query: query);
      if (_selectedTag != null && _selectedTag!.isNotEmpty) {
        items = items.where((i) => i.tags.contains(_selectedTag)).toList();
      }
      if (!mounted || requestId != _loadSequence) {
        return;
      }
      setState(() {
        _items = items;
        _isLoading = false;
      });
      _loadDeletedCount();
    } catch (_) {
      if (!mounted || requestId != _loadSequence) {
        return;
      }
      setState(() {
        _items = const <VaultListItem>[];
        _isLoading = false;
        _errorMessage = AppStrings.of(context).vaultLoadFailedMessage;
      });
    }
  }

  Future<void> _loadTags() async {
    try {
      final tags = await widget.services.allTags();
      if (!mounted) return;
      setState(() => _allTags = tags);
    } catch (_) {}
  }

  Future<void> _loadDeletedCount() async {
    try {
      final count = await widget.services.deletedItemCount();
      if (!mounted) return;
      setState(() => _deletedCount = count);
    } catch (_) {}
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
      _loadTags();
      _loadDeletedCount();
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
      _loadTags();
      _loadDeletedCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return SecureVisualBackground(
      bottomInset: 0,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
          onPressed: _handleAdd,
          tooltip: strings.addPasswordTooltip,
          child: const Icon(Icons.add_rounded),
        ),
        body: RefreshIndicator(
          onRefresh: _loadItems,
          child: ListView(
            padding: EdgeInsets.fromLTRB(0, 8, 0, hasQuery ? 32 : 96),
            children: [
              SecureReplicaHeader(title: strings.vaultTitle),
              const SizedBox(height: 22),
              _SecuritySummary(itemCount: _items.length, isLoading: _isLoading),
              const SizedBox(height: 16),
              SecureGlassCard(
                padding: EdgeInsets.zero,
                shadow: false,
                child: TextField(
                  controller: _searchController,
                  enableSuggestions: false,
                  autocorrect: false,
                  onTap: widget.services.recordActivity,
                  onChanged: (_) {
                    widget.services.recordActivity();
                    _loadItems();
                  },
                  decoration: InputDecoration(
                    labelText: strings.searchLabel,
                    hintText: strings.searchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: const Icon(Icons.tune_rounded),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              if (_allTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _allTags.length + 1,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return FilterChip(
                          selected: _selectedTag == null,
                          label: Text(
                            strings.allTagsFilter,
                            style: TextStyle(fontSize: 12),
                          ),
                          onSelected: (_) {
                            setState(() => _selectedTag = null);
                            _loadItems();
                          },
                          selectedColor: SecureVisualColors.blue.withValues(
                            alpha: 0.15,
                          ),
                          checkmarkColor: SecureVisualColors.blue,
                          visualDensity: VisualDensity.compact,
                        );
                      }
                      final tag = _allTags[index - 1];
                      final selected = _selectedTag == tag;
                      return FilterChip(
                        selected: selected,
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        onSelected: selected
                            ? (_) {
                                setState(() => _selectedTag = null);
                                _loadItems();
                              }
                            : (_) {
                                setState(() => _selectedTag = tag);
                                _loadItems();
                              },
                        selectedColor: SecureVisualColors.blue.withValues(
                          alpha: 0.15,
                        ),
                        checkmarkColor: SecureVisualColors.blue,
                        visualDensity: VisualDensity.compact,
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                hasQuery
                    ? strings.searchResultCount(_items.length)
                    : strings.recentItemsTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                _ListMessage(
                  title: strings.vaultLoadFailedTitle,
                  message: _errorMessage!,
                  actionLabel: strings.retry,
                  onAction: _loadItems,
                )
              else if (_items.isEmpty)
                _ListMessage(
                  title: hasQuery
                      ? strings.noSearchResultsTitle
                      : strings.emptyVaultTitle,
                  message: hasQuery
                      ? strings.noSearchResultsMessage
                      : strings.emptyVaultMessage,
                )
              else
                SecureGlassCard(
                  padding: EdgeInsets.zero,
                  shadow: false,
                  child: Column(
                    children: [
                      for (final item in _items)
                        _VaultReplicaTile(
                          item: item,
                          onTap: () => _openDetail(item),
                        ),
                    ],
                  ),
                ),
              if (_deletedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ListTile(
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: Text(strings.trashTitleWithCount(_deletedCount)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      widget.services.recordActivity();
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TrashPage(services: widget.services),
                        ),
                      );
                      _loadItems();
                      _loadDeletedCount();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultReplicaTile extends StatelessWidget {
  const _VaultReplicaTile({required this.item, required this.onTap});

  final VaultListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SecureVisualColors.blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.mail_outline_rounded,
                  color: theme.colorScheme.primary,
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
                          ? strings.missingUsername
                          : item.username,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz_rounded),
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
    final strings = AppStrings.of(context);

    return SecureGlassCard(
      key: const ValueKey('vault-list-security-summary'),
      padding: const EdgeInsets.all(18),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SecureIconTile(
                icon: Icons.enhanced_encryption_outlined,
                color: SecureVisualColors.blue,
                size: 46,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.securitySummaryTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLoading
                          ? strings.securitySummaryLoading
                          : strings.vaultLocalRecordCount(itemCount),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
              SecureStatusPill(
                icon: Icons.lock_rounded,
                label: strings.encryptedStatus,
                color: SecureVisualColors.blue,
              ),
              SecureStatusPill(
                icon: Icons.offline_bolt_outlined,
                label: strings.localFirstStatus,
                color: SecureVisualColors.success,
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
