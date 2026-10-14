# M6 packaging

Build in Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-RemoteCommanderTray.ps1
```

Requires .NET SDK 8 and the Windows built-in IExpress utility.

Default formal installation is D:\Apps\RemoteCommanderTray. Settings and logs are under D:\Apps\RemoteCommanderTrayData\<Windows-SID> for per-account separation. The source repository stays in D:\DesktopCommanderRemote. Old C: application data is never deleted or silently migrated.

Output is under `verification\m6-dist` (excluded from Git). No changes are made to Windows login startup or Desktop Commander credentials when building.

Runtime CLI dependency must be explicitly installed by the user only **after verifying no other Remote is running**:

```powershell
npm install -g @wonderwhy-er/desktop-commander@0.3.0
```

The tray now verifies the exact version in the global npm package manifest; it never uses npx @latest automatically. The installer itself does not install npm packages.

For safe testing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-M6Lifecycle.ps1
```

This test only reads/writes `verification\m6-sandbox` and passes `-TestMode` to management scripts. It never sets HKCU Run, creates shortcuts, or touches official Remote credentials. Do not execute the built installer on the production computer while the current Remote session is needed.

Upgrade/rollback: fully exit **the tray** first; never kill an unrelated Remote. The manager stores one previously installed EXE with SHA256 verification. CLI version rollback requires separate explicit manual npm action. `Uninstall` preserves app settings/logs by default; `-RemoveUserData` requires a DELETE confirmation outside test mode.

For unattended **keep-settings** removal on the designated D-drive install, use the installed manager with `-Action Uninstall -KeepUserData` after exiting the tray. This is an explicit keep-data option; default GUI uninstall still asks whether to retain data. It never removes official Desktop Commander credentials. Do not run a second Remote while the existing npx Remote is connected.

M6 remains open: verify with a separate non-administrator Windows account, test rollback between distinct application builds, and verify MCP operations from tray-managed Remote mode in an independent session before marking M6 PASS.

## Distinct EXE rollback and installer directory permissions

To publish a second test binary without touching the installed tray, build `0.2.0-preview.2` self-contained win-x64 to `verification/m6-distinct-v2/publish` using the same publish switches as `Build-RemoteCommanderTray.ps1`, with `-p:Version=0.2.0-preview.2`. Then run:

```powershell
.\tools\Test-M6DistinctRollback.ps1
```

The test installs the two **different hashed EXEs** into `verification`, checks backup metadata, rolls back to the earlier version, rejects tampered backups, confirms retained settings and leaves the current Remote and HKCU Run untouched. The latest test evidence is `verification/m6-distinct-rollback.log`.

Read-only security gate:

```powershell
.\tools\Audit-M6InstallPermissions.ps1
```

**Current machine: FAIL.** `D:\Apps`, `D:\Apps\RemoteCommanderTray` and `D:\Apps\RemoteCommanderTrayData` inherit `Authenticated Users: FullControl`. Fixing the parent ACL requires assessing other software in `D:\Apps`; the build/test scripts must not silently alter it. The SID-specific data folder itself is private but parent permissions still matter.

Real non-administrator setup/uninstall and tray-managed Remote MCP tests need a separate safe Windows login/VM so the live ChatGPT Remote connection remains available. Do not claim these were passed from the administrator login or by a separate stdio MCP process. M6 stays open until the remaining gates are verified.
