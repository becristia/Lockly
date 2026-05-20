# 回收站与恢复 — 设计说明

**日期：** 2026-05-21

## 概述

为密码库添加回收站功能。数据层已有 `softDelete`（`deletedAt` 字段），可恢复或永久删除已删除条目。

## 入口

密码库列表底部 Footer：显示已删除条目计数，点击导航到回收站页面。

仅当存在已删除条目时显示 Footer。

## 回收站页面

- 列出所有已删除条目（按删除时间倒序）
- 每个条目显示：标题、用户名、删除时间（相对时间）
- 左滑或长按显示操作：恢复 / 永久删除
- 支持"全部清空"操作（底部按钮，需二次确认）
- 30天后自动永久删除

## 交互

- **恢复**：清除 `deletedAt`，条目回到密码库列表。确认 SnackBar "已恢复"，带"撤销"按钮（重新软删除）
- **永久删除**：二次确认对话框后硬删除（DELETE FROM items WHERE id = ?），不可恢复
- **全部清空**：二次确认后删除所有已删除条目

## 数据流

```
VaultService.listDeletedItems() → 回收站列表
VaultService.restoreItem(id) → 恢复单条
VaultService.permanentlyDeleteItem(id) → 永久删除
VaultService.emptyTrash() → 清空回收站
```

## 文件地图

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/features/trash/trash_page.dart` | 新建 | 回收站页面 |
| `lib/features/vault_list/vault_list_page.dart` | 修改 | 添加 Footer 入口 |
| `lib/core/vault/vault_service.dart` | 修改 | 添加回收站 API |
| `lib/app/app_services.dart` | 修改 | 暴露回收站 API |

## 测试矩阵

| 场景 | 预期结果 |
|------|----------|
| 删除条目后出现在回收站 | 列表显示已删除条目 |
| 恢复条目 | 条目回到密码库，回收站不显示 |
| 永久删除 | 条目完全移除，不可恢复 |
| 清空回收站 | 所有软删除条目永久删除 |
| 无已删除条目 | Footer 隐藏 |

## 验收标准

- `flutter test` 通过
- `flutter analyze` 通过
- 恢复/永久删除/清空功能正常
- 空回收站无 Footer 显示