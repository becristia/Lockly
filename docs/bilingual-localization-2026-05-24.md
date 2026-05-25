# Lockly 双语本地化落地记录

日期：2026-05-24

## 目标

- 设置页提供中文 / English 切换入口。
- 前端可见固定文案集中到 `AppStringsZh` 与 `AppStringsEn`。
- 页面切换语言时即时刷新，不改变密码库加密、主密码、同步密钥逻辑。
- 增加静态防回归测试，避免新增页面重新写入硬编码显示文本。

## 实现

- 新增 `lib/shared/i18n/`：
  - `app_language.dart`：语言枚举与解析。
  - `app_strings.dart`：统一文案接口与页面读取入口。
  - `app_strings_zh.dart`：中文文案实现。
  - `app_strings_en.dart`：英文文案实现。
  - `app_strings_scope.dart`：通过 inherited scope 向页面提供当前文案。
  - `password_policy_strings.dart`：将主密码策略的核心结果映射到当前界面语言。
- `AppServices` 持有 `languageNotifier`，`SecureBoxApp` 通过 `AppStringsScope` 包裹应用。
- 设置、解锁、初始化、密码库、详情、编辑、生成器、迁移、回收站、标签、安全中心、应急访问等页面已改为读取 `AppStrings`。
- 设置页新增语言切换控件，并保持默认中文。
- 主密码策略校验本身不改动，仅在 UI 层把策略结果映射成当前语言，避免影响安全逻辑。

## 防回归

- `test/ui/localization_test.dart` 覆盖：
  - 语言解析默认中文。
  - 设置页中文 / 英文切换。
  - `AppStringsScope` 暴露当前语言。
  - `lib/features`、`lib/app`、`lib/shared/widgets` 中常见可见文案入口不得再出现硬编码字符串，包括 `Text`、输入框标签、按钮标签、snack、failure message、云同步状态等。

## 验证记录

- `flutter test --reporter compact test\ui\localization_test.dart`
- `flutter test --reporter compact test\ui\visual_system_test.dart test\features\generator_settings_test.dart test\features\setup_unlock_test.dart test\features\vault_item_flow_test.dart`

以上命令已在本轮通过；最终交付前仍需再执行全量 `flutter analyze` 与 `flutter test --reporter compact`。
