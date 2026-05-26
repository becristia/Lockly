# LAN 同步手工测试计划（2026-05-25）

## Preconditions

- 两台设备连接到同一个 LAN。
- 两边 Lockly vault 均已解锁。

## P0-01：发送一条无冲突密码

步骤：
1. 在发送端选择一条接收端不存在的密码条目。
2. 发起 LAN 同步并在接收端扫码加入。
3. 接收端确认导入。

期望结果：接收端成功导入该密码条目，字段内容与发送端一致。

记录结果：

## P0-02：错误发送端主密码不导入

步骤：
1. 在发送端使用错误的主密码或错误的发送端验证信息发起导出。
2. 接收端扫码并尝试导入。

期望结果：接收端拒绝导入，并提示凭据或校验失败；vault 内容不变。

记录结果：

## P0-03：一个本地冲突被跳过且不覆盖

步骤：
1. 在接收端准备一条与 incoming item 标识冲突但内容不同的本地密码。
2. 发送端发起包含该冲突条目的 LAN 同步。
3. 接收端确认导入。

期望结果：冲突条目被跳过，接收端原有本地条目未被覆盖。

记录结果：

## P0-04：包内重复跳过第二条 incoming item

步骤：
1. 准备一个同步包，其中包含两条重复的 incoming item。
2. 接收端扫码并确认导入。

期望结果：第一条可导入，第二条重复 incoming item 被跳过，并有可识别的结果记录。

记录结果：

## P0-05：attachment 默认包含

步骤：
1. 在发送端选择一条带 attachment 的密码条目。
2. 使用默认 LAN 同步设置发送。
3. 接收端扫码并确认导入。

期望结果：接收端导入密码条目及其 attachment，附件可打开或可预览。

记录结果：

## P0-06：sender 关闭 attachment 时不导入附件

步骤：
1. 在发送端选择一条带 attachment 的密码条目。
2. 关闭发送 attachment 的选项后发起 LAN 同步。
3. 接收端扫码并确认导入。

期望结果：接收端只导入密码条目，不导入附件。

记录结果：

## P0-07：旧 QR/session 不可复用

步骤：
1. 完成一次 LAN 同步后保留旧 QR 或旧 session。
2. 在接收端再次扫描旧 QR 或尝试复用旧 session。

期望结果：旧 QR/session 被拒绝，不会再次导入任何数据。

记录结果：

## P0-08：app background/auto-lock cancels sender session

步骤：
1. 发送端发起 LAN 同步并停留在等待接收端的 session 页面。
2. 将发送端 app 切到 background，或等待 auto-lock 触发。
3. 接收端尝试继续扫码连接。

期望结果：发送端 session 被取消，接收端无法继续连接并看到可理解的失败提示。

记录结果：

## P0-09：receiver vault 仍可用 receiver master password 解锁

步骤：
1. 接收端完成一次 LAN 导入。
2. 锁定接收端 vault。
3. 使用接收端原 master password 解锁。

期望结果：接收端 vault 可正常解锁，导入后不会改变接收端 master password。

记录结果：

## P0-10：主密码不传输、不持久化、不记录

步骤：
1. 发送端生成 LAN session，接收端扫码并输入发送端 master password。
2. 完成导入或故意输入错误 master password 触发失败。
3. 检查二维码内容、导入结果页、错误提示、本地持久化数据和可访问日志。

期望结果：发送端和接收端 master password 仅在本机内存中用于当前解密/解锁流程；不会写入 QR payload、LAN 传输包、数据库、SharedPreferences、结果页、错误提示或日志。

记录结果：

## P1-01：network unavailable shows retryable message

步骤：
1. 发起 LAN 同步后断开任一设备网络，或切换到不同网络。
2. 接收端尝试扫码连接或继续导入流程。

期望结果：界面显示可重试的网络不可用提示，用户可返回或重新尝试。

记录结果：

## P1-02：language switch updates LAN text

步骤：
1. 打开包含 LAN 同步文案的页面。
2. 切换 app 语言。
3. 返回或刷新 LAN 同步流程页面。

期望结果：LAN 相关标题、按钮、错误提示和结果文案切换为目标语言。

记录结果：
