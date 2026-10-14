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

## 2026-10-14 — D:\Apps 最小权限整改已通过（用户授权）

- 实际改动范围仅为 `D:\Apps` 的 ACL 与其 Windows 自动继承，不修改 D 盘根目录。实施前检查 `D:\Apps` 只有本项目的 `RemoteCommanderTray`、`RemoteCommanderTrayData` 两个子目录，没有其他软件。
- 修改前根目录及两个子目录继承 `Authenticated Users: FullControl`。整改后，`D:\Apps` 停止继承 D 盘根目录的宽松权限：当前用户 SID、SYSTEM、Administrators = FullControl；BUILTIN\Users = ReadAndExecute。程序目录和数据根目录继承新的最小权限，单用户 SID 数据子目录维持独立 ACL。
- 新增 `tools/Repair-M6InstallPermissions.ps1`：限定只允许 D:\Apps 或项目 verification 隔离沙箱；先检查目录仅含项目自身子目录及无链接，备份完整子树 ACL 到 verification 后才应用；失败时只对原先全部继承的目标根目录执行已验证的 /reset 恢复方法。
- 隔离目录完整验证：先 dry-run → 应用 → 审计 PASS → /reset 恢复原继承权限 → 原始审计 FAIL（符合预期），文件内容不变；确认恢复方案可用。Windows 上原生 `icacls /restore` 返回错误 1300，因此**不能**把 /restore 视为验证通过的回滚方式。
- 真正执行 D:\Apps 修改后，`tools/Audit-M6InstallPermissions.ps1` 返回 `M6_INSTALL_ACL_AUDIT=PASS`；程序目录已不再向 Authenticated Users 授予写/删除权限。
- 更改前后正式 EXE SHA256 均为 `EC2C0C6BF1ECAFBBC556A468C26E0197C0817A36B62D62A7B095EBB2985E68C2`；现有 Remote PID `14924,17544,32716` 集合不变。
- 当前用户 SID 私有数据目录 ACL 保持，实际日志目录写/读通过。安装管理器 Check 正常，重新执行 M6 隔离生命周期测试（初装、升级、回滚、篡改保护、保留/删除配置、HKCU Run 不变）全部通过。
- 真实 ACL 备份位于 `verification/m6-acl-backups/D-Apps-20261014T081150623Z.acl`（本机不纳入 Git）。**仅当确需恢复且 D:\ 父 ACL 仍未变化时**，管理员可执行 `icacls.exe "D:\Apps" /reset` 恢复原继承机制；此操作会重新引入不安全的广泛写权限，不能作为正常运行方式。
- **安全门禁整改通过，但 M6 继续进行中。** 当前安装目录采用一个固定共享路径，只授予此用户 SID 写权限，因此其他标准用户不能自行维护共享程序；需要后续设计并验证每用户安装布局，不能虚报非管理员自助安装 PASS。托盘托管 Remote 模式的 MCP 实机验证也仍待隔离环境完成。

## 2026-10-14 — 多用户 SID 安装布局的安全改造（M6 继续进行中）

