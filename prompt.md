
# 任务目标

请开发一个「本地密码管理工具箱」MVP。  
这是一个本地优先的密码管理器，第一版只支持本地加密存储，暂不支持云同步。

核心目标：

1. 所有账号、用户名、密码、备注等敏感数据必须本地加密存储。
2. 用户通过主密码解锁密码库。
3. 支持生物识别快速解锁，但生物识别不能直接作为加密数据的唯一密钥。
4. 支持密码生成器。
5. 支持查看、复制用户名和密码。
6. 支持生成密码后直接进入保存页面。

---

# 技术原则

请优先保证安全性，不要只做 UI 原型。

必须遵守以下原则：

1. 不允许明文保存主密码。
2. 不允许明文保存账号密码。
3. 不允许使用硬编码加密密钥。
4. 不允许使用 MD5、SHA1 或普通 SHA256 直接处理主密码。
5. 不允许把密码、主密码、密钥写入日志。
6. 每条加密记录必须使用独立 nonce / iv。
7. 解密后的明文数据只应在内存中短暂存在。
8. App 进入后台或超时后应自动锁定。
9. 复制密码后应在一定时间后自动清空剪贴板。
10. 生物识别只能作为本机快速解锁方式，不能替代主密码的根权限。

---

# 推荐加密架构

请按以下密钥结构设计：

```text
用户主密码
   ↓ KDF 派生
KEK：Key Encryption Key
   ↓ 解密
DEK：Data Encryption Key
   ↓ 加密 / 解密
具体账号数据
````

说明：

* 主密码由用户记住，不保存。
* KEK 由主密码通过 KDF 派生。
* DEK 是随机生成的数据加密密钥。
* 所有密码条目使用 DEK 加密。
* 修改主密码时，只需要重新用新 KEK 加密 DEK，不需要重新加密所有账号数据。

KDF 优先使用：

```text
Argon2id
```

如果当前平台不方便使用 Argon2id，可以使用：

```text
PBKDF2-HMAC-SHA256
```

加密算法优先使用：

```text
AES-256-GCM
```

如果项目里更方便使用 libsodium，也可以使用：

```text
XChaCha20-Poly1305
```

---

# 生物识别设计

生物识别不能直接加密所有密码数据。

正确流程：

```text
用户第一次输入主密码解锁成功
   ↓
用户开启生物识别
   ↓
系统生成或读取本地安全区密钥
   ↓
用本地安全区密钥加密 DEK 的副本
   ↓
下次用户通过指纹 / Face ID 解锁
   ↓
解密 DEK
   ↓
