# Remote Commander Tray V2 — 项目总计划（PLAN.md）

> 状态：已获执行授权，**M1 已通过验收，M2 待开始**。严格按 M1→M8 阶段门禁执行。
>
> 本地开发根目录：D:\DesktopCommanderRemote
>
> 上游项目：https://github.com/PeterShanxin/Remote-Commander-Tray
>
> 工作方式：Fork 保留上游 Git 历史，在个人仓库的开发分支进行 C#/.NET 8/WinForms 二次开发。
>
> 需求依据：2026-10-13 grilling 设计树 Q1–Q40 全部已确认。
>
> 本文件是后续实施、验收、提交与回滚的唯一总计划入口。新增计划变更同步更新本文件；遵循同目录 AGENTS.md。

## 1. 项目目标

将 npx @wonderwhy-er/desktop-commander@latest remote 对应的 Remote 功能改造成用户登录 Windows 后可自动启动、由系统托盘管理的长期后台程序。正式运行时使用经过验证的**固定版本**，不继续依赖 @latest 自动变化。

目标能力：
1. Windows 用户登录后自动启动托盘程序；Remote 是否自动启动由托盘中的独立开关决定。
2. 托盘与管理器合并为一个 WinForms 程序；无独立 Windows 服务、常驻守护进程或额外监控进程。
3. 托盘提供 Start、Stop、Restart、Hide Tray、Show Logs、Exit Application。
4. 隐藏托盘不关闭 Remote；再次运行 EXE 只恢复原托盘，不新增实例、不更改 Remote 启停状态。
5. 本次登录期间手动停止 Remote 后不自动重启；下一次登录遵循自动启动开关。
6. 受管理的 Remote 进程异常退出时自动退避重启；普通网络中断先由官方客户端重连。
7. 检测外部 Remote 实例冲突；保守提示，不接管或杀死不属于本程序的进程。
8. 同时展示进程状态与 CLI 报告的连接状态；无法可靠判断时显示 Unknown。
9. 授权失效提醒用户重新认证；不自动清除授权文件。
10. 日志脱敏、按大小轮转和七天过期清理；详细日志默认关闭，允许主动开启。
11. 普通用户安装、卸载、更新、回滚；不破坏原有 Node.js/npm/Remote 认证与配置。
12. 实际 Windows 系统验收及 MCP 工具调用测试通过后才发布。

## 2. 固定设计决策（Q1–Q40）

| 类别 | 确定结果 |
| --- | --- |
| 自启动触发 | 用户登录 Windows，而非开机前系统服务 |
| 程序形态 | C# / .NET 8 / WinForms 单程序系统托盘 |
| 托盘运行方式 | 完全后台、无终端弹窗 |
| 用户控制 | 托盘菜单启动、停止、重启，独立控制 Remote 自启动 |
| 自启动注册 | HKCU Run；托盘每次登录运行，Remote 是否运行由配置决定 |
| 手动停止 | 本次登录不自动恢复，下次登录遵循 Remote 自启动开关 |
| 隐藏托盘 | 管理器继续运行；再次执行 EXE 恢复托盘 |
| 真正退出 | 单独提供 Exit Application，停止受管理的 Remote 后结束程序 |
| 自动恢复 | Remote 异常退出时带退避重试；用户手动停止不触发 |
| 管理器自身崩溃 | 不另设守护进程；Job Object 确保受管理进程尽力清理 |
| 网络中断 | 官方 Remote 自行重连优先；不因短暂断线强制重启 |
| 版本管理 | 固定已验证 npm 全局安装版本；手动验证更新，可回滚 |
| 外部进程 | 冲突时保守暂停启动；不自动接管/强制结束 |
| 连接状态 | 沿用 CLI 解析，并严格区分 Running 与 Online |
| 授权失效 | 弹出有节制的通知，由用户重新授权 |
| 日志 | 普通与详细日志大小轮转 + 七天过期清理；普通日志脱敏 |
| 通知 | 仅重要异常显示 Windows 通知 |
| 睡眠/锁屏 | 不阻止睡眠；锁屏不主动停止，唤醒后恢复检查 |
| 用户范围 | 当前 Windows 用户独立运行；不共享跨账户授权 |
| 源码托管 | Fork 上游到个人 GitHub；开发分支、阶段提交及 Release |
| 安装路径 | %LOCALAPPDATA%\Programs\RemoteCommanderTray\ |
| 安装形式 | 自包含 EXE + 当前用户安装器 |
| 卸载 | 删除本程序安装文件与注册项；询问保留设置/日志；保留官方认证 |
| 验收 | 自动测试 + Windows 实机测试 + 实际 MCP 调用 |

