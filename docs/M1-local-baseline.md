# M1 — 本机环境基线与验收报告

验收日期：2026-10-14
项目根目录：D:\DesktopCommanderRemote
上游：https://github.com/PeterShanxin/Remote-Commander-Tray
Fork：https://github.com/zf849352726/Remote-Commander-Tray
开发分支：develop
上游基线提交：c25d2ce91757d4f5f56bfafb42761a3a0400938f

## 已验证环境

- Windows x64；Node.js v24.21.0；npm 11.19.0；Git 2.41.0；GitHub CLI 2.92.0。
- .NET SDK 8.0.425 已安装，另有 SDK 7.0.203。
- 原始 Remote 正通过 npx @wonderwhy-er/desktop-commander@latest remote 运行。本阶段保留现有进程和授权，未接管、停止或更改。
- 固定 npm 全局版尚未安装，须在后续阶段另行选择经验证的具体版本。
- 注册表 Run 检查未发现 Remote Commander Tray 相关登录启动项；当前未修改启动配置。
- Remote MCP 实际远程调用已验证可用：远程设备 ping 和实际执行本机状态查询均成功。

## 构建与测试验收

| 验收项 | 实际结果 |
| --- | --- |
| .NET 8 SDK | 8.0.425，可用 |
| Solution Restore | PASS，所有项目恢复成功（改用 D 盘私有 NuGet 缓存） |
| Release Build | PASS，0 warnings，0 errors |
| Core Tests | PASS 153/153 |
| Windows Tests | PASS 13/13 |
| Windows Native Integration | PASS 10/10 |
| 实际 MCP 调用 | PASS：远程 ping、进程与文件系统查询 |
| 原有 Remote 授权/会话 | 未主动修改，远程连接可用 |
| PLAN.md / AGENTS.md | 均保留 |

测试输出（本地忽略追踪的 verification 目录）：
- verification/m1-restore.log：首次失败，原因是 C 盘磁盘空间不足。
- verification/m1-restore-D.log：切换 NuGet/CLI 缓存到 D 盘后恢复成功。
- verification/m1-build.log
- verification/m1-test.log
- verification/m1-native.log
- tests/*/TestResults/test-results.trx

## 已识别风险 / 后续约束

- **C 盘可用空间为 0 GB**。可能影响 Windows、SDK 和用户程序稳定性；此问题未由项目改动解决。严禁未确认地清理个人文件。
- 后续 .NET 构建继续复用 D:\DesktopCommanderRemote\verification 中的 NuGet/CLI 缓存，并显式设置 TEMP/TMP=D:\temp。verification/ 被 .gitignore 排除。
- 现有 Remote 为手动启动的 @latest 外部实例。M2 冲突检测必须保守、只读，不能结束该进程或使远程控制中断。
- M6 的固定版本安装仍需验证目标版本及升级回滚。
- M7 的完整托盘/登录/系统实机验收不能以本次 M1 基线测试代替。

## M1 门禁

**PASS**。基线、源码及环境记录、编译、单元测试和原生集成测试均成功。允许进入 M2，但受上述磁盘容量和在线外部 Remote 安全边界约束。
