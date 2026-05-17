# 安全性和可用性升级测试计划

**日期：** 2026-05-17

## 范围

本测试计划涵盖 `docs/superpowers/plans/2026-05-17-security-usability-upgrade.md` 中的执行计划。

它验证：

- 本地密码健康检查。
- 密码健康 UI 和底部导航。
- 密码生成器预设和密码短语模式。
- 敏感明文生命周期清理。
- 解锁冷却和更清晰的安全错误状态。
- 加密、保险库完整性、备份、剪贴板、生物识别回退和路由的回归覆盖。

## 测试策略

使用三层测试：

1. 纯服务的单元测试：
   - `PasswordHealthService`
   - `PasswordGenerator`
   - `ClipboardService`
   - `MasterPasswordPolicy`

2. 保险库行为的服务/集成测试：
   - `VaultService`
   - `BackupService`
   - 清单和回滚锚点交互

3. 面向用户流程的小组件件测试：
   - 设置/解锁
   - 保险库列表/详情/编辑
   - 生成器
   - 设置
   - 健康页面
   - 外壳导航

## 必需命令

每个任务后运行聚焦测试：

```powershell
flutter test --reporter compact test\core\security\password_health_service_test.dart
flutter test --reporter compact test\features\security_health_test.dart
flutter test --reporter compact test\core\password_generator\password_generator_test.dart
flutter test --reporter compact test\features\generator_settings_test.dart
flutter test --reporter compact test\features\vault_item_flow_test.dart
flutter test --reporter compact test\features\setup_unlock_test.dart
```

运行最终验证：

```powershell
flutter test --reporter compact
flutter analyze
```

## 密码健康测试矩阵

| 场景 | 测试文件 | 预期结果 |
| --- | --- | --- |
| 常见弱密码 | `test/core/security/password_health_service_test.dart` | 发现包含 `weak`，严重性为 `critical` |
| 两个条目间重复密码 | `test/core/security/password_health_service_test.dart` | 两个条目都包含 `reused`，严重性为 `critical` |
| 超过 365 天的密码 | `test/core/security/password_health_service_test.dart` | 发现包含 `stale`，严重性为 `warning`，除非也是弱/重复 |
| 密码包含标题/网站标记 | `test/core/security/password_health_service_test.dart` | 发现包含 `similarToTitleOrSite` |
| 强唯一近期密码 | `test/core/security/password_health_service_test.dart` | 无发现 |
| 发现字符串不包含明文密码 | `test/core/security/password_health_service_test.dart` | `finding.toString()` 排除密码 |
| 保险库健康分析需要已解锁保险库 | `test/core/vault/vault_service_test.dart` | 已锁定保险库抛出 `VaultLockedException` |
| 删除的条目被排除 | `test/core/vault/vault_service_test.dart` | 报告总数排除软删除行 |

## 健康页面测试矩阵

| 场景 | 测试文件 | 预期结果 |
| --- | --- | --- |
| 健康标签在底部导航可见 | `test/features/security_health_test.dart` | 找到 `vault-shell-health-tab` |
| 报告摘要可见 | `test/features/security_health_test.dart` | 显示总数、高风险数、提醒数 |
| 发现列表可见 | `test/features/security_health_test.dart` | 显示标题和本地化原因标签 |
| 空健康保险库 | `test/features/security_health_test.dart` | 显示无风险空状态 |
| 健康分析失败 | `test/features/security_health_test.dart` | 显示检查失败消息 |
| 下拉刷新 | `test/features/security_health_test.dart` | 再次调用分析 |

## 生成器测试矩阵

| 场景 | 测试文件 | 预期结果 |
| --- | --- | --- |
| 强预设 | `test/core/password_generator/password_generator_test.dart` | 24 字符，包含小写/大写/数字/符号 |
| 兼容预设 | `test/core/password_generator/password_generator_test.dart` | 20 字符，无符号 |
| 密码短语预设 | `test/core/password_generator/password_generator_test.dart` | 四个单词加数字 |
| 密码短语拒绝少于三个单词 | `test/core/password_generator/password_generator_test.dart` | 抛出 `PasswordGeneratorException` |
| UI 暴露预设 | `test/features/generator_settings_test.dart` | 显示 `强密码`、`密码短语`、`兼容网站` |
| UI 可以复制生成的密码 | `test/features/generator_settings_test.dart` | 显示复制成功 snackbar |
| UI 可以保存生成的密码 | `test/features/generator_settings_test.dart` | 导航到编辑页面并预填充密码 |
| 后台清除生成的密码 | `test/features/generator_settings_test.dart` | 暂停状态后生成的密钥消失 |

