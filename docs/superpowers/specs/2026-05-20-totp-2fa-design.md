# TOTP 二次验证码 — 设计说明

**日期：** 2026-05-20

## 概述

在 Lockly 中添加 TOTP（基于时间的一次性密码，RFC 6238）二次验证码生成功能。用户可将 TOTP 密钥绑定到密码条目，在应用内查看动态验证码。

## 数据模型

### PasswordEntry 扩展

在 `PasswordEntry` 中新增可选字段：

```dart
final String? totpSecret;  // Base32 编码的 TOTP 密钥，null 表示未启用
```

该字段与其他敏感字段（password、notes）一样通过 AES-256-GCM 加密后存入 SQLite。`toJson()`/`fromJson()` 相应扩展。

## 导航

底部导航栏新增第 4 个 Tab："验证码"。

```
密码库 | 生成器 | 验证码 | 设置
```

仅当保险库已解锁时显示（与其他 Tab 一致）。

## TOTP 页面

### 布局

2 列自适应卡片网格（`SliverGrid`），每张卡片显示：
- 圆形倒计时进度环（外圈色：绿 > 10s / 黄 > 5s / 红 ≤ 5s）
- 6 位或 8 位验证码（等宽字体，24px，字间距 4px）
- 条目标题
- 用户名
- 剩余秒数文本
- 点击卡片复制验证码到剪贴板，SnackBar 反馈

### 数据来源

遍历所有活跃条目，筛选 `totpSecret != null` 的条目。30 秒定时器驱动倒计时和码值刷新。

如果无 TOTP 条目，显示空状态："暂无疑问验证码条目" + 引导文字。

## 密钥设置

### 方式 1：二维码扫描

在编辑页新增"扫描 QR 码"入口：
- 调用摄像头扫描 QR 码
- 解析 `otpauth://totp/...` URL，提取 secret / issuer / label
- 自动填充 totpSecret 字段（Base32 密钥）
- 可选：自动设置标题（如果新建条目）

### 方式 2：手动输入

在编辑页输入框供用户粘贴 Base32 密钥：
- `TextFormField`，单行输入
- 自动过滤空格和非法字符
- 使用 `RegExp(r'[A-Za-z2-7]+')` 校验 Base32 格式

### UI 布局

编辑页密码字段下方新增"TOTP 二次验证"区域：
- 如果 `totpSecret == null`：显示"扫描 QR 码"和"手动输入密钥"两个操作入口
- 如果 `totpSecret != null`：显示当前动态码预览 + 编辑/删除按钮

## TOTP 算法

### 依赖

使用 `otp` 包（pub.dev package:otp），支持 HOTP/TOTP RFC 6238。

```yaml
dependencies:
  otp: ^3.1.4
```

### 参数

- 默认周期：30 秒
- 默认位数：6 位
- 默认算法：SHA1（可通过 `otpauth://` URL 覆盖为 SHA256/SHA512）
- 密钥编码：Base32

### 生成逻辑

```dart
String generateTotp(String base32Secret, {int digits = 6, int period = 30}) {
  return OTP.generateTOTPCodeString(
    base32Secret,
    DateTime.now().millisecondsSinceEpoch,
    length: digits,
    interval: period,
  );
}
```

## 文件地图

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/data/models/password_entry.dart` | 修改 | 添加 totpSecret 字段 |
| `lib/core/password_generator/totp_service.dart` | 新建 | TOTP 码生成服务 |
| `lib/features/totp/totp_page.dart` | 新建 | 验证码卡片网格页面 |
| `lib/features/vault_shell/vault_shell_page.dart` | 修改 | 添加第 4 个 Tab |
| `lib/features/vault_edit/vault_edit_page.dart` | 修改 | 添加 TOTP 密钥设置 UI |
| `lib/features/vault_detail/vault_detail_page.dart` | 修改 | 查看条目时显示验证码 |
| `test/core/password_generator/totp_service_test.dart` | 新建 | TOTP 单元测试 |
| `test/features/totp_test.dart` | 新建 | TOTP 页面 widget 测试 |
| `pubspec.yaml` | 修改 | 添加 otp 依赖 |

## 视觉效果

- 卡片：深色圆角背景，`SecureGlassCard` 风格
- 验证码数字：24px 等宽粗体，字间距 4px，白色
- 倒计时环：外圈 `CircularProgressIndicator`，颜色动态切换
- 空状态：居中图标 + 提示文字
- 复制反馈：SnackBar "验证码已复制"

## 测试矩阵

| 场景 | 预期结果 |
|------|----------|
| 生成 6 位 TOTP 码 | 返回 6 位数字字符串 |
| 30 秒内生成相同码 | 同一周期内返回相同值 |
| 无效 Base32 密钥 | 抛出异常 |
| 空 TOTP 条目列表 | 显示空状态 |
| 点击卡片复制 | 剪贴板包含验证码，SnackBar 弹出 |
| 扫码解析 otpauth URL | 正确提取 secret、label、issuer |
| 手动输入非法字符 | 过滤后仅保留 Base32 字符 |
| 倒计时 < 10s 变色 | 剩余时间 ≤ 10s 时倒计时环变黄，≤ 5s 变红 |

## 验收标准

- `flutter test` 全量通过
- `flutter analyze` 静态分析通过
- TOTP 码与 Google Authenticator 输出一致
- totpSecret 加密存储，不落明文
- 底部导航 4 个 Tab 正常切换
- 扫码和手动输入两种方式均可设置密钥