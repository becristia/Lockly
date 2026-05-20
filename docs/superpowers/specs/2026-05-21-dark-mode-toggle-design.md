# 暗色模式手动切换 — 设计说明

**日期：** 2026-05-21

## 概述

在设置页添加主题切换：浅色/深色/跟随系统，切换即时生效。

## 实现

- 设置页"主题"段：`SegmentedButton` 或三个 `RadioListTile`
- 选项：浅色 / 深色 / 跟随系统
- 持久化到 `SettingsDAO`（现有 shared_preferences 或 SQLite）
- 切换时通过 `ValueNotifier<ThemeMode>` 即时通知 MaterialApp 重建

## 文件

| 文件 | 操作 |
|------|------|
| `lib/app/app.dart` | 修改 — ThemeMode 改为动态 |
| `lib/features/settings/settings_page.dart` | 修改 — 添加主题切换 |
| `lib/app/app_services.dart` | 修改 — 暴露 themeMode get/set |

## 验收

- 三选一切换即时生效
- 关闭 App 重开后记住选择