## 敏感明文生命周期测试矩阵

| 场景 | 测试文件 | 预期结果 |
| --- | --- | --- |
| 详情密码默认隐藏 | `test/features/vault_item_flow_test.dart` | 揭示前密码文本不存在 |
| 详情密码在应用后台时隐藏 | `test/features/vault_item_flow_test.dart` | `paused` 后密码文本不存在 |
| 详情密码在页面销毁时隐藏 | `test/features/vault_item_flow_test.dart` | 返回列表不会保留可见密钥 |
| 编辑在保存时清除密码控制器 | `test/features/vault_item_flow_test.dart` | 保存后密码控制器不再暴露旧值 |
| 编辑在取消/返回时清除敏感字段 | `test/features/vault_item_flow_test.dart` | 密码/笔记在弹出前清除 |
| 剪贴板在后台时清除密码 | `test/core/security/clipboard_and_lock_test.dart` | 待处理密码清除立即执行 |
| 用户名复制不安排密码清除 | `test/core/security/clipboard_and_lock_test.dart` | 无待处理密码清理 |

## 解锁和错误状态测试矩阵

| 场景 | 测试文件 | 预期结果 |
| --- | --- | --- |
| 错误主密码显示通用失败 | `test/features/setup_unlock_test.dart` | 无敏感技术细节 |
| 重复失败显示冷却 | `test/features/setup_unlock_test.dart` | 消息包含 `稍后` 和秒数 |
| 成功解锁重置冷却 | `test/features/setup_unlock_test.dart` | 重试状态清除 |
| 生物识别失败回退到主密码 | `test/features/setup_unlock_test.dart` | 主解锁表单保持可用 |
| 完整性失败锁定保险库 | `test/core/vault/vault_service_test.dart` | 失败后会话锁定 |

## 回归测试矩阵

| 区域 | 测试文件 |
| --- | --- |
| 加密和 KDF | `test/core/crypto/crypto_service_test.dart` |
| 保险库 CRUD 和明文缺失 | `test/core/vault/vault_service_test.dart` |
| 清单完整性 | `test/core/vault/vault_service_test.dart`、`test/core/vault/vault_service_anchor_test.dart` |
| 备份导入/导出 | `test/core/backup/backup_service_test.dart` |
| 剪贴板和自动锁定 | `test/core/security/clipboard_and_lock_test.dart` |
| 设置/解锁路由 | `test/app/app_routing_test.dart`、`test/features/setup_unlock_test.dart` |
| 生成器/设置 | `test/features/generator_settings_test.dart` |
| 保险库条目流程 | `test/features/vault_item_flow_test.dart` |
| Android 加固 | `test/android_integration_test.dart` |

## 手动 QA 检查清单

在自动化测试后在 Android 上手动运行：

- 使用强主密码创建新保险库。
- 尝试 `password123456` 作为主密码并确认它被拒绝。
- 添加三个条目：一个强、两个重复弱密码。
- 打开健康标签并确认重复/弱条目被标记为高风险。
- 揭示密码，进入后台，返回，确认保险库被锁定或密码被隐藏。
- 生成强密码，复制，等待配置的清理，确认剪贴板不再包含它。
- 生成密码短语并保存到新条目。
- 导出备份，导入到干净的本地保险库，确认条目解密。
- 启用生物识别解锁，锁定，用生物识别解锁，然后禁用生物识别。
- 更改主密码并确认旧密码不再解锁。

## 验收标准

- 使用 `flutter test --reporter compact` 运行完整自动化套件通过。
- 使用 `flutter analyze` 运行静态分析通过。
- 没有新的明文字段添加到 SQLite 模式。
- 没有引入网络权限、云同步、远程密码查找或明文搜索索引。
- 密码健康分析仅在已解锁的解密内存数据上运行。
- 生成的密码和揭示的密码在后台/锁定/销毁时被清除或隐藏。
- 面向用户的安全消息可操作而不暴露敏感内部信息。