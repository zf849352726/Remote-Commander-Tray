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
