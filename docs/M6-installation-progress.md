# M6 — 安装、固定依赖与回滚：执行记录

日期：2026-10-14
开发根目录：D:\DesktopCommanderRemote
分支：develop

**当前状态：M6 进行中，隔离测试通过；真实部署和升级后的 MCP 验收尚未通过。**

## 已实现

- 发布 win-x64 .NET 8 自包含单文件 EXE，应用版本候选 0.2.0-preview.1。
- 使用 Windows 内置 IExpress 打包当前用户安装 EXE，无需系统级编译器安装。NSIS 官方压缩包在当前网络无法可靠获取，故更换打包实现；不改变“单 EXE 当前用户安装器”的设计目标。
- 当前用户安装路径：D:\Apps\RemoteCommanderTray。
- HKCU Run 注册、开始菜单与桌面快捷方式，以及 Add/Remove Programs 卸载入口；不会请求管理员权限。
- 安装前核验 release-manifest.json 的 EXE SHA256，升级前备份旧版 EXE、发行清单和管理脚本，回滚时再次核验哈希。
- 卸载前要求退出托盘，卸载时询问是否保留日志与配置；从不自动删除官方 Desktop Commander 认证、Node.js/npm 或其他进程。
- 隔离 TestMode 限制为 verification 路径，避免测试误写真实用户目录及 HKCU Run。
- Remote 运行入口取消自动 npx @latest 及未验证的 npm shim，只识别固定全局包名和精确版本。
- 固定候选版本：@wonderwhy-er/desktop-commander@0.3.0；npm 包 integrity 保存在 tools/remote-package-lock.json；未修改正在运行的外部 Remote。
- 包含 MIT LICENSE 文件；提供 Build-RemoteCommanderTray.ps1、Manage-RemoteCommanderTray.ps1、Test-M6Lifecycle.ps1 和使用说明。

## 已完成验证

| 检查项目 | 结果 |
| --- | --- |
| Release 构建 | PASS，0 警告、0 错误 |
| Core 自动化测试 | PASS，177/177 |
| Windows 自动化测试 | PASS，25/25 |
| Windows 原生集成检查 | PASS，10/10 |
| 固定 CLI 版本、包名与禁止静默下载 | PASS，模拟环境 |
| 隔离安装、升级、哈希备份与回滚 | PASS |
| 篡改备份拒绝回滚 | PASS |
| 卸载保留设置/日志及明确删除选项 | PASS，隔离模式 |
| 不修改真实 HKCU Run | PASS，隔离模式 |
| 最终自解压 EXE 解包、MIT LICENSE、包装脚本安装与卸载 | PASS，隔离模式实际执行，最终候选包校验通过 |
| 当前用户真实安装及 HKCU Run | PASS，D 盘程序及 HKCU Run、快捷方式、卸载入口已验证；管理员账户，非管理员环境待测 |
| 固定版全局 npm 0.3.0 + 实际 MCP 工具调用 | PASS：全局入口通过 initialize、tools/list、tools/call(list_directory) 的 stdio MCP 往返；独立的 remote 模式切换仍待测试 |
| 真正 Windows 登录、隐藏/恢复托盘 | 留待 M7 |

## 未完成的阶段门禁

当前远程会话依赖正在运行的 Desktop Commander Remote，禁止在此阶段强制替换或停止该外部进程。尚未在独立普通用户环境验证真实安装/卸载、HKCU 注册及升级后的 Remote MCP 通信。按照现行 PLAN.md，M6 尚不能完整标记 PASS，相关实现不得宣称已完成实机验收。

安装包未签名，正式发布时需要披露 Windows SmartScreen 警告。当前 C 盘空间较少，构建和测试输出位于 D 盘 verification 路径。M6 真实门禁通过前，不进行 M7，也不提交宣称 M6 完成的阶段 Git commit。


## D 盘安装修订（用户已确认）

- 正式程序：`D:\Apps\RemoteCommanderTray`。
- 数据根目录：`D:\Apps\RemoteCommanderTrayData`。实际设置/日志按 Windows SID 建独立子目录。
- AppPaths 默认路径与安装、卸载脚本一致；TestMode 只能在 verification 隔离目录操作。
- 新增 2 项默认路径测试及 nvm-windows 路径解析测试；Release 构建通过，Core 177/177 和 Windows 25/25 自动化测试通过；隔离生命周期脚本全部通过。
- 旧 C 盘应用配置及日志未删除，也未更改当前官方认证。
- M6 真实普通用户安装、升级后 MCP 检查尚未完成，继续保留阶段未通过状态。

- D 盘最终候选自解压安装包 SHA256: BD01EC0F116B71468C6EEEAFA38E200147940C7155225EC04E8200C2A8B0B801。已验证自解压、许可文件、实际运行测试模式安装入口、EXE 哈希和隔离卸载。
- Windows 10 项原生集成检查在 D 盘修订后已重新通过；未运行正式用户安装入口。

## 2026-10-14 远程连接恢复后的 M6 验收补充

