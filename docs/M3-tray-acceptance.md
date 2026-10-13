# M3 — 托盘交互与登录启动验收

日期：2026-10-14
开发根目录：D:\DesktopCommanderRemote
阶段顺序：M1 PASS → M2 PASS → M3

## 完成的改动

1. 单进程系统托盘延续上游 WinForms 实现，不引入服务、第二个管理器或后台独立常驻代理。
2. 使用 Local\ 范围内的 Windows 自动复位命名事件激活已有实例；重复运行 EXE 将信号送给主实例，而不新建 Remote 进程。
3. Hide Tray 隐藏 NotifyIcon，原有托盘管理器和 Remote 状态均不改变；再次运行 EXE 可恢复可见性。
4. 明确保留 Exit Application（停止受管理 Remote 并退出程序）与 Hide Tray 的区分。
5. 托盘 HKCU Run 登录启动注册与 Remote 自启动开关解耦：若首次运行时托盘注册项不存在，程序注册自身；Windows 已禁用或状态未知时不重写用户的 Windows 审批记录。
6. 托盘菜单显示注册状态并可打开 Windows Startup Apps 设置；只用独立的 Start Remote at sign-in 控件改变 settings.json 中的 startAgentOnLaunch，已保存设置下次启动生效。
7. 改变 Remote 自启设置不会立刻启动或停止 Remote；手动 Stop 语义保持至本次登录结束。
8. 启动路径保留 M2 外部 Remote 冲突保护；不接管用户正在运行的 npx Remote。

## 本机测试记录

| 测试 | 结果 |
| --- | --- |
| Release 构建 | PASS，0 warnings / 0 errors |
| Core 自动化测试 | PASS 155 / 155 |
| Windows 自动化测试 | PASS 25 / 25 |
| Windows 原生进程集成测试 | PASS 10 / 10 |
| 命名事件发信/不存在实例检查 | PASS（2 项新 Windows 测试） |
| 托盘 Hide → Show / 远程状态未变化 | PASS（托盘合成进程测试） |
| Remote 登录自启开关持久化 | PASS（settings.json，合成数据目录） |
| HKCU Run 注册状态与 Windows 外部禁用检查 | PASS（隔离注册表测试） |
| 真实用户 Windows 注销/登录 | 未测试，留待 M7 实机验收 |
| 真实 EXE 第二次运行唤回隐藏托盘 | 未测试完整 UI 端到端，留待 M7 |
| 首次运行真实 HKCU Run 写入 | 本阶段未运行开发版 EXE；M6/M7 验证 |

## 已知边界与风险

- Windows 登录后能否实际显示托盘、系统托盘通知能否唤回等需要 M7 的真实 GUI 人工验收。
- 此阶段仅编译和测试开发版本，**没有安装软件或向真实用户 HKCU Run 写入登录启动项**；安装器正式部署在 M6，开机实机验收在 M7。
- 原有 Remote 正在运行，因此不会运行可能启动同一设备 Remote 的开发 EXE；只有受控的合成进程用于自动化测试。
- C 盘空间仍极低/曾为 0 GB，首次真实托盘写入 LOCALAPPDATA 设置可能失败，需在实机验收前解除磁盘空间风险。
- 后续需要测试重复 EXE 启动的竞争窗口，以及托盘退出、登录重启和隐藏状态与单实例协议的实际交互。

## M3 门禁

PASS（阶段自动化、单实例信号与合成托盘测试通过）；真实登录/真实托盘人工门禁移交 M7，不将其冒充已完成。
