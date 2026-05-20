# 标签筛选与管理 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为密码库添加标签筛选栏和标签管理功能，支持点击 chip 筛选、标签重命名/删除。

**Architecture:** 修改 vault_list_page 添加标签 chip 栏；新增 tag_management_page；VaultService 新增标签操作方法（从已有条目提取标签、重命名、删除）。

**Tech Stack:** Flutter 3.x, Dart 3.11, Material 3, sqflite, 现有 SecureVisual 组件

**Spec:** `docs/superpowers/specs/2026-05-21-tag-filtering-design.md`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `lib/features/vault_list/vault_list_page.dart` | Modify | 添加标签筛选栏 |
| `lib/features/tag_management/tag_management_page.dart` | Create | 标签管理页面 |
| `lib/features/settings/settings_page.dart` | Modify | 添加标签管理入口 |
| `lib/core/vault/vault_service.dart` | Modify | 标签操作 API |
| `lib/app/app_services.dart` | Modify | 暴露标签操作 API |

---

### Task 1: VaultService + AppServices 标签 API

**Files:**
- Modify: `lib/core/vault/vault_service.dart`
- Modify: `lib/app/app_services.dart`

- [ ] **Step 1: VaultService 添加标签方法**

```dart
// In vault_service.dart

Future<List<String>> allTags() async {
  _ensureUnlocked();
  final items = await repository.itemsDao.allItemsForManifest();
  final active = items.where((i) => i.deletedAt == null).toList();
  final tags = <String>{};
  for (final item in active) {
    final entry = _decryptItemAsEntry(item, await _session.dekCopy());
    tags.addAll(entry.tags);
  }
  return tags.toList()..sort();
}

Future<void> renameTag(String oldTag, String newTag) async {
  _ensureUnlocked();
  // Need per-item update — read, modify, re-encrypt, save
  final items = await repository.itemsDao.allItemsForManifest();
  // Decrypt all, find those with oldTag, replace with newTag, save
}

Future<void> deleteTag(String tag) async {
  // Similar to rename, but remove tag from all items
}
```

Note: The exact implementation depends on how VaultRepository exposes per-item update. Use the existing `mutate` pattern or per-item read/write.

- [ ] **Step 2: AppServices 暴露 API**

```dart
Future<List<String>> allTags() async => vaultService.allTags();
Future<void> renameTag(String oldTag, String newTag) async => vaultService.renameTag(oldTag, newTag);
Future<void> deleteTag(String tag) async => vaultService.deleteTag(tag);
```

- [ ] **Step 3: Commit**

```bash
git add lib/core/vault/vault_service.dart lib/app/app_services.dart
git commit -m "feat: add tag CRUD APIs to VaultService"
```

---

### Task 2: VaultListPage 标签筛选栏

**Files:**
- Modify: `lib/features/vault_list/vault_list_page.dart`

- [ ] **Step 1: 添加标签状态和加载逻辑**

In `_VaultListPageState`:

```dart
  List<String> _allTags = [];
  String? _selectedTag;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadTags();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await widget.services.allTags();
      if (!mounted) return;
      setState(() => _allTags = tags);
    } catch (_) {}
  }
```

- [ ] **Step 2: 添加标签 Chip 栏到 build 方法**

After search box, before the list, add:

```dart
if (_allTags.isNotEmpty) ...[
  const SizedBox(height: 12),
  SizedBox(
    height: 36,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _allTags.length + 1, // +1 for "全部"
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          final selected = _selectedTag == null;
          return FilterChip(
            selected: selected,
            label: const Text('全部', style: TextStyle(fontSize: 12)),
            onSelected: (_) => setState(() => _selectedTag = null),
            selectedColor: SecureVisualColors.blue.withValues(alpha: 0.15),
            checkmarkColor: SecureVisualColors.blue,
          );
        }
        final tag = _allTags[index - 1];
        final selected = _selectedTag == tag;
        return FilterChip(
          selected: selected,
          label: Text(tag, style: const TextStyle(fontSize: 12)),
          onSelected: selected
              ? (_) => setState(() => _selectedTag = null)
              : (_) => setState(() => _selectedTag = tag),
          selectedColor: SecureVisualColors.blue.withValues(alpha: 0.15),
          checkmarkColor: SecureVisualColors.blue,
        );
      },
    ),
  ),
]
```

