# M6 最后两项实机验收（尚未完成）

**状态：M6 进行中；不可进入 M7。**

## 1. 真正的 Windows 标准账户安装/卸载

准备 `tools/Test-M6StandardAccount.ps1`。该脚本不新建账户、不重置密码、不尝试管理员提权，不会启动 Desktop Commander Remote。

**必须在标准用户自己正常登录的 Windows 桌面会话中运行**，不能由管理员 PowerShell、S4U 计划任务或不完整加载 HKCU 的模拟令牌替代。脚本检查当前账户不属于 Administrators、HKCU 与该用户的 SID/用户配置文件匹配，并确认不存在旧版托盘注册和安装文件。发现任何预存内容即拒绝测试，避免覆盖真正的用户设置。

先执行只读预检：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\DesktopCommanderRemote\tools\Test-M6StandardAccount.ps1"
```

出现 `M6_STANDARD_USER_PREFLIGHT=PASS` 才能在**同一账户、同一交互式会话**中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\DesktopCommanderRemote\tools\Test-M6StandardAccount.ps1" -RunAcceptance
```

验收 PASS 要求实际在该账户下安装 EXE 到 `D:\Apps\RemoteCommanderTray\<该账户SID>`，对比 SHA256、账户文件夹所有者与 DACL、该账户 HKCU Run、卸载注册及两枚快捷方式，完成升级备份/回滚、卸载并保留设置，且 Node 进程 PID 集合未变化。只有输出 `M6_STANDARD_USER_ACCEPTANCE=PASS` 才能记为通过。

若测试失败，脚本尽力卸载测试程序，但不擅自删除用户数据；应按输出检查测试账户的 D 盘 SID 路径。

**2026-10-14 环境约束：**仅一台 Remote 设备在线；当前连接是管理员账户。已存在的标准用户沙箱账户的配置文件没有加载，强行通过后台任务使用它们不能算交互式标准用户验收。C 盘仅余约 0.28 GB，不适宜自动创建新测试账户/配置文件。对管理员账户执行脚本的预检已正确拒绝，`NOT_STANDARD_USER`（这只是负向保护测试，不是标准用户验收通过）。

## 2. 托盘真正托管的 Remote MCP 调用

当前唯一在线的 Desktop Commander 设备就是 ChatGPT 访问这台 Windows 的通信通道，运行中的 `npx remote` 进程不能停止或接管。当前项目也有外部 Remote 检测保护，在同一设备上强制启动托盘管理的另一个 Remote 会有冲突或断连风险。

**安全验收前置条件：**第二个独立 Windows 用户会话或测试 VM、独立运行的 Remote 认证和设备注册、已安装固定全局包 `@wonderwhy-er/desktop-commander@0.3.0`、此测试会话无外部 Remote 进程。不得复制当前 Remote 的认证令牌或覆盖当前注册信息。

安全测试步骤：

1. 在独立环境的托盘设置中打开 `StartAgentOnLaunch`，启动托盘并观察托盘托管 Node 进程；确认不是 `npx @latest` 或手动启动的外部 Remote。
2. 从该测试环境所连接的 MCP 客户端执行至少一个真实工具调用（如 `list_directory` 指向隔离测试文件夹），记录工具结果与进程 PID。
3. 通过托盘 `Stop agent`，验证只停止托盘拥有的子进程且没有清理官方认证。
4. 验证日志、故障反馈、再次启动及退出后清理；确认当前生产设备仍在线、PID 不变。

必须有测试环境独立进程、实际 MCP 工具调用和托盘关闭证据，才能标记此项 PASS。已完成的 stdio MCP 和当前 npx Remote ping 不能代替此门禁。

**M6 不得标记 PASS，M7 不得开始，直到上述两项都有实测证据。**

## 2026-10-14 托盘托管远程工具门禁更新（覆盖本文件较早的“未连接”状态）

用户已在 Windows 本机安全地手动从旧 npx Remote 切换为 `0.2.0-preview.3` Tray 管理的固定版 `@wonderwhy-er/desktop-commander@0.3.0 remote`，成功重新连接当前对话。实测托盘 PID 9764 → Remote PID 31892 → MCP PID 35756，日志 Connected / Online，并通过当前 Remote 的原生 MCP `list_directory` 成功返回项目 verification 文件夹内容。**托盘托管 MCP 真实工具调用门禁已 PASS**，无需再以“必须独立设备才能验证工具调用”作为阻塞理由。

但是托盘 Stop agent → 启动 → 重新连接完整恢复循环尚未实测，因为当前聊天依赖该连接；不得冒充已验收。**真正非管理员 Windows 交互式账户的安装/更新/回滚/卸载仍待完成**，总 M6 Gate 未通过，M7 未开始。

## 跨用户托盘误判修复后的重试（2026-10-14）

原先脚本提示 `A tray process is running`，是因为它把管理员会话中运行的托盘也算作当前标准用户的托盘。已更新测试脚本和 staging 中的管理器，确认只保护同 SID 或同目标 EXE 的进程，并保留不明同会话进程的保守阻止。

**当前环境先决条件：**C: 可用空间仅约 11 MB，已出现 PowerShell 内存异常。请先安全释放约 2 GB C 盘空间，避免登录和安装不稳定；不要因此结束生产托盘或删除 Remote 授权。

清理完成后，在**现有标准用户自己登录的 PowerShell 会话**重新运行以下两步，保留全部输出：
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\DesktopCommanderRemote\tools\Test-M6StandardAccount.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\DesktopCommanderRemote\tools\Test-M6StandardAccount.ps1" -RunAcceptance
```
第二条必须在第一条输出 `M6_STANDARD_USER_PREFLIGHT=PASS` 后运行。只有出现 `M6_STANDARD_USER_ACCEPTANCE=PASS` 才通过真实标准用户 Gate。旧 `preview.3` SFX 仍含旧管理器，不要使用该包进行本次测试；此处使用 `verification\m6-dist\staging` 中同步后的脚本。
