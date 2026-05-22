import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
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
    return SecureVisualBackground(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: Column(
        children: [
          SecureReplicaHeader(
            title: '标签管理',
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '新标签名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
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
                messenger.showSnackBar(const SnackBar(content: Text('重命名失败')));
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(String tag) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('将从所有条目中移除 "$tag" 标签'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
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
                messenger.showSnackBar(const SnackBar(content: Text('删除失败')));
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
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
            tooltip: '重命名',
            onPressed: onRename,
            icon: const Icon(
              Icons.edit_rounded,
              color: SecureVisualColors.blue,
            ),
          ),
          IconButton(
            tooltip: '删除',
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
            Text('暂无标签', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
