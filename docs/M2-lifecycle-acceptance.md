# M2 — 进程生命周期与外部实例冲突检测验收

日期：2026-10-14
上游基线：c25d2ce
基于 M1 的 166 项自动化测试、10 项原生集成检查继续开发。

## 改动

1. 在 Core 引入 IExternalAgentDetector 与 ExternalAgentPresence（None / Conflict / Unknown），保留可测试边界。
2. Windows 实现使用只读 WMI Win32_Process 命令行检测，识别 node、cmd、desktop-commander.exe 中的远程 CLI 启动命令。
3. 遇到外部 Remote 冲突或进程信息不完整时，保守阻止托盘启动新 Remote，并明确提示；不接管、不终止外部进程。
4. AgentSupervisor 在实际启动前执行检查；手动停止保护、异常恢复与 Job Object 原有逻辑保留。
5. Windows TrayApplicationContext 生产默认使用真实检测器，合成托盘测试通过依赖注入使用可预测的检测器。
6. Windows 原生集成项目同步添加 System.Management 8.0.0 包引用，避免生产源文件直接编译时缺失依赖。
7. 新增核心保护测试和 Windows 命令行识别测试；未启动第二个真实 Remote。

## 验证

| 门禁 | 结果 |
| --- | --- |
| Restore | PASS，D 盘缓存 |
| Release Build | PASS，0 warnings，0 errors |
| Core Tests | PASS 155/155 |
| Windows Tests | PASS 23/23 |
| Native Integration | PASS 10/10 |
| 外部进程冲突与不可检查状态 | PASS，核心模拟测试阻止实际创建进程 |
| Remote 启动命令识别 | PASS，识别 npx/node/shim，忽略无关命令 |
| 实际 Windows WMI 查询权限 | 当前远程环境可获取在线 Remote 进程命令行（M1 只读观察） |
| 当前活动 Remote | 未停止、未接管 |
| 真实托盘端到端运行 | 尚未运行，后续 M7 人工实机门禁 |

- 首轮 M2 测试曾因真实进程被识别而阻止合成托盘测试；已通过测试检测器依赖注入修复，再次全量测试通过。
- CI 测试与当前 Remote 实例隔离；实际机器上的托盘在线状态、通知交互仍需要 M7 人工测试。

## 风险

- C 盘空间仍为零；构建与测试缓存必须维持在 D 盘。
- WMI 不可用或部分进程命令行不可读取时采用失败关闭（Unknown），可能要求用户先处理权限问题。
- 进程检测存在命令行模式误判/漏判的可能；首次真机启用托盘前必须验证实际冲突提示，不启动第二个实例。
- 不修改用户当前 npm @latest Remote 命令；固定版本及安装交给 M6。

## M2 门禁

PASS：本阶段变更已通过构建、自动化测试和原生集成测试；受上述真实托盘验收边界约束。