### 2.1 运行结构

```text
Windows 用户登录
  └─ HKCU Run
      └─ Remote Commander Tray（单实例 WinForms 应用）
          ├─ 托盘 UI / 隐藏与恢复 / 自启设置
          ├─ Remote Supervisor / Job Object / 异常重启 / 冲突检测
          ├─ CLI 状态解析 / 认证提醒 / 通知
          ├─ 日志轮转与清理
          └─ 固定版本 Desktop Commander Remote（受管理子进程）
              └─ Remote MCP 服务
```

### 2.2 生命周期优先级

1. **手动 Stop 优先级最高**：即使启用了异常恢复，也不得在本次登录内再次自动启动，除非用户主动 Start/Restart。
2. **隐藏不等于退出**：Hide Tray 不结束管理器，不影响 Remote；第二次运行 EXE 应触发恢复显示。
3. **Exit Application 是显式彻底退出**：停止受管理进程；不得误杀用户在其他终端运行的 Node.js/npm。
4. **断网不等于崩溃**：进程仍活跃时主要依赖官方重连，避免反复启动产生并发实例。
5. **管理员权限不是默认需求**：HKCU 与 LocalAppData 为主，不能无理由提权。
6. **安全优先**：无法确定 PID 归属时不强制结束，连接状态无法判断时显示 Unknown。
7. **切换版本不可覆盖凭据**：升级和卸载均保留官方认证数据。

## 3. 开发阶段与门禁

### M1 — Fork、基线与环境诊断

任务：
- 检查工作根目录、现有 AGENTS.md、PLAN.md 与 Git 状态。
- Fork 上游仓库，保留 Git 历史与 LICENSE；将 D:\DesktopCommanderRemote 用作本地工作区。
- 若本地目录包含已有文件，先制定非破坏性导入方案，不覆盖 AGENTS.md / PLAN.md。
- 新建开发分支（如 develop），记录上游 commit、依赖与构建指令。
- 检查 Windows 版本、架构、Node.js、npm、npx、.NET SDK、现有 Remote 包、授权及启动项。
- 检查当前是否存在 Remote 外部进程；仅收集信息，不停止或替换。
- 构建原版并运行其现有测试；验证原版 Remote 实际 MCP 调用。
- 输出基线环境报告、风险清单与版本锁定候选。

门禁：
- 源码/许可证来源明确，原版编译和可用测试通过或阻塞原因清晰。
- 现有授权、运行进程与启动配置未受破坏。
- Git 工作区路径确认为 D:\DesktopCommanderRemote。
- 未通过 M1 验收，不进入 M2。

Git：chore: establish upstream baseline

### M2 — 进程生命周期与冲突检测

任务：
- 复核原项目 Windows Job Object 的 KILL_ON_JOB_CLOSE / 清理语义。
- 保留并验证托盘管理进程与其子进程树的归属关系。
- 识别外部 Remote 实例；可能冲突时暂停自动启动并提示。
- 实现手动停止标志与异常退出重试的严格隔离。
- 实现有上限/退避间隔的异常重试，避免高速循环。
- 确保普通 Node.js 进程和其他用户 Remote 进程不被误杀。
- 处理注销与关机时尽力关闭受管理进程。

门禁：
- Start/Stop/Restart 正常；重复操作不出现第二实例。
- 受管理进程崩溃后按策略恢复，手动 Stop 不自动恢复。
- 外部进程冲突可被检测并安全提示。
- Job Object 关闭不会留下受管理孤儿进程（在可测场景下）。
- 无关进程未被终止。

Git：feat: improve remote process lifecycle

### M3 — 托盘交互与登录启动