- [ ] **Step 3: 修改 _loadItems 支持标签筛选**

```dart
  Future<void> _loadItems() async {
    // ... existing code ...
    final query = '${_searchController.text} ${_selectedTag ?? ''}'.trim();
    final items = await widget.services.listVaultItems(query: query);
    // ...
  }
```

If `listVaultItems` doesn't support tag filtering yet, filter client-side:

```dart
  Future<void> _loadItems() async {
    // ... get items ...
    var filtered = items;
    if (_selectedTag != null) {
      // Need to get full entries to check tags. 
      // For efficiency, filter by decrypting and checking tags.
      filtered = ...;
    }
    // ...
  }
```

The simplest approach: pass `_selectedTag` as part of the query string, or do client-side filtering after getting items.

- [ ] **Step 4: 标签变更后刷新**

After `_loadItems()` completes in `_handleAdd` and `_openDetail`, also call `_loadTags()`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/vault_list/vault_list_page.dart
git commit -m "feat: add tag filter chips to vault list"
```

---

### Task 3: 标签管理页面

**Files:**
- Create: `lib/features/tag_management/tag_management_page.dart`

- [ ] **Step 1: 创建标签管理页面**

```dart
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
      setState(() { _tags = tags; _isLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('标签管理')),
      body: SecureVisualBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _tags.isEmpty
                ? const Center(child: Text('暂无标签'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _tags.length,
                    itemBuilder: (context, index) {
                      final tag = _tags[index];
                      return ListTile(
                        title: Text(tag),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _showRenameDialog(tag),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _showDeleteDialog(tag),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  void _showRenameDialog(String oldTag) { ... }
  void _showDeleteDialog(String tag) { ... }
}
```

- [ ] **Step 2: 实现重命名和删除对话框**

```dart
  void _showRenameDialog(String oldTag) {
    final controller = TextEditingController(text: oldTag);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () async {
            final newTag = controller.text.trim();
            if (newTag.isEmpty || newTag == oldTag) { Navigator.pop(ctx); return; }
            try {
              await widget.services.renameTag(oldTag, newTag);
              if (!mounted) return;
              Navigator.pop(ctx);
              _load();
            } catch (_) {
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('重命名失败')));
            }
          }, child: const Text('确认')),
        ],
      ),
    );
  }

  void _showDeleteDialog(String tag) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('将从所有条目中移除"$tag"标签'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              try {
                await widget.services.deleteTag(tag);
                if (!mounted) return;
                Navigator.pop(ctx);
                _load();
              } catch (_) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('删除失败')));
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/tag_management/tag_management_page.dart
git commit -m "feat: add tag management page"
```

---

### Task 4: 设置页添加入口

**Files:**
- Modify: `lib/features/settings/settings_page.dart`

- [ ] **Step 1: 添加标签管理 ListTile**

Add import: `import 'package:secure_box/features/tag_management/tag_management_page.dart';`

Add ListTile in settings list (near the health entry):

```dart
ListTile(
  leading: Container(
    width: 44, height: 44,
    decoration: BoxDecoration(
      color: SecureVisualColors.blue.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Icon(Icons.sell_outlined),
  ),
  title: const Text('标签管理'),
  subtitle: const Text('管理密码库标签'),
  trailing: const Icon(Icons.chevron_right_rounded),
  onTap: () {
    widget.services.recordActivity();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TagManagementPage(services: widget.services),
      ),
    );
  },
),
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/settings/settings_page.dart
git commit -m "feat: add tag management entry to settings"
```

---

### Task 5: 端到端验证

- [ ] **Step 1: Run tests + analyze**

```bash
flutter test --reporter compact
flutter analyze
```

- [ ] **Step 2: Build APK**

```bash
flutter build apk --debug
```

- [ ] **Step 3: Commit**

```bash
git commit -m "chore: finalize tag filtering feature" --allow-empty
```