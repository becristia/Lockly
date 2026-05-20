# 密码历史记录 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为密码条目添加历史记录，保存最多5个旧密码，支持在详情页查看和恢复。

**Architecture:** 新增 `password_history` SQLite 表 + `PasswordHistoryDao`；`VaultService` 修改密码时自动归档旧密码，新增 `listPasswordHistory`/`restorePassword` API；详情页底部时间线。

**Tech Stack:** Flutter 3.x, Dart 3.11, sqflite, AES-256-GCM

**Spec:** `docs/superpowers/specs/2026-05-21-password-history-design.md`

---

### Task 1: DB Schema + DAO + VaultService

**Files:**
- Modify: `lib/data/db/app_database.dart`
- Create: `lib/data/db/password_history_dao.dart`
- Modify: `lib/core/vault/vault_service.dart`
- Modify: `lib/app/app_services.dart`

**Step 1: 升级 schema v3，创建 password_history 表**

Read `lib/data/db/app_database.dart`. Change schemaVersion to 3, add:

```dart
static const int schemaVersion = 3;

// in onUpgrade:
if (oldVersion < 3) {
  await db.execute('''
    CREATE TABLE password_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_id TEXT NOT NULL,
      encrypted_password TEXT NOT NULL,
      password_nonce TEXT NOT NULL,
      recorded_at INTEGER NOT NULL,
      FOREIGN KEY (entry_id) REFERENCES vault_items(id) ON DELETE CASCADE
    )
  ''');
}
```

**Step 2: 创建 PasswordHistoryDao**

Read existing DAO patterns (`vault_items_dao.dart`). Implement standard sqflite CRUD.

**Step 3: VaultService 集成**

Modify the item update/create method where password changes to archive the old password. Add `listPasswordHistory(entryId)` and `restorePassword(entryId, historyId)` methods.

**Step 4: AppServices 暴露 API**

**Commit:** Commit per step.

---

### Task 2: 详情页历史时间线

**Files:**
- Modify: `lib/features/vault_detail/vault_detail_page.dart`

Read existing detail page. Add password history section below password field:
- Foldable "密码历史 (N)" section
- Timeline list with relative dates
- "揭示" toggle per entry + "恢复" button
- Restore confirmation dialog

**Commit:** `feat: add password history timeline to detail page`

---

### Task 3: E2E verification

```bash
flutter analyze && flutter build apk --debug
```

**Commit:** `chore: finalize password history feature`