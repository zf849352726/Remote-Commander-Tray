# M6 packaging

Build in Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-RemoteCommanderTray.ps1
```

Requires .NET SDK 8 and the Windows built-in IExpress utility.

New per-user default installation is D:\Apps\RemoteCommanderTray\<Windows-SID>. Settings and logs remain at D:\Apps\RemoteCommanderTrayData\<Windows-SID>. The previous shared binary at D:\Apps\RemoteCommanderTray\RemoteCommanderTray.exe is preserved as a legacy installation; there is no automatic migration. The source repository stays in D:\DesktopCommanderRemote. Old C: application data is never deleted or silently migrated.

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

M6 remains open: distinct-binary rollback already passed in an isolated real filesystem. Still required: installation by an actual non-administrator Windows account and MCP tools through tray-managed Remote mode in an independent session.

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

The new installer targets D:\Apps\RemoteCommanderTray\<Windows SID>. Minimal non-inheriting CreateDirectories grants have been provisioned on only the two application roots; each newly created SID directory has private ACLs. Actual non-administrator execution is still awaiting independent Windows account testing. The older shared EXE remains in place. M6 is not fully accepted until this and tray-managed Remote MCP mode are tested safely.

## SID-scoped per-user D-drive installation (preview.3)

For a newly signed-in Windows account, the installer target is:
`D:\Apps\RemoteCommanderTray\<Windows SID>\RemoteCommanderTray.exe`.
The per-account settings and log root remains
`D:\Apps\RemoteCommanderTrayData\<Windows SID>`.

Initial provisioning of the two **application parent directories** requires an
authorized administrator (done on this machine):

```powershell
.\tools\Provision-M6UserRoots.ps1
.\tools\Provision-M6UserRoots.ps1 -Apply
.\tools\Audit-M6InstallPermissions.ps1
```

The sole additional permission for Authenticated Users is **CreateDirectories on
each parent folder itself**; it is not inherited into a SID directory. The
installer creates only its current SID directory, verifies ownership and rejects
junctions or symlinks; installed program/data folders have private ACLs.

To verify the layout without HKCU changes or touching the existing Remote:

```powershell
.\tools\Test-M6PerUserInstall.ps1
```

The existing legacy shared EXE at `D:\Apps\RemoteCommanderTray\RemoteCommanderTray.exe`
is intentionally preserved. **Do not run the new installer over the existing
legacy registration**: migration of the old HKCU Run entry and shortcuts is
not yet accepted. Close the tray before any install/update. No live Remote
connection is stopped or taken over by these scripts.

The build artifact currently uses version `0.2.0-preview.3`. Tests performed
as an administrator or against mock directories are NOT evidence of
non-administrator self-install on a separate Windows account.

## Migrating a legacy shared installation to current SID (WIP)

The historical shared EXE at `D:\Apps\RemoteCommanderTray\RemoteCommanderTray.exe`
can be migrated using the project-only command after closing the tray:

```powershell
.\tools\Migrate-M6Legacy.ps1               # Read-only preflight
.\tools\Migrate-M6Legacy.ps1 -Apply        # Do actual migration
```

The script rejects unexpected Run values, unrelated shortcuts or uninstall
registration, wrong package checksum, or an already installed SID target.
It stages a verified private-SID EXE first, snapshots existing HKCU Run,
uninstall values and both .lnk files, then switches the Windows integration.
It leaves Windows StartupApproved, legacy EXE, user settings and the external
Remote untouched. Backups are under `verification/m6-migration-backups`.

If the transaction fails after the private EXE was staged, the old integration
is restored. After inspecting the prepared version and owner, explicitly
resume with `-Apply -ResumePrepared`; it refuses version mismatches.

Isolated proof without production integration changes:

```powershell
.\tools\Test-M6LegacyMigration.ps1
```

Do not confuse this migration with proof that a standard Windows account
can independently install, or with the separate tray-managed Remote
MCP acceptance test. Both remain open M6 gates.