- 已确认设备恢复在线，原 npx Remote 和全局 npm 安装包均为 `@wonderwhy-er/desktop-commander@0.3.0`；没有停止、接管或替换当前 Remote。
- Node/npm 位于 D 盘，全局包安装到 `D:\nvm4w\nodejs\node_modules\@wonderwhy-er\desktop-commander`；验证包名、版本及入口真实存在。运行环境解析器成功自动解析该 Node 和 pinned 入口（`FOUND=True`）。
- 全局包在**独立 stdio 模式**下，实际通过 MCP 初始化、工具列表（25 个）以及一次 `tools/call list_directory`，不是只凭进程 Online 认定可用；本次现有 npx Remote 的 MCP ping 也成功。**托盘托管的 `remote` 模式在当前连接中未接管测试**，留作后续独立会话验收。
- 正式 D 盘程序安装后已校验 SHA256，真实 HKCU Run、开始菜单/桌面快捷方式、卸载条目正常；首次配置 `startAgentOnLaunch=false`，无自动创建第二个 Remote。
- 默认数据目录 ACL 已修复并实际验证：只允许当前账户、SYSTEM 与 Administrators 完全访问，不继承 `Authenticated Users:F`。
- 已在当前账户启动托盘 EXE，进程存活并生成 D 盘日志，未创建新的 Remote 进程；第二次运行程序也只保留单个托盘管理器。
- 真实 D 盘安装→备份→回滚→再次安装过程执行且 SHA256 验证通过。但本次安装前后可执行文件哈希一致，**不能把它当成不同版本二进制的完整升级/回滚验证**。
- 仅终止本阶段启动、确认没有受管理子进程的测试托盘进程后，真实运行了保留用户数据的卸载流程：删除程序文件、HKCU Run、卸载条目与快捷方式；设置保留，npx Remote 进程 PID 不变。新增 `-KeepUserData` 显式安全卸载选项。
- M6 仍未满足全部门禁：独立**非管理员**账户安装/卸载、不同真实程序版本回滚以及受托盘管理的 Remote 远程通信需进一步验收。不能把当前管理员账户或 stdio 测试表述成这些检查已通过。

- 最终候选安装包重新生成，并从实际 EXE 自解压验证 5 项内容（EXE、管理脚本、安装入口、清单及 LICENSE）。最终包 SHA256：`BD01EC0F116B71468C6EEEAFA38E200147940C7155225EC04E8200C2A8B0B801`；安装后 EXE SHA256：`EC2C0C6BF1ECAFBBC556A468C26E0197C0817A36B62D62A7B095EBB2985E68C2`。
- 已执行真实卸载（`-KeepUserData`）并验证程序文件、HKCU Run、快捷方式及卸载注册项被清理、配置保留、外部 Remote PID 不变；随后通过最终自解压包重新安装并再次通过清单哈希检查。
- 此次为当前管理员账号的真实操作，不等同于独立标准用户测试；托盘托管 Remote 模式和不同 EXE 版本回滚仍待完整验收。

## 2026-10-14 — 两个不同自包含 EXE 的升级回滚实测

- 在 `verification` 中额外发布应用版本 `0.2.0-preview.2`（`dotnet publish`，自包含 Windows x64 单文件），保留正式安装的 `0.2.0-preview.1`，**未触碰 D:\Apps 下的正式应用或外部 Remote**。
- 版本 1 EXE SHA256：`EC2C0C6BF1ECAFBBC556A468C26E0197C0817A36B62D62A7B095EBB2985E68C2`。
- 版本 2 EXE SHA256：`756C1288AA30C474914FF918C53FF1D0B05FB1F3E8B45ED2CBE2217581BADB13`。
- `tools/Test-M6DistinctRollback.ps1` 真实运行通过：v1 安装 → v2 升级 → 验证 v1 SHA256 备份 → 回滚恢复 v1 及发行清单 → 再次升级 → 篡改备份后拒绝回滚且当前 v2 不变 → 卸载保留设置。
- 验证 HKCU Run 不变、当前远程 npx Remote PID 集合不变。日志：`verification/m6-distinct-rollback.log`，最终记录 `M6_DISTINCT_EXE_ROLLBACK=PASS`。
- **不同实际程序版本的升级/回滚门禁在隔离 Windows 实机文件系统中通过**；当前用户的正式安装仍为原候选版。

## 2026-10-14 — 安装父目录 ACL 审查与新增阻塞

- 新增只读审计脚本 `tools/Audit-M6InstallPermissions.ps1`，验证程序目录、数据根目录及公共上级目录是否赋予过宽的写权限。
- 本机审计返回 `M6_INSTALL_ACL_AUDIT=FAIL`（退出码 2）：`D:\Apps`、`D:\Apps\RemoteCommanderTray` 和 `D:\Apps\RemoteCommanderTrayData` 均继承了 `Authenticated Users`（SID `S-1-5-11`）的 `FullControl`。
- 已有 `D:\Apps\RemoteCommanderTrayData\<SID>` 用户个人目录 ACL 受限，但上级目录的过宽权限仍可能允许其他账户篡改或替换程序文件/目录项。这与多 Windows 用户安全隔离的目标冲突。
- **未修改 `D:\Apps` 或 D 盘 ACL**：该目录可能有其他程序；未经评估不能收紧整个公共父目录权限。正式安装保持原状态，安全整改列为 M6 阻塞。
- Windows 11 家庭版未具备可直接验证的 Windows Sandbox 环境；本机当前是管理员会话。没有创建系统用户，没有通过当前管理员会话冒充非管理员通过验收。
- 另一剩余门禁：在独立环境中验证托盘进程真正管理的 Remote 模式 MCP 工具调用。此前固定版 `0.3.0` stdio 的 `initialize`、`tools/list`、`tools/call` 已通过，但不等于托盘托管 Remote；此处为了不破坏聊天所依赖的 npx 连接而保持未测试。
- 因此 **M6 仍为进行中，尚不能标记 PASS，不进入 M7**；下一步应先明确 D 盘共享父目录 ACL 的安全处理方式，及获得独立非管理员账户/设备以完成剩余两项验收。
