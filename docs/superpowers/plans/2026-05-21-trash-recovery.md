# 回收站与恢复 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为密码库添加回收站，支持查看已删除条目、恢复、永久删除和全部清空。

**Architecture:** 利用现有 `deletedAt` 字段筛选已删除条目；VaultService 新增 `listDeletedItems`/`restoreItem`/`permanentlyDelete`/`emptyTrash`；新增 TrashPage；密码库列表底部 Footer 入口。

**Tech Stack:** Flutter 3.x, Dart 3.11, 现有组件

**Spec:** `docs/superpowers/specs/2026-05-21-trash-recovery-design.md`

---

### Task 1: VaultService + AppServices 回收站 API

**Files:**
- Modify: `lib/core/vault/vault_service.dart`
- Modify: `lib/app/app_services.dart`

**VaultService additions:**

```dart
// List all soft-deleted items (VaultListItem already has necessary fields from DB)
Future<List<VaultListItem>> listDeletedItems() async {
  _ensureUnlocked();
  final items = await repository.itemsDao.allItemsForManifest();
  return items.where((i) => i.deletedAt != null).map((i) => VaultListItem(
    id: i.id,
    title: _decryptItemTitle(i), 
    website: '',
    username: '',
    tags: [],
    createdAt: i.createdAt,
    updatedAt: i.deletedAt!,
  )).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

Future<void> restoreItem(String id) async {
  // Clear deletedAt — use existing updateItem pattern or direct DAO call
}

Future<void> permanentlyDeleteItem(String id) async {
  // Hard DELETE from items table
}

Future<void> emptyTrash() async {
  // DELETE all items where deletedAt IS NOT NULL
}
```

Note: Check existing `repository.itemsDao` for available methods. Read `lib/data/db/vault_items_dao.dart` to find hard-delete methods.

**AppServices:** Passthrough methods for all 4 APIs.

**Commit:** `feat: add trash CRUD APIs`

---

### Task 2: TrashPage UI

**Files:**
- Create: `lib/features/trash/trash_page.dart`

TrashPage 列出已删除条目，每个条目有恢复和永久删除按钮。底部"全部清空"按钮。

```dart
class TrashPage extends StatefulWidget {
  const TrashPage({super.key, required this.services});
  final AppServices services;
  // ...State with ListView, Dismissible for swipe actions, bottom Clear All button
}
```

**Commit:** `feat: add trash page`

---

### Task 3: VaultListPage Footer 入口

**Files:**
- Modify: `lib/features/vault_list/vault_list_page.dart`

在列表底部添加 Footer（仅当已删除条目 > 0 时显示）:

```dart
if (_deletedCount > 0)
  ListTile(
    leading: Icon(Icons.delete_outline_rounded),
    title: Text('回收站 ($_deletedCount 条)'),
    trailing: Icon(Icons.chevron_right),
    onTap: () => Navigator.push(TrashPage),
  )
```

**Commit:** `feat: add trash entry footer to vault list`

---

### Task 4: E2E verification

```bash
flutter analyze && flutter test --reporter compact && flutter build apk --debug
```