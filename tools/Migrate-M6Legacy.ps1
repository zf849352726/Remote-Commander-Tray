# Transactional transition from the legacy shared install to current-SID installation.
# The old binary is never deleted. No Remote agent is launched or stopped.
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$FixtureRoot,
    [switch]$InjectFailureAfterRun,
    [switch]$ResumePrepared
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo='D:\DesktopCommanderRemote'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$stage=Join-Path $repo 'verification\m6-dist\staging'
$manager=Join-Path $repo 'tools\Manage-RemoteCommanderTray.ps1'
$root='D:\Apps\RemoteCommanderTray'
$legacyExe=Join-Path $root 'RemoteCommanderTray.exe'
$target=Join-Path $root $sid
$data=Join-Path 'D:\Apps\RemoteCommanderTrayData' $sid
$testMode=![string]::IsNullOrWhiteSpace($FixtureRoot)
if ($testMode) {
    $FixtureRoot=[IO.Path]::GetFullPath($FixtureRoot).TrimEnd('\')
    $allowed=Join-Path $repo 'verification\m6-migration-fixture'
    if ($FixtureRoot -ine $allowed) { throw 'Migration fixture must be the dedicated verification directory.' }
    $root=Join-Path $FixtureRoot 'Old'
    $legacyExe=Join-Path $root 'RemoteCommanderTray.exe'
    $target=Join-Path (Join-Path $FixtureRoot 'New') $sid
    $data=Join-Path (Join-Path $FixtureRoot 'Data') $sid
}
if($InjectFailureAfterRun -and !$testMode){throw 'Failure injection is permitted only in the verification fixture.'}
$newExe=Join-Path $target 'RemoteCommanderTray.exe'
$oldRun='"'+$legacyExe+'" --autostart'
$newRun='"'+$newExe+'" --autostart'
$legacyInstallDir=[IO.Path]::GetDirectoryName($legacyExe)
$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$uninstallKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RemoteCommanderTray'
$approvalKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$stateFile=if($testMode){Join-Path $FixtureRoot 'integration.json'}else{$null}
$backupRoot=Join-Path $repo 'verification\m6-migration-backups'
function Get-State {
    if($testMode){return Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8|ConvertFrom-Json}
    $run=(Get-ItemProperty -Path $runKey -Name RemoteCommanderTray -ErrorAction Stop).RemoteCommanderTray
    $un=Get-ItemProperty -Path $uninstallKey -ErrorAction Stop
    return [pscustomobject]@{
        run=$run
        installLocation=$un.InstallLocation
        uninstallString=$un.UninstallString
        displayName=$un.DisplayName
        publisher=$un.Publisher
    }
}
function Write-State($state){
    if($testMode){
        $state|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $stateFile -Encoding UTF8
        return
    }
    New-ItemProperty -Path $runKey -Name 'RemoteCommanderTray' -Value $state.run -PropertyType String -Force|Out-Null
    Set-ItemProperty -Path $uninstallKey -Name InstallLocation -Value $state.installLocation
    Set-ItemProperty -Path $uninstallKey -Name UninstallString -Value $state.uninstallString
    Set-ItemProperty -Path $uninstallKey -Name DisplayName -Value $state.displayName
    Set-ItemProperty -Path $uninstallKey -Name Publisher -Value $state.publisher
}
function Get-ShortcutPaths {
    if($testMode){
        return @((Join-Path $FixtureRoot 'Desktop\Remote Commander Tray.lnk'),
                 (Join-Path $FixtureRoot 'Programs\Remote Commander Tray.lnk'))
    }
    return @(
        (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Remote Commander Tray.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'Remote Commander Tray.lnk'))
}
function Get-Approval {
    if($testMode){return (Get-Content -Raw (Join-Path $FixtureRoot 'startup-approval.txt'))}
    $key=Get-ItemProperty -Path $approvalKey -ErrorAction SilentlyContinue
    if(!$key){return $null}
    $p=$key.PSObject.Properties['RemoteCommanderTray']
    return $(if($p){[Convert]::ToBase64String([byte[]]$p.Value)}else{$null})
}
function Change-Shortcut([string]$path,[string]$exe,[string]$working){
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut($path)
    $link.TargetPath=$exe
    $link.WorkingDirectory=$working
    $link.Save()
}
$links=@(Get-ShortcutPaths)
if((Test-Path -LiteralPath $newExe) -and !$ResumePrepared){throw 'SID install already exists. Use ResumePrepared only after a verified interrupted migration.'}
if(!(Test-Path -LiteralPath $legacyExe)){throw 'Legacy executable is absent.'}
if(!(Test-Path -LiteralPath (Join-Path $stage 'release-manifest.json'))){throw 'New package manifest missing.'}
if(Get-Process RemoteCommanderTray -ErrorAction SilentlyContinue){throw 'Exit the tray before migration. No process is terminated.'}
$manifest=Get-Content -Raw (Join-Path $stage 'release-manifest.json') -Encoding UTF8|ConvertFrom-Json
$source=Join-Path $stage 'RemoteCommanderTray.exe'
if(!(Test-Path $source) -or
    (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $manifest.sha256 -or
    $manifest.remoteVersion -cne '0.3.0'){throw 'New package integrity or pinned version failed.'}
if($ResumePrepared){
    if(!(Test-Path -LiteralPath $newExe)){throw 'No prepared installation exists for recovery.'}
    if((Get-FileHash -LiteralPath $newExe -Algorithm SHA256).Hash -cne $manifest.sha256){
        throw 'Prepared EXE does not match the verified package.'
    }
    $owner=(Get-Acl -LiteralPath (Split-Path -Parent $newExe)).GetOwner([Security.Principal.SecurityIdentifier]).Value
    if($owner -cne $sid){throw 'Prepared install is owned by a different Windows SID.'}
}
$original=Get-State
if($original.run -cne $oldRun){throw 'HKCU Run does not exactly match the expected legacy path.'}
if($original.installLocation -ine $legacyInstallDir){throw 'Uninstaller does not match this legacy install.'}
if($original.uninstallString -notlike ('*'+(Join-Path $legacyInstallDir 'Manage-RemoteCommanderTray.ps1')+'*')){
    throw 'Uninstall command was not registered by the legacy application.'
}
$shell=New-Object -ComObject WScript.Shell
foreach($link in $links){
    if(!(Test-Path -LiteralPath $link)){throw "Missing registered legacy shortcut: $link"}
    $entry=$shell.CreateShortcut($link)
    if($entry.TargetPath -ine $legacyExe){throw "Shortcut points to an unrelated executable: $link"}
}
$approvedBefore=Get-Approval
$legacyHash=(Get-FileHash -LiteralPath $legacyExe -Algorithm SHA256).Hash
$remoteBefore=@(Get-CimInstance Win32_Process|Where-Object{
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander'
}|Select-Object -ExpandProperty ProcessId)
Write-Output ('LEGACY_EXE='+$legacyExe)
Write-Output ('TARGET_EXE='+$newExe)
Write-Output ('LEGACY_SHA256='+$legacyHash)
Write-Output ('NEW_SHA256='+$manifest.sha256)
Write-Output ('REMOTE_PID_SET='+($remoteBefore -join ','))
if(!$Apply){Write-Output 'M6_MIGRATION_PREFLIGHT=PASS (no modifications)';return}

New-Item -ItemType Directory -Force $backupRoot|Out-Null
$backupDir=Join-Path $backupRoot ('migration-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
if(Test-Path $backupDir){throw 'Backup directory collision.'}
New-Item -ItemType Directory -Path $backupDir|Out-Null
$original|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $backupDir 'integration.json') -Encoding UTF8
if($null -ne $approvedBefore){[IO.File]::WriteAllText((Join-Path $backupDir 'startup-approval.txt'),[string]$approvedBefore)}
for($i=0;$i -lt $links.Count;$i++){
    Copy-Item -LiteralPath $links[$i] -Destination (Join-Path $backupDir ("shortcut-$i.lnk"))
}
$next=[pscustomobject]@{
    run=$newRun
    installLocation=$target
    uninstallString=('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $target 'Manage-RemoteCommanderTray.ps1')+'" -Action Uninstall')
    displayName=$original.displayName
    publisher=$original.publisher
}
$updatedWindows=$false
try {
    # Fully stage and verify the new private executable BEFORE touching HKCU.
    if(!$ResumePrepared){
        if($testMode){
            & $manager -Action Install -TestMode -PrepareOnly -InstallDir $target -DataDir $data -SourceDir $stage|Out-Null
        }else{
            & $manager -Action Install -PrepareOnly -SourceDir $stage|Out-Null
        }
    }else{
        Write-Output 'Reusing an already-verified SID installation after the previous registration rollback.'
    }
    if((Get-FileHash -LiteralPath $newExe -Algorithm SHA256).Hash -cne $manifest.sha256){
        throw 'Staged private EXE digest mismatch.'
    }
    # Preserve the user's StartupApproved policy; only the current user's
    # Run path, registered uninstaller, and these two owned shortcuts change.
    $updatedWindows=$true
    $intermediate=[pscustomobject]@{
        run=$newRun
        installLocation=$original.installLocation
        uninstallString=$original.uninstallString
        displayName=$original.displayName
        publisher=$original.publisher
    }
    Write-State $intermediate
    if($InjectFailureAfterRun){throw 'Injected verification failure after HKCU Run change.'}
    Write-State $next
    foreach($link in $links){Change-Shortcut $link $newExe $target}
    $now=Get-State
    if($now.run -cne $newRun -or $now.installLocation -ine $target){
        throw 'Windows registration did not point to new install.'
    }
    foreach($link in $links){
        if($shell.CreateShortcut($link).TargetPath -ine $newExe){throw 'Shortcut did not migrate.'}
    }
    if((Get-Approval) -cne $approvedBefore){throw 'Startup approval was modified.'}
    if((Get-FileHash -LiteralPath $legacyExe -Algorithm SHA256).Hash -cne $legacyHash){throw 'Legacy EXE was changed.'}
    $remoteAfter=@(Get-CimInstance Win32_Process|Where-Object{
        $_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander'
    }|Select-Object -ExpandProperty ProcessId)
    if(@(Compare-Object $remoteBefore $remoteAfter).Count -ne 0){throw 'Remote PID set changed during migration.'}
    Write-Output ('M6_LEGACY_MIGRATION=PASS; BACKUP='+$backupDir)
    Write-Output 'Old shared EXE remains intact for recovery; no Remote restarted.'
}
catch {
    $reason=$_.Exception.Message
    if($updatedWindows){
        try {
            Write-State $original
            for($i=0;$i -lt $links.Count;$i++){
                Copy-Item -LiteralPath (Join-Path $backupDir ("shortcut-$i.lnk")) -Destination $links[$i] -Force
            }
            if((Get-State).run -cne $oldRun){throw 'Run registry rollback mismatch.'}
            Write-Output 'M6_MIGRATION_ROLLBACK=PASS'
        }catch{
            throw ('Migration failed AND integration rollback failed: '+$reason+'; recovery: '+$backupDir+'; '+$_.Exception.Message)
        }
    }
    throw ('Migration failed safely: '+$reason+'; backup: '+$backupDir)
}