- 旧版正式安装 `D:\Apps\RemoteCommanderTray\RemoteCommanderTray.exe` 已保留，不自动迁移、不结束当前 npx Remote，也不更改官方授权。新版安装脚本的默认目标改为 `D:\Apps\RemoteCommanderTray\<当前 Windows SID>\RemoteCommanderTray.exe`，设置与日志仍在 `D:\Apps\RemoteCommanderTrayData\<当前 Windows SID>`。
- 新增 `tools/Provision-M6UserRoots.ps1`，对上述两个父目录只授予 `Authenticated Users` **CreateDirectories（此目录，不继承）**。不授予修改父目录文件、删除兄弟账户目录、向子目录继承写权限的能力；D:\Apps 本身仍为原安全 ACL。
- 安装脚本检查 SID 子目录路径、是否为 reparse point、现有目录的所有者是否为当前 Windows SID；拒绝访问被其他所有者预占的同名目录。私有安装目录和数据目录仅允许本人、SYSTEM、管理员组完全控制。
- 更新 `tools/Audit-M6InstallPermissions.ps1`，只对两个指定父目录精确允许非继承的 CreateDirectories ACE；其他广泛写/删除权限仍视为安全失败。
- 沙箱测试先执行 ACL 加固，再授予最小创建权限，复审 PASS。生产 `D:\Apps\RemoteCommanderTray`、`D:\Apps\RemoteCommanderTrayData` 也已经只赋予非继承 CreateDirectories，实际权限审计 PASS。旧安装 EXE SHA256 与远程进程 PID 集合均保持不变。
- `tools/Test-M6PerUserInstall.ps1` 已在隔离 D 盘环境通过：按当前 SID 创建独立安装和数据目录、检查所有者与私有 ACL、安装 SHA256、重复安装备份、回滚、保留数据卸载、HKCU 不变、已有 Remote PID 不变。
- 托盘程序单实例命名由用户名调整为当前 Windows SID，避免不同 Windows 域中用户名相同导致的命名冲突。
- Release 构建 0 warnings / 0 errors；Core 177/177、Windows 25/25、Windows 原生集成 10/10 均通过。新安装包使用 `0.2.0-preview.3` 版本标识，避免与旧文件同名混淆。
- **实际非管理员 Windows 用户安装及不同用户之间的隔离仍待独立普通账户验收**。当前测试在管理员账户运行，不能冒充标准用户。既有旧路径向 SID 新路径的迁移尚未执行；其 HKCU Run、开始菜单/桌面快捷方式迁移需另行验证。
- **托盘真正托管 Remote 模式的 MCP 验收仍未执行**，必须在不影响现有远程连接的独立设备或会话完成。M6 保持进行中；M7 未开始。

## M6 SID 安装候选包与回归测试补充

- 正式默认路径：`D:\Apps\RemoteCommanderTray\<Windows SID>`；用户数据路径：`D:\Apps\RemoteCommanderTrayData\<Windows SID>`。
- Windows 实际目录 `D:\Apps\RemoteCommanderTray` 与 `D:\Apps\RemoteCommanderTrayData` 已应用**非继承** CreateDirectories 最小权限。只读安全审计返回 PASS，旧共享程序 EXE 与 Remote PID 集合未改变。
- 隔离 `Test-M6PerUserInstall.ps1` 测试结果：`M6_SID_ISOLATION_TEST=PASS`。已经覆盖按当前 Windows SID 安装程序、独立私有 ACL、发行哈希、重复安装、回滚、卸载保留数据及 HKCU 与 Remote 不变。
- Release 构建成功（0 警告/错误），Core 177/177，Windows 25/25，Native 10/10 全部通过。
- 新候选 `verification\m6-dist\RemoteCommanderTray-Setup-0.2.0-preview.3-win-x64.exe` 已经实际自解压并验证包含新版按 SID 安装脚本、LICENSE 和发行清单。
- 安装包 SHA256：`75029107A60E8D74F93583DCC4883AC933B016B833D23AC76D73943EDECD4886`；内部 EXE SHA256：`7FE50B7E2538FDF05F5A7F6AC11B3EBC6848F007A616B7FE598D9F993BCBEB98`。
- 旧版已安装 EXE 及当前用户的 Windows 启动注册仍保留在共享旧位置；**没有直接迁移**到新的 SID 目录，也没有自动运行第二个 Remote。
- 遗留风险：父目录允许其他标准用户创建任意子文件夹，可能出现 SID 目录名被抢占的拒绝服务；安装器通过目录所有者检查拒绝使用预先抢占的 SID 目录，但尚未进行真实跨用户测试。
- M6 **尚未完整通过**：真正标准用户账户自助安装（当前仅在管理员账户执行隔离测试）、遗留安装的受控迁移，以及托盘托管 Remote 模式真实 MCP 工具调用均待独立环境验收。

## 2026-10-14 — 旧共享安装安全迁移至 SID 独立目录：已真实执行

