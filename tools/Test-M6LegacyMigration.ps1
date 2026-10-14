[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo='D:\DesktopCommanderRemote'
$fixture=Join-Path $repo 'verification\m6-migration-fixture'
$migrate=Join-Path $repo 'tools\Migrate-M6Legacy.ps1'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$old=Join-Path $fixture 'Old\RemoteCommanderTray.exe'
$new=Join-Path (Join-Path (Join-Path $fixture 'New') $sid) 'RemoteCommanderTray.exe'
$oldRun='"'+$old+'" --autostart'
$newRun='"'+$new+'" --autostart'
$legacy=Split-Path -Parent $old
$approval='EXISTING_DISABLED_WINDOWS_STARTUPAPP_APPROVAL'
function Setup-Fixture {
    if(Test-Path $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
    foreach($path in @((Join-Path $fixture 'Old'),(Join-Path $fixture 'Desktop'),(Join-Path $fixture 'Programs'))){
        New-Item -ItemType Directory -Force $path|Out-Null
    }
    Set-Content -LiteralPath $old -Value 'LEGACY-BINARY-IMMUTABLE' -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $repo 'tools\Manage-RemoteCommanderTray.ps1') -Destination (Join-Path $legacy 'Manage-RemoteCommanderTray.ps1')
    $original=[ordered]@{
        run=$oldRun
        installLocation=$legacy
        uninstallString=('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $legacy 'Manage-RemoteCommanderTray.ps1')+'" -Action Uninstall')
        displayName='Remote Commander Tray'
        publisher='Remote Commander Tray contributors'
    }
    $original|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $fixture 'integration.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $fixture 'startup-approval.txt') -Value $approval -Encoding UTF8
    $shell=New-Object -ComObject WScript.Shell
    foreach($path in @((Join-Path $fixture 'Desktop\Remote Commander Tray.lnk'),(Join-Path $fixture 'Programs\Remote Commander Tray.lnk'))){
        $link=$shell.CreateShortcut($path)
        $link.TargetPath=$old
        $link.WorkingDirectory=$legacy
        $link.Save()
    }
}
function Check-State([string]$run,[string]$exe) {
    $state=Get-Content -Raw (Join-Path $fixture 'integration.json')|ConvertFrom-Json
    if($state.run -cne $run){throw "Unexpected integration Run: $($state.run)"}
    $shell=New-Object -ComObject WScript.Shell
    foreach($path in @((Join-Path $fixture 'Desktop\Remote Commander Tray.lnk'),(Join-Path $fixture 'Programs\Remote Commander Tray.lnk'))){
        if($shell.CreateShortcut($path).TargetPath -ine $exe){throw 'Shortcut target mismatch.'}
    }
    if((Get-Content -Raw (Join-Path $fixture 'startup-approval.txt')).Trim() -cne $approval){throw 'Startup approval mutated.'}
}
$nodesBefore=@(Get-CimInstance Win32_Process |
    Where-Object {$_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander'} |
    Select-Object -ExpandProperty ProcessId)
$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$realRun=(Get-ItemProperty $runKey -ErrorAction SilentlyContinue).RemoteCommanderTray
try {
    Setup-Fixture
    & $migrate -FixtureRoot $fixture
    Check-State $oldRun $old
    if(Test-Path $new){throw 'Preflight accidentally installed binary.'}
    Write-Output 'PASS fixture migration preflight read-only'

    $failed=$false
    try { & $migrate -FixtureRoot $fixture -Apply -InjectFailureAfterRun }
    catch {$failed=$true;Write-Output 'EXPECTED_ROLLBACK_TRIGGERED'}
    if(!$failed){throw 'Failure injection should have thrown.'}
    Check-State $oldRun $old
    if((Get-Content -Raw $old) -notmatch 'LEGACY-BINARY-IMMUTABLE'){throw 'Legacy binary changed on failure.'}
    Write-Output 'PASS injected failure restores legacy Run and shortcuts exactly'
    & $migrate -FixtureRoot $fixture -Apply -ResumePrepared
    Check-State $newRun $new
    Write-Output 'PASS interrupted migration can resume after checking prepared EXE integrity'

    Setup-Fixture
    & $migrate -FixtureRoot $fixture -Apply
    Check-State $newRun $new
    if(!(Test-Path $old) -or !(Test-Path $new)){throw 'Legacy or new binary missing.'}
    $manifest=Get-Content -Raw (Join-Path $repo 'verification\m6-dist\staging\release-manifest.json')|ConvertFrom-Json
    if((Get-FileHash $new -Algorithm SHA256).Hash -cne $manifest.sha256){throw 'Migrated EXE hash mismatch.'}
    $state=Get-Content -Raw (Join-Path $fixture 'integration.json')|ConvertFrom-Json
    if($state.installLocation -ine (Split-Path -Parent $new)){throw 'New uninstaller path mismatch.'}
    Write-Output 'PASS new EXE, Run, shortcuts, uninstaller, legacy binary retained'
    $rejected=$false
    try { & $migrate -FixtureRoot $fixture -Apply |Out-Null }
    catch {$rejected=$true}
    if(!$rejected){throw 'Duplicate migration was accepted.'}
    Write-Output 'PASS duplicate migration refused'
    $realAfter=(Get-ItemProperty $runKey -ErrorAction SilentlyContinue).RemoteCommanderTray
    if($realRun -cne $realAfter){throw 'Real HKCU Run mutated by fixture.'}
    $nodesAfter=@(Get-CimInstance Win32_Process |
        Where-Object {$_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander'} |
        Select-Object -ExpandProperty ProcessId)
    if(@(Compare-Object $nodesBefore $nodesAfter).Count -ne 0){throw 'Active Remote PIDs changed.'}
    Write-Output 'PASS real HKCU and Remote unchanged'
    Write-Output 'M6_MIGRATION_FIXTURE=PASS'
}
finally{
    if(Test-Path $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