任务：
- 保留单程序 WinForms 结构和托盘单实例保护。
- 实现 Hide Tray、恢复隐藏托盘、Exit Application。
- 再次运行 EXE 仅唤回托盘，不新建 Remote 或改变停止状态。
- 以 HKCU Run 注册托盘登录自启动。
- Remote 的“Start at Login”与托盘自启动解耦，配置持久化。
- 登录时仅在 Remote 自启为 On 且无外部冲突时自动启动。
- 关闭 Remote 自启时，托盘仍运行并允许手动 Start。
- 托盘显示必要状态和重要异常通知，减少弹窗。

门禁：
- 登录自启正确，Remote 开关按设置生效。
- Hide Tray 后 Remote 持续运行；重复 EXE 恢复图标。
- 手动 Stop 本次登录内持续有效。
- Exit Application 真正结束程序及其受管理进程。
- Windows 自启项被外部禁用时显示真实状态，不误报。

Git：feat: enhance tray controls and startup settings

### M4 — 连接状态、网络及授权

任务：
- 复用/改进 CLI 输出解析，不自行重写 Remote MCP 协议。
- 状态包括 Running、Stopped、Online、Connecting、Reconnecting、Auth Required、Error、Unknown。
- 明确区分进程在运行与远程会话真正可用。
- 断网时优先等待官方重连；恢复网络后更新状态。
- 验证授权失效检测及用户重新认证入口；禁止自动删凭据。
- 锁屏、睡眠、唤醒后执行状态重新检查。
- 减少重复通知；正常重连不刷屏。

门禁：
- 网络断开与恢复测试通过；没有频繁误重启。
- 未知状态显示 Unknown，不伪造在线状态。
- 授权失效时准确提示、不无限重启。
- 唤醒后状态可正常恢复。
- 实际远程 MCP 工具调用成功。

Git：feat: improve connection state handling

### M5 — 日志、脱敏及诊断

任务：
- 普通日志单文件 1 MB，最多保留 10 个轮转文件。
- 详细日志单文件 5 MB，最多保留 4 个轮转文件；默认关闭。
- 普通与详细日志统一增加七天过期清理机制。
- 启动时及运行中定期清理；兼顾活跃文件锁与轮转正确性。
- 保留启动、停止、失败类别、恢复状态等非敏感事件。
- 普通日志避免保存认证数据、验证码、执行参数和文件内容。
- 详细日志主动开启，有隐私提醒；导出诊断默认不包含敏感日志。
- 验证数量/容量阈值优先时，旧日志可能早于七天删除。

门禁：
- 文件大小轮转、数量限制、七天清理测试通过。
- 活跃日志不被误删；清理失败不会使主进程崩溃。
- 脱敏测试通过，默认诊断不泄露凭据。
- 7 天是最长保留期限，而非保证完整保留 7 天。

Git：feat: add log retention and diagnostics

### M6 — 安装、卸载、版本与回滚

任务：
- 发布 Windows x64 .NET 自包含 EXE，制作当前用户安装器。
- 默认安装在 %LOCALAPPDATA%\Programs\RemoteCommanderTray\。
- 检测并使用已验证的固定 npm 全局 Remote 版本，执行路径明确。
- 全局 npm 安装遇到权限或路径冲突时先诊断，不擅自提权。
- 禁止启动时隐式使用 @latest；升级只能由用户明确发起。
- 创建恢复托盘的桌面快捷方式与卸载入口。
- 卸载时停止受管理进程、移除本程序的 HKCU Run 项及文件。
- 卸载向用户询问配置和日志是否保留；绝不清理官方认证数据。
- 升级前保留上一已验证版本及非敏感配置；可手动回滚。
- 发布物提供版本号、构建来源、依赖版本及校验值。

门禁：
- 普通用户可安装、卸载、重新安装，不破坏其他程序。
- 卸载后本程序注册的启动项不存在；用户选保留的配置/日志被保留。
- 原 Node.js/npm 环境与官方授权文件没有被重置。
- 升级后实际 MCP 功能验证通过，失败时可成功回滚。

Git：feat: add installer and version management

### M7 — 完整 Windows 系统验收