进入密码库
```

要求：

1. 生物识别失败时，必须回退到主密码解锁。
2. 用户关闭生物识别时，应删除生物识别加密的 DEK 副本。
3. 用户修改主密码后，生物识别解锁能力应保持可用，或者重新初始化。
4. 用户重装 App、换设备、系统安全区失效时，必须依赖主密码恢复。

---

# 数据库存储

使用本地 SQLite。

请至少设计三张表：

## 1. vault_meta

用于保存密码库元信息。

字段建议：

```sql
CREATE TABLE vault_meta (
  id TEXT PRIMARY KEY,
  version INTEGER NOT NULL,
  kdf TEXT NOT NULL,
  kdf_params TEXT NOT NULL,
  salt TEXT NOT NULL,
  encrypted_dek_by_master TEXT NOT NULL,
  encrypted_dek_by_biometric TEXT,
  biometric_enabled INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

## 2. vault_items

用于保存加密后的密码条目。

```sql
CREATE TABLE vault_items (
  id TEXT PRIMARY KEY,
  nonce TEXT NOT NULL,
  ciphertext TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
```

## 3. settings

用于保存本地设置。

```sql
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

---

# 密码条目明文结构

加密前的密码条目可以使用以下结构：

```json
{
  "title": "GitHub",
  "website": "https://github.com",
  "username": "user@example.com",
  "password": "generated_password",
  "notes": "备用邮箱登录",
  "tags": ["开发", "重要"]
}
```

这些字段都应该被整体加密后存储到 `vault_items.ciphertext` 中。

---

# 页面需求

请实现以下页面。

## 1. 首次启动页

功能：

* 创建主密码
* 确认主密码
* 显示密码强度
* 提醒用户主密码无法找回
* 可选开启生物识别

提示文案：

```text
主密码不会上传，也无法找回。请务必牢记。
```

## 2. 解锁页

功能：

* 输入主密码解锁
* 支持生物识别解锁
* 解锁失败显示错误提示
* 多次失败后增加等待时间

## 3. 密码列表页

功能：

* 展示所有已保存密码条目
* 支持搜索
* 支持新增
* 支持进入详情页
* 不直接显示密码明文

列表建议显示：

```text
标题
用户名
更新时间
```

## 4. 新增 / 编辑密码页

字段：

* 标题
* 网站
* 用户名
* 密码
* 备注
* 标签

功能：

* 保存
* 删除
* 从密码生成器带入密码

## 5. 密码详情页

功能：

* 查看标题
* 查看网站
* 查看用户名
* 查看密码
* 密码默认隐藏
* 支持复制用户名
* 支持复制密码
* 支持编辑
* 支持删除

密码展示：

```text
••••••••••••••••
[显示] [复制]
```

## 6. 密码生成器页

功能：

* 设置密码长度
* 是否包含小写字母
* 是否包含大写字母
* 是否包含数字
* 是否包含特殊符号
* 是否排除易混字符
* 是否保证每类字符至少出现一个
* 一次生成多个候选密码
* 支持复制生成结果
* 支持点击「保存此密码」进入新增页面并自动填入密码

密码长度选项建议：

```text
8 / 12 / 16 / 24 / 32 / 64
```

字符组合建议：

```text
小写字母：abcdefghijklmnopqrstuvwxyz
大写字母：ABCDEFGHIJKLMNOPQRSTUVWXYZ
数字：0123456789
符号：!@#$%^&*()-_=+[]{};:,.<>?
易混字符：0 O o 1 l I
```

## 7. 设置页

功能：

* 修改主密码
* 开启 / 关闭生物识别
* 自动锁定时间
* 剪贴板自动清理时间
* 导出加密备份
* 导入加密备份
* 清空本地密码库

---

# 核心业务流程

## 初始化密码库

```text
用户设置主密码
   ↓
生成随机 salt
   ↓
通过 KDF 派生 KEK
   ↓
生成随机 DEK
   ↓
用 KEK 加密 DEK
   ↓
保存 vault_meta
```

## 主密码解锁

```text
用户输入主密码
   ↓
读取 salt 和 kdf_params
   ↓
派生 KEK
   ↓
尝试解密 encrypted_dek_by_master
   ↓
成功后获得 DEK
   ↓
进入密码列表
```

## 新增密码条目

```text
用户填写账号信息
   ↓
序列化为 JSON
   ↓
生成随机 nonce
   ↓
使用 DEK 加密 JSON
   ↓
保存 ciphertext 和 nonce
```

## 查看密码条目

```text
读取 vault_items
   ↓
使用 DEK 解密 ciphertext
   ↓
展示明文数据
```

## 修改主密码

```text
输入旧主密码
   ↓
解密 DEK
   ↓
输入新主密码
   ↓
生成新 salt
   ↓
派生新 KEK
   ↓
用新 KEK 重新加密 DEK
   ↓
更新 vault_meta
```

## 开启生物识别

```text
用户已通过主密码解锁
   ↓
请求系统生物识别授权
   ↓
生成或读取系统安全区密钥
   ↓
用该密钥加密 DEK 副本
   ↓
保存 encrypted_dek_by_biometric
```

## 生物识别解锁

```text
用户点击生物识别解锁
   ↓
系统验证指纹 / Face ID
   ↓
使用系统安全区密钥解密 encrypted_dek_by_biometric
   ↓
获得 DEK
   ↓
进入密码库
```

---

# 本地备份功能

第一版可以支持加密备份导出和导入。

导出文件格式建议：

```json
{
  "version": 1,
  "kdf": "argon2id",
  "kdf_params": {},
  "salt": "...",
  "encrypted_dek_by_master": "...",
  "items": [
    {
      "id": "...",
      "nonce": "...",
      "ciphertext": "..."
    }
  ]
}
```

备份文件扩展名建议：

```text
.mvault
```

导出文件名示例：

```text
moonix-vault-backup-2026-05-12.mvault
```

导入时要求：

1. 校验文件格式。
2. 校验版本。
3. 要求用户输入主密码。
4. 成功解密后再导入。
5. 遇到重复数据时提示覆盖、跳过或合并。

---

# 自动锁定要求

请实现以下安全行为：

1. App 进入后台后自动锁定。
2. 用户长时间无操作后自动锁定。
3. 解锁状态不要长期保留。
4. 任务切换预览页应隐藏敏感内容。
5. 密码复制后自动清理剪贴板。
6. 连续输入错误主密码后增加等待时间。

自动锁定时间配置：

```text
立即
30 秒
1 分钟
5 分钟
15 分钟
```

剪贴板清理时间配置：

```text
15 秒
30 秒
60 秒
永不
```

默认建议：

```text
自动锁定：1 分钟
剪贴板清理：30 秒
```

---

# 测试要求

请至少添加以下测试：

## 加密测试

1. 相同明文多次加密，ciphertext 应不同。
2. 错误主密码无法解密 DEK。
3. 正确主密码可以解密 DEK。
4. 每条记录 nonce 不重复。
5. 修改主密码后，旧主密码不能解锁，新主密码可以解锁。

## 密码生成测试

1. 指定长度必须准确。
2. 开启数字时结果应包含数字。
3. 开启大写时结果应包含大写。
4. 开启小写时结果应包含小写。
5. 开启符号时结果应包含符号。
6. 排除易混字符后，结果不能包含易混字符。
7. 必须包含每类字符时，每类至少出现一个。

## 数据库测试

1. 新增条目成功。
2. 编辑条目成功。
3. 删除条目成功。
4. 解密后数据与保存前一致。
5. 数据库中不能出现明文密码。

## 生物识别测试

1. 开启生物识别后可以通过生物识别解锁。
2. 生物识别失败后回退主密码。
3. 关闭生物识别后不能再使用生物识别解锁。
4. 删除 biometric encrypted DEK 后，主密码仍可正常解锁。

---

# 代码组织建议

**请使用Flutter开发。**

请按模块拆分，不要把所有逻辑写在页面里。

建议目录：

```text
lib/
  core/
    crypto/
      kdf_service.dart
      crypto_service.dart
      secure_random.dart
    vault/
      vault_service.dart
      vault_session.dart
      vault_repository.dart
    biometric/
      biometric_service.dart
    clipboard/
      clipboard_service.dart
    security/
      auto_lock_service.dart
      app_lifecycle_guard.dart
  data/
    db/
      app_database.dart
      vault_meta_dao.dart
      vault_items_dao.dart
    models/
      vault_item.dart
      vault_meta.dart
      password_entry.dart
  features/
    setup/
    unlock/
    vault_list/
    vault_detail/
    vault_edit/
    password_generator/
    settings/
  shared/
    widgets/
    utils/
```

---

# UI 要求

UI 风格要求：

1. 简洁、克制、安全感。
2. 不要花哨，不要游戏化。
3. 密码默认隐藏。
4. 复制操作要有明确反馈。
5. 删除操作必须二次确认。
6. 危险操作使用醒目提示。
7. 首次设置主密码时必须强调不可找回。

主要页面文案使用中文。

---

# 开发顺序

请按以下顺序实现：

1. 项目基础结构。
2. SQLite 数据库。
3. KDF 和加密服务。
4. vault 初始化。
5. 主密码解锁。
6. vault session 管理。
7. 新增 / 查看 / 编辑 / 删除密码条目。
8. 密码生成器。
9. 复制用户名和密码。
10. 自动锁定。
11. 生物识别解锁。
12. 加密备份导入导出。
13. 测试。
14. 安全检查和代码整理。

---

# 最小可运行版本验收标准

完成后应满足：

1. 用户首次打开 App 可以创建主密码。
2. 关闭 App 后再次打开需要解锁。
3. 可以新增一条密码记录。
4. 数据库里看不到明文密码。
5. 可以查看密码详情。
6. 可以复制用户名和密码。
7. 可以使用密码生成器生成密码。
8. 生成密码后可以直接保存。
9. 可以修改主密码。
10. 可以开启生物识别快速解锁。
11. App 进入后台后会自动锁定。
12. 复制密码后会自动清理剪贴板。
13. 基础单元测试通过。

---