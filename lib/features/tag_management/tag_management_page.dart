import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_dialog.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class TagManagementPage extends StatefulWidget {
  const TagManagementPage({super.key, required this.services});

  final AppServices services;

  @override
  State<TagManagementPage> createState() => _TagManagementPageState();
}

class _TagManagementPageState extends State<TagManagementPage> {
  List<String> _tags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final tags = await widget.services.allTags();
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SecureVisualBackground(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: Column(
        children: [
          SecureReplicaHeader(
            title: strings.text('tagManagementTitle'),
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _tags.isEmpty
                ? const _EmptyTags()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
                    itemCount: _tags.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final tag = _tags[index];
                      return _TagTile(
                        tag: tag,
                        onRename: () => _showRenameDialog(tag),
                        onDelete: () => _showDeleteDialog(tag),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(String oldTag) {
    final controller = TextEditingController(text: oldTag);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final strings = AppStrings.of(ctx);
        return SecureDialog(
          icon: Icons.edit_rounded,
          title: strings.text('renameTag'),
          actions: [
            SecureDialogAction.primary(
              label: strings.text('confirm'),
              icon: Icons.check_rounded,
              onPressed: () async {
                final navigator = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(ctx);
                final newTag = controller.text.trim();
                if (newTag.isEmpty || newTag == oldTag) {
                  navigator.pop();
                  return;
                }
                try {
                  await widget.services.renameTag(oldTag, newTag);
                  if (!mounted) return;
                  navigator.pop();
                  _load();
                } catch (_) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text(strings.text('renameFailed'))),
                  );
                }
              },
            ),
            SecureDialogAction.cancel(ctx),
          ],
          child: TextField(
            controller: controller,
            autofocus: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(labelText: strings.text('newTagName')),
          ),
        );
      },
    ).whenComplete(() {
      controller.clear();
      controller.dispose();
    });
  }

  void _showDeleteDialog(String tag) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final strings = AppStrings.of(ctx);
        return SecureDialog(
          icon: Icons.label_off_rounded,
          title: strings.text('deleteTag'),
          message:
              '${strings.text('deleteTagMessagePrefix')} "$tag" ${strings.text('deleteTagMessageSuffix')}',
          destructive: true,
          actions: [
            SecureDialogAction.destructive(
              label: strings.text('delete'),
              icon: Icons.delete_outline_rounded,
              onPressed: () async {
                final navigator = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(ctx);
                try {
                  await widget.services.deleteTag(tag);
                  if (!mounted) return;
                  navigator.pop();
                  _load();
                } catch (_) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text(strings.text('deleteFailed'))),
                  );
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

class _TagTile extends StatelessWidget {
  const _TagTile({
    required this.tag,
    required this.onRename,
    required this.onDelete,
  });

  final String tag;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SecureGlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      borderRadius: 22,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: SecureVisualColors.blue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.sell_outlined,
              size: 24,
              color: SecureVisualColors.blue,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: SecureVisualColors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: strings.text('rename'),
            onPressed: onRename,
            icon: const Icon(
              Icons.edit_rounded,
              color: SecureVisualColors.blue,
            ),
          ),
          IconButton(
            tooltip: strings.text('delete'),
            onPressed: onDelete,
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTags extends StatelessWidget {
  const _EmptyTags();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SecureGlassCard(
        borderRadius: 26,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SecureIconBadge(icon: Icons.sell_outlined),
            const SizedBox(height: 16),
            Text(
              AppStrings.of(context).text('emptyTags'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}