执行自动测试和实机测试，至少覆盖：
1. 首次安装、重复安装及普通用户权限。
2. 登录自启（Remote 开/关两种设置）。
3. 托盘隐藏、恢复、单实例及真正退出。
4. Start、Stop、Restart 及本次登录手动停止的持久性。
5. Remote 异常退出与退避重试。
6. 托盘管理器异常退出和 Job Object 清理。
7. 网络断开、恢复及长时间离线。
8. 授权失效与重新认证。
9. 锁屏、睡眠、唤醒、注销及再登录。
10. 外部 Remote 进程冲突与无关 Node.js 进程安全。
11. 日志大小轮转、七天过期、脱敏与详细日志开关。
12. 固定版本更新、升级失败回滚及卸载。
13. 实际 MCP 工具调用（不可仅凭 Online 状态代替）。

门禁：
- 所有必要自动化测试通过，并保留报告。
- 关键 Windows 实机验收通过，失败项必须修复并重测。
- 无严重进程生命周期、授权破坏或错误进程终止问题。
- 构建过程可复现，不含提交的个人凭据或敏感日志。

Git：test: complete Windows acceptance tests

### M8 — 文档、版本发布与收尾

任务：
- 更新 README.md、中文版使用指南、CHANGELOG.md。
- 完善安装、卸载、启动、停止、重连、升级、回滚操作说明。
- 记录与上游的差异及相关版权、LICENSE 声明。
- 整理测试、验收、已知限制与兼容性说明。
- 创建 GitHub Release，提供安装器、EXE、校验值及发布说明。
- 将通过验收的开发分支按 Git 工作流合并到主分支。
- 验证最终发行版本与测试版本一致。

门禁：
- 发布文件可在目标 Windows 机器正常安装与启动。
- 完整验收报告、Release 与文档可追溯。
- 没有未披露的严重问题或凭据泄露。

Git：docs: finalize release and acceptance

## 4. 全局执行、Git 与安全规则

1. 严格按 M1 → M2 → M3 → M4 → M5 → M6 → M7 → M8 顺序实施。
2. 每一阶段验收通过后提交 Git；失败时不得擅自标记为完成。
3. 每次修改同步更新 PLAN.md；执行过程遵循 AGENTS.md。
4. 自动测试不代替 Windows 实机测试；Online 不代替实际 MCP 工具调用成功。
5. 禁止破坏已有官方授权、Node.js 环境、无关进程和其他程序的注册表项。
6. 不提交认证文件、令牌、个人敏感路径、隐私日志到 GitHub。
7. 未经批准不得引入独立 Windows 服务、额外常驻看门狗或彻底替换上游架构。
8. 发现影响既有设计决策的重大差异，先写明风险及决策，再调整本计划。
9. 阶段提交遵循 Git diff 审核、构建、测试、验收、commit 的顺序。
10. M1 必须先检查目标目录状态；本目录先前存在 AGENTS.md 与 PLAN.md，不得用 clone 覆盖它们。

## 5. 状态与变更记录

| 项目 | 状态 |
| --- | --- |
| grilling 设计树 Q1–Q40 | 已完成 |
| 本地根目录 D:\DesktopCommanderRemote | 已指定 |
| PLAN.md | 本次写入计划 |
| 开发方案审批 | 用户已授权执行 |
| Fork 与 Git 初始化 | 已完成：Fork + develop 分支，保留上游历史 |
| M1 | 已通过验收；见 docs/M1-local-baseline.md |
| M2 | 未开始 |
| M3 | 未开始 |
| M4 | 未开始 |
| M5 | 未开始 |
| M6 | 未开始 |
| M7 | 未开始 |
| M8 | 未开始 |

### 2026-10-13
- 已确认 Q1–Q40。
- 已指定 D:\DesktopCommanderRemote 为唯一本地开发根目录。
- 将已确认的分阶段计划整理到 PLAN.md。
- 当前仅规划落盘，不开始 Fork、安装、注册自启、运行测试或软件开发。

### 2026-10-14
- 用户授权执行 PLAN.md。M1 基线完成并通过 166 项自动化测试、10 项 Windows 原生集成检查，Release 构建 0 警告 / 0 错误。
- C 盘空间不足；将项目依赖缓存移至 D 盘。该环境风险仍需处理。
- 保留现有手动启动的 Remote 进程；后续冲突检测不得接管或终止现有连接。
- M1 验收证据：docs/M1-local-baseline.md；下一阶段为 M2。
