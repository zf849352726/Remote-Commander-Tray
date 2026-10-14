[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo='D:\DesktopCommanderRemote'
$root=Join-Path $repo 'verification\m6-acl-sandbox\PerUser-Install'
$stage=Join-Path $repo 'verification\m6-dist\staging'
$manager=Join-Path $repo 'tools\Manage-RemoteCommanderTray.ps1'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$install=Join-Path (Join-Path $root 'RemoteCommanderTray') $sid
$data=Join-Path (Join-Path $root 'RemoteCommanderTrayData') $sid
$targetExe=Join-Path $install 'RemoteCommanderTray.exe'
$reg='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
function RunValue{
    $k=Get-ItemProperty $reg -ErrorAction SilentlyContinue
    if($k){$v=$k.PSObject.Properties['RemoteCommanderTray'];if($v){return $v.Value}}
    return $null
}
$before=RunValue
$nodesBefore=@(Get-CimInstance Win32_Process |
    Where-Object {$_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander'} |
    Select-Object -ExpandProperty ProcessId)
if(Test-Path $root){throw 'Test sandbox exists; do not delete or overwrite.'}
New-Item -ItemType Directory -Force (Join-Path $root 'RemoteCommanderTray'),(Join-Path $root 'RemoteCommanderTrayData')|Out-Null
try {
    & (Join-Path $repo 'tools\Repair-M6InstallPermissions.ps1') -Root $root -Apply
    & (Join-Path $repo 'tools\Provision-M6UserRoots.ps1') -Root $root -Apply
    & (Join-Path $repo 'tools\Audit-M6InstallPermissions.ps1') -InstallDir (Join-Path $root 'RemoteCommanderTray') -DataBaseDir (Join-Path $root 'RemoteCommanderTrayData')
    & $manager -Action Install -TestMode -InstallDir $install -DataDir $data -SourceDir $stage |Out-Null
    if(!(Test-Path $targetExe)){throw 'Per-user SID-scoped EXE missing.'}
    $srcDigest=(Get-Content -Raw (Join-Path $stage 'release-manifest.json') | ConvertFrom-Json).sha256
    if((Get-FileHash $targetExe -Algorithm SHA256).Hash -cne $srcDigest){throw 'Per-user EXE digest mismatch.'}
    foreach($p in @($install,$data)){
        $acl=Get-Acl $p
        $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if($owner -cne $sid){throw "Owner mismatch at $p"}
        $broad=@($acl.Access|Where-Object {
            $who=$_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            $who -in @('S-1-5-11','S-1-1-0','S-1-5-32-545')
        })
        if($broad.Count -ne 0){throw "Private user directory inherited broad access: $p"}
    }
    Write-Output 'PASS SID-scoped install and data dirs are owned by the invoking SID with no broad ACL'
    & $manager -Action Install -TestMode -InstallDir $install -DataDir $data -SourceDir $stage |Out-Null
    if(!(Test-Path (Join-Path $install 'rollback\RemoteCommanderTray.exe'))){throw 'Version backup missing.'}
    & $manager -Action Rollback -TestMode -InstallDir $install -DataDir $data |Out-Null
    Write-Output 'PASS SID-scoped upgrade and rollback'
    & $manager -Action Uninstall -TestMode -KeepUserData -InstallDir $install -DataDir $data |Out-Null
    if((Test-Path $targetExe) -or !(Test-Path (Join-Path $data 'settings.json'))){throw 'SID-scoped uninstall or data preserve failed.'}
    Write-Output 'PASS SID-scoped uninstall preserving data'
    if((RunValue) -cne $before){throw 'Test changed user Run key.'}
    $nodesAfter=@(Get-CimInstance Win32_Process |
        Where-Object {$_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander'} |
        Select-Object -ExpandProperty ProcessId)
    if(@(Compare-Object $nodesBefore $nodesAfter).Count -ne 0){throw 'Test changed Remote process list.'}
    Write-Output 'PASS HKCU and active Remote PIDs unchanged'
    Write-Output 'M6_SID_ISOLATION_TEST=PASS'
}
finally{
    if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
