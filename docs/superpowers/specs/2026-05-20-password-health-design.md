# 密码健康检测 — 设计说明

**日期：** 2026-05-20

## 概述

在 Lockly 中添加本地密码健康分析功能。所有分析仅在保险库解锁后在解密内存数据上运行，不持久化任何明文索引，不调用远程 API。

## 导航

在设置页添加"密码健康"入口，点击导航到独立的健康报告页面。

```
设置页 → 密码健康入口 → 健康报告页 → 展开分类 → 条目详情
```

## 页面结构

### 健康仪表盘（主页）

1. **健康评分卡片** — 蓝绿渐变背景，大数字 0-100 综合评分
2. **统计行** — 三列：高风险数（红）、提醒数（橙）、健康数（绿）
3. **分类列表** — 5 个可折叠面板，按严重度排序，左侧色条 + 右上角计数标记

### 展开详情页

点击某个分类面板后，展开该分类下的具体问题条目列表。每个条目显示：
- 条目标题和用户名
- 弱密码严重度进度条
- 具体问题描述（长度不足、字符类型单一、常见密码等）
- "修改密码" 按钮，导航到编辑页

## 检测维度

| 类别 | 严重度 | 色标 | 检测逻辑 |
|------|--------|------|----------|
| `weak` | 高 | 红 `#E33C32` | 密码不满足 `MasterPasswordPolicy` 的可接受标准 |
| `reused` | 高 | 红 `#E33C32` | 两个或以上条目的密码明文完全一致 |
| `stale` | 提醒 | 橙 `#F5A623` | 密码超过 365 天未更新（仅提醒，除非同时为弱/重复则提升为高） |
| `similar` | 提醒 | 橙 `#F5A623` | 密码包含条目标题或网站名中的关键词 |
| `neverEdited` | 信息 | 灰 `#6D7F9B` | 创建后从未修改过密码 |

优先级规则：弱密码 > 重复密码 > 过期密码 > 相似密码。同一条目可能有多个发现。

### 健康评分算法

```
基础分 = 100
每个 weak 发现：-20
每个 reused 发现：-15
每个 stale 发现：-5
每个 similar 发现：-5
每个 neverEdited：-2
最低分 = 0
```

### 隐私约束

- 发现对象的 `toString()` 和错误消息不得包含明文密码
- 健康分析仅在 `VaultService` 已解锁状态下可调用
- 已删除条目（soft-deleted）自动排除

## 数据流

```
VaultService.analyzePasswordHealth()
  → _ensureUnlocked() 守卫
  → 读取所有活跃条目
  → 执行 5 个独立检测（纯内存）
  → 返回 List<PasswordHealthFinding>
  → HealthPage 渲染
```

不创建新的持久化表，不写入 SQLite，不上传数据。

## 服务层

### PasswordHealthService（新增）

`lib/core/security/password_health_service.dart`

```dart
class PasswordHealthService {
  List<PasswordHealthFinding> analyze(List<VaultListItem> items, Uint8List dek);
}

class PasswordHealthFinding {
  String itemId;
  String title;
  String username;
  Set<HealthCategory> categories; // weak, reused, stale, similar, neverEdited
  // 不包含密码明文
}
```

### VaultService 扩展

添加 `analyzePasswordHealth()` 方法，内部调用 `PasswordHealthService`。

### AppServices 扩展

暴露 `analyzePasswordHealth()` 方法，管理保险库解锁状态守卫。

## UI 组件

### HealthPage（新增）

`lib/features/security_health/health_page.dart`

- 使用 `SecureVisualBackground`
- 评分卡片使用渐变背景 (`SecureVisualColors.blue` → `SecureVisualColors.cyan`)
- 分类列表使用 `SecureGlassCard`
- 展开动画 200ms
- 下拉刷新 (`RefreshIndicator`) 重新触发分析
- Skeleton shimmer 在分析进行中显示

### 设置页修改

在 `settings_page.dart` 中添加"密码健康"列表项，导航到 `HealthPage`。

## 视觉效果

- 配色：深色卡片 (`#08224A` 底色) + Lockly 现有蓝/青色渐变
- 字体：跟随系统 Material 3 主题
- 评分数字：56px 粗体，居中大写标题
- 面板：左侧 4px 色条，圆角 14px，内边距 16px
- 过渡：`AnimatedContainer` 200ms ease-out

## 测试矩阵

| 场景 | 预期结果 |
|------|----------|
| 常见弱密码 | 发现 `weak`，严重度 `critical` |
| 两条目重复密码 | 两个条目都发现 `reused`，严重度 `critical` |
| 超过 365 天的密码 | 发现 `stale`，严重度 `warning`（除非也是弱/重复则升级） |
| 密码含标题/网站标记 | 发现 `similar` |
| 强唯一近期密码 | 无发现 |
| 发现字符串不含明文密码 | `finding.toString()` 排除密码 |
| 保险库已锁时调用 | 抛出 `VaultLockedException` |
| 已删除条目排除 | 报告总数排除软删除行 |
| 空保险库 | 评分 100，显示空状态 |
| 分析失败 | 显示错误消息和重试按钮 |
| 下拉刷新 | 重新调用分析 |

## 验收标准

- `flutter test` 全量通过
- `flutter analyze` 静态分析通过
- 健康分析仅在已解锁的解密内存数据上运行
- 发现内容不泄露密码明文
- 不创建新的明文 SQLite 列或表
- 评分卡片适配浅色/深色模式