# 密码历史记录 — 设计说明

**日期：** 2026-05-21

## 概述

为每个密码条目保留最多 5 次历史密码（包括当前密码恢复时归档的旧密码），在详情页展示时间线，支持一键恢复。

## 数据模型

### 新表：`password_history`

```sql
CREATE TABLE password_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entry_id TEXT NOT NULL,
  encrypted_password TEXT NOT NULL,
  password_nonce TEXT NOT NULL,
  recorded_at INTEGER NOT NULL,
  FOREIGN KEY (entry_id) REFERENCES vault_items(id) ON DELETE CASCADE
);
```

- 上限：每个 `entry_id` 最多 5 条，超出时删最旧的
- CASCADE：条目永久删除时历史自动清除

### 行为

- 修改密码时：旧密码自动归档到历史表
- 恢复历史密码时：当前密码归档到历史表，历史密码变为当前密码（并从历史表删除该条）
- 查看历史时：需要 DEK 解密

## UI

### 详情页底部

密码详情页密码字段下方新增"密码历史"区域：
- 时间线列表，最新在上
- 每条显示：修改日期（相对时间）、加密的旧密码（揭示按钮）、"恢复"按钮
- 初始折叠，点击展开
- 恢复需确认对话框

## 数据流

```
修改密码 → 旧密码加密 → INSERT INTO password_history (最多5条)
恢复密码 → 旧历史记录取出 → 解密 → 设为当前 → 当前密码归入历史
查看历史 → SELECT by entry_id → 解密 → 渲染时间线
```

## 文件地图

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/data/db/app_database.dart` | 修改 | schema v3，新增 password_history 表 |
| `lib/data/db/password_history_dao.dart` | 新建 | 历史记录 CRUD |
| `lib/core/vault/vault_service.dart` | 修改 | 修改密码时归档历史，添加恢复 API |
| `lib/features/vault_detail/vault_detail_page.dart` | 修改 | 详情页底部时间线 |
| `lib/app/app_services.dart` | 修改 | 暴露历史 API |

## 测试矩阵

| 场景 | 预期结果 |
|------|----------|
| 修改密码 | 旧密码出现在历史列表 |
| 历史超过 5 条 | 最旧记录自动删除 |
| 恢复历史密码 | 当前密码归档，历史密码恢复 |
| 条目永久删除 | 关联历史自动清除 |

## 验收标准

- 新密码历史不落明文
- 历史密码用独立 nonce 加密
- 恢复后条目可正常使用新（旧）密码
- schema 升级不丢现有数据