- 新增 `tools/Migrate-M6Legacy.ps1` 和 `tools/Test-M6LegacyMigration.ps1`；迁移前严格检查旧 EXE、HKCU Run 的**精确路径**、旧卸载登记、两个旧快捷方式、无正在运行的托盘进程、候选 EXE SHA256、固定 Remote 0.3.0。任何非预期注册值都会拒绝迁移。
- 工具先创建当前 SID 的私有程序目录并校验 EXE，再备份 HKCU Run、卸载登记、两个快捷方式及 StartupApproved 只读状态，最后更新 HKCU Run、卸载登记和快捷方式。原共享 EXE 和现有数据不删除，StartupApproved 状态不修改，不启动或停止 Remote。
- 隔离场景通过：dry-run 只读；正常迁移；模拟更新 HKCU Run 后故障并恢复原 Run、卸载登记及快捷方式；检查预安装 EXE 后通过 `-ResumePrepared` 继续；重复迁移被拒绝；测试对真实 HKCU Run 与 Remote PID 无影响。证据：`verification/m6-migration-resume-test.log`，`M6_MIGRATION_FIXTURE=PASS`。
- 生产环境预检：`verification/m6-migration-preflight.log`，`M6_MIGRATION_PREFLIGHT=PASS`。正式执行：`verification/m6-migration-real-apply.log`，`M6_LEGACY_MIGRATION=PASS`。真正 SID 版安装路径为 `D:\Apps\RemoteCommanderTray\<当前 SID>\RemoteCommanderTray.exe`。
- 当前 HKCU Run、开始菜单/桌面快捷方式、卸载登记已指向 SID 新版；两个 EXE 均在 D 盘：旧版 EXE SHA256 `EC2C0C6BF1ECAFBBC556A468C26E0197C0817A36B62D62A7B095EBB2985E68C2`，新版 EXE SHA256 `5289501ECEB5C0C4262B2B81DCEF1637D1CF8F9E404DFF162B9B6A317E7B0BB2`。安装后哈希复核及账户目录所有者检查已通过。
- 生产回滚资料位于（本机、不纳入 Git）`verification/m6-migration-backups/migration-20261014T085128233Z`。工具发生中途错误会恢复入口，但**不会擅自删除已复制的新 SID 文件夹**；可在检查其签名/所有者后显式使用 `-ResumePrepared`。
- 正式新 EXE 已启动验证：保持运行并在 D 盘写日志，设置 `startAgentOnLaunch=false`，没有创建额外 Remote。仅终止本次测试启动且经确认没有子进程的托盘，不影响现有 npx Remote。
- 已重新生成 WIP `0.2.0-preview.3` 自解压安装包，SHA256 `41BB9B2F0E5F07ECDB960F3B97AC22AE57332B7E453B67B292178849C2B5E59A`。本机正式迁移使用此包的验证 staging 版本。
- **M6 仍未通过完整阶段门禁**：现有验证使用管理员账户；尚无真实非管理员账户登录下的独立安装/卸载验收，且托盘管理的 Remote 模式 MCP 实际调用未在安全隔离会话测试。不能把现有 stdio MCP 或当前 npx Remote 通信当作托盘托管测试。M7 尚未开始。

## 2026-10-14 — 真实标准用户与托盘托管 Remote：门禁准备（未验收）

- 已创建 `tools/Test-M6StandardAccount.ps1`，仅供交互登录的 Windows **真实标准用户**执行。默认只读预检，`-RunAcceptance` 会验证应用文件 SHA256、私有 SID 目录所有者和 ACL、真实 HKCU Run/卸载项/快捷方式、升级/回滚及保留数据卸载，并比较 Node 进程 PID。
- 脚本必须先验证自己不属于 Administrators、HKCU 用户配置文件已加载，且当前 SID 下没有旧设置或安装注册，否则拒绝运行并保留数据。
- 管理员账户执行脚本的负向安全测试返回 `NOT_STANDARD_USER`，符合预期，**并不代表标准用户门禁 PASS**。
- 当前机器 C 盘可用空间约 0.28 GB，已有标准用户沙箱账户配置文件未加载。为避免创建系统残留账户、写满 C 盘或以后台 S4U 任务代替正常用户登录，本次没有新建/重置任何账户，也未执行其他用户的真实安装。
- 本机只有一个在线的 Desktop Commander Remote 设备，当前连接依赖外部 npx Remote。禁止让托盘启动并接管同一 Remote；托盘托管真实 Remote MCP 工具调用须独立 VM/设备。
- **剩余这两项仍未 PASS**。详见 `docs/M6-remaining-gates.md`；M6 仍进行中，M7 未开始。

