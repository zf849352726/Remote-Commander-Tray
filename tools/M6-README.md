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

## D drive ACL security gate (verified 2026-10-14)

Use the read-only audit before and after an installation:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Audit-M6InstallPermissions.ps1

Minimal ACL repair has been tested in a sandbox and applied to D:\Apps only:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Repair-M6InstallPermissions.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Repair-M6InstallPermissions.ps1 -Apply

The tool first refuses unrelated D:\Apps contents, saves the subtree ACL snapshot to verification/m6-acl-backups, and applies inheritable full control for current SID/SYSTEM/Administrators plus read/execute for Users. It does not change D:\ root permissions or official Remote credentials.

On this particular Windows host, native icacls /restore failed with error 1300. The sandbox-tested rollback is ONLY: icacls.exe "D:\Apps" /reset, and only if the original D:\Apps ACL was inherited-only and the D:\ parent ACL is unchanged. Rollback intentionally restores the former INSECURE Authenticated Users:FullControl inheritance. Do not run casually.

The current application installation is shared at D:\Apps\RemoteCommanderTray, writable only by the installing Windows SID. Other non-admin users cannot independently install to this shared location; per-user installation layout remains an unresolved M6 design/acceptance requirement. M6 is not fully accepted until this and tray-managed Remote MCP mode are tested safely.
