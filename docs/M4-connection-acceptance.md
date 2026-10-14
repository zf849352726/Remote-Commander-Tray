# M4 — 连接状态、网络与授权处理验收

日期：2026-10-14
本地根目录：D:\DesktopCommanderRemote
上游开发分支：develop

## 实现内容

1. 延续官方 Desktop Commander CLI 输出解析，不新建独立远程健康接口，也不重写 MCP 协议。
2. 增加 AgentState.Unknown，明确表示受管理进程仍在运行，但系统恢复后远程连接尚未由新 CLI 信号确认。
3. 通过 Microsoft.Win32.SystemEvents 订阅 Windows PowerModeChanged（Resume）及 SessionSwitch（SessionUnlock），在受管理进程仍存活且上次为 Online 时将连接状态降为 Unknown。
4. 复用状态机的 DeviceOnline / DeviceReady 信号恢复 Online；ChannelSubscribed 单独出现不足以确认设备在线。
5. ChannelDisrupted 出现在 Unknown 时转为 Connecting / Reconnecting，保留已有进程，不触发强制重启。
6. 托盘菜单额外展示进程状态和连接状态，避免 ProcessRunning 被误读为远程连接可用。
7. Unknown 使用可区别于暂停和错误的托盘图标；系统锁屏不主动停止代理。
8. 保留上游授权失效人工处理和通知去重逻辑。需要执行官方 logout 的重新认证操作仍由用户在界面确认后发起；无自动凭据清除。

## 阶段验证

| 测试 | 结果 |
| --- | --- |
| 解决方案 NuGet Restore | PASS，采用 D 盘本地缓存 |
| Release Build | PASS，0 warnings / 0 errors |
| Core Tests | PASS 160 / 160 |
| Windows Tests | PASS 25 / 25 |
| Windows Native Integration | PASS 10 / 10 |
| 状态在线→唤醒 Unknown→新官方在线事件 Online | PASS，模拟状态机测试 |
| 未收到新在线信号不假称 Online | PASS |
| 网络断开不自动启动第二进程 | PASS，回归与状态机测试 |
| 授权流程与用户确认 | PASS，既有自动化回归 |
| 托盘 Process/Connection 状态分离 | PASS，合成托盘 UI 测试 |
| 实际 Remote MCP 连接 | PASS，本次远程文件/命令工具调用可用 |
| 真实 Windows 睡眠唤醒/锁屏测试 | 待 M7 实机验收 |

## 诊断与边界

- 初次未恢复 NuGet 包时使用 --no-restore 构建报缺少 Xunit 与 System.Management 引用；已确认资产记录失效，重新在 D 盘恢复依赖后全部测试通过。
- 系统恢复后若官方 CLI 没有报告新在线事件，状态保持 Unknown。这是保守显示，不应通过时间推断在线。
- 假连接恢复、异常 CLI 日志、操作系统电源事件真机兼容性将在 M7 进行实机测试。
- 此阶段没有运行开发版托盘 EXE、修改真实 HKCU Run，也没有终止用户当前正在运行的 Remote。
- C 盘已恢复约 2.2 GB 可用空间，但仍需保持足够空间以保证 M6 安装和 M7 实机测试。

## M4 验收

**PASS（阶段自动化、原生集成和既有远程 MCP 调用）**。真实设备睡眠/解锁门禁保留在 M7，不虚报完成。