## 2026-10-14 — 最后两项门禁准备回归结果

- `Test-M6StandardAccount.ps1` PowerShell 解析检查 PASS；在当前管理员账户下执行预检正确拒绝（`NOT_STANDARD_USER`），没有触碰其 HKCU 或 D: 目录；这仅是安全负向测试，并非标准用户安装通过。
- 修正 `Audit-M6InstallPermissions.ps1` 成功时明确返回 `exit 0`，防止前序负向脚本退出码污染审计结论。真实 D:\Apps ACL 审计返回 0 且 `M6_INSTALL_ACL_AUDIT=PASS`。
- 安装生命周期回归 PASS，覆盖 D: 目录、备份/回滚/卸载、设置保留及 HKCU 不变。
- .NET Core 177/177 + Windows 25/25，共 202/202 项 PASS；Windows 原生集成 10/10 PASS。日志保存在本地 ignored `verification/m6-standard-prep-*.log`。
- 本次没有新建用户、修改已有标准用户配置文件、创建计划任务或触碰当前 npx Remote。真正标准用户的交互式验收及另一独立设备的托盘 Remote MCP 验收仍然未运行，M6 继续保持 WIP。

## 2026-10-14 — 用户手动切换后：托盘托管 Remote 实际 MCP 门禁通过

- 用户确认可以直接操作 Windows 本机，并在旧 `npx Remote` 停止后手动启动已迁移到 SID 目录的 `RemoteCommanderTray.exe`，通过托盘选择 `Start agent`，然后报告已通过新托盘连接回 ChatGPT。
- 连接恢复后独立核查 `mcp__Remote_Desktop_Commander__list_devices`，唯一设备 `Administrator` 为 `Online`、Remote 版本 `0.3.0`。本次 MCP ping 返回 `pong`。
- Windows 进程树真实观测：`RemoteCommanderTray.exe` PID **9764**（D 盘当前 SID 安装版 `0.2.0-preview.3`）→ `node.exe` PID **31892**（其命令行指向 D 盘全局 `@wonderwhy-er/desktop-commander@0.3.0` 的 `remote` 入口，无 npx-cli）→ `node.exe` PID **35756**（MCP 子进程）。未发现正在运行的旧 npx Remote 进程。
- D 盘日志 `D:\Apps\RemoteCommanderTrayData\<SID>\logs\agent.log` 真实记录：`Agent started (pid 31892)`、`Starting MCP Device`、`Connected to Remote MCP`、`Device online`。用户配置 `startAgentOnLaunch=false`，本轮为手动启动。
- **经该新设备上的真实 MCP 工具通道执行 `list_directory`**，目标 `D:\DesktopCommanderRemote\verification\m6-runtime-probe`，工具实际返回 `bin`、`obj`、`Program.cs`、`m6-runtime-probe.csproj`。这证明 MCP 工具读取端到端通过，不是仅检查 Online 或单独启动 stdio 模拟。
- 结论：**M6 托盘托管 Remote 连接+实际 MCP 工具调用 = PASS**。期间没有由助手停止/重启任何 Remote 进程。
- 托盘 `Stop agent` → 恢复连接的实际循环尚未验收；在用户仅依赖该连接时，助手不主动停止它，也不能宣称此循环通过。
- **M6 总 Gate 仍未 PASS**：尚未在真正非管理员 Windows 交互式会话中执行独立安装、升级、回滚、卸载验收。此前管理员负向防护测试不得代替该门禁。M7 未开始。
