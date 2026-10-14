# M6 standard-user acceptance. Execute ONLY from an ordinary, signed-in
# Windows standard user's interactive desktop session (not a scheduled S4U task).
# Preflight is read-only; -RunAcceptance performs install/update/rollback/uninstall
# using this account's HKCU and isolated SID directories. No Remote is launched.
[CmdletBinding()]
param(
    [switch]$RunAcceptance,
    [string]$SourceDir = 'D:\DesktopCommanderRemote\verification\m6-dist\staging'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$sid=$identity.User.Value
$adminSid='S-1-5-32-544'
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
$adminGroup=[Security.Principal.SecurityIdentifier]::new($adminSid)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
    @($identity.Groups|Where-Object{$_.Value -eq $adminSid}).Count -gt 0) {
    throw 'NOT_STANDARD_USER: this account belongs to Administrators or is elevated. No files/registry changed.'
}
# Verify membership using Windows local group information too. Do not accept a
# UAC-filtered administrator or token-only impersonation as a separate user.
$admins=Get-LocalGroup -SID $adminSid -ErrorAction Stop
$members=@(Get-LocalGroupMember -Group $admins.Name -ErrorAction Stop)
if(@($members|Where-Object{$_.SID.Value -eq $sid}).Count -gt 0) {
    throw 'NOT_STANDARD_USER: explicit member of the local Administrators group.'
}
$profile=[Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
$desktop=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
$startPrograms=[Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
$profileReg=(Get-ItemProperty 'HKCU:\Volatile Environment' -Name USERPROFILE -ErrorAction Stop).USERPROFILE
if(!$profile -or !$desktop -or !$startPrograms -or
   !$profileReg -or
   [IO.Path]::GetFullPath($profile).TrimEnd('\') -ine [IO.Path]::GetFullPath($profileReg).TrimEnd('\') -or
   !(Test-Path -LiteralPath ("Registry::HKEY_USERS\"+$sid))) {
    throw 'NO_INTERACTIVE_USER_PROFILE: HKCU is not tied to the logged-in standard account.'
}
$install=Join-Path 'D:\Apps\RemoteCommanderTray' $sid
$data=Join-Path 'D:\Apps\RemoteCommanderTrayData' $sid
$exe=Join-Path $install 'RemoteCommanderTray.exe'
$manager=Join-Path $SourceDir 'Manage-RemoteCommanderTray.ps1'
$manifest=Join-Path $SourceDir 'release-manifest.json'
$uninstall='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RemoteCommanderTray'
$run='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$links=@((Join-Path $desktop 'Remote Commander Tray.lnk'),
         (Join-Path $startPrograms 'Remote Commander Tray.lnk'))
if(!(Test-Path -LiteralPath $manager) -or !(Test-Path -LiteralPath $manifest)) {
    throw 'Release staging package is inaccessible to this standard account.'
}
$expected=(Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json).sha256
if((Get-FileHash -LiteralPath (Join-Path $SourceDir 'RemoteCommanderTray.exe') -Algorithm SHA256).Hash -cne $expected){
    throw 'Source package checksum mismatch.'
}
if((Get-Process RemoteCommanderTray -ErrorAction SilentlyContinue)) {
    throw 'A tray process is running. Do not stop it automatically.'
}
$currentRun=Get-ItemProperty -Path $run -ErrorAction SilentlyContinue
if((Test-Path $install) -or (Test-Path $data) -or
    (Test-Path $uninstall) -or
    ($currentRun -and $currentRun.PSObject.Properties['RemoteCommanderTray']) -or
    @( $links|Where-Object{Test-Path -LiteralPath $_} ).Count -gt 0) {
    throw 'EXISTING_APP_STATE: target user has prior tray data/registration. Refusing destructive acceptance test.'
}
Write-Output "STANDARD_USER=$($identity.Name)"
Write-Output "WINDOWS_SID=$sid"
Write-Output "PROFILE=$profile"
Write-Output "APP_TARGET=$install"
Write-Output "DATA_TARGET=$data"
Write-Output "RELEASE_SHA256=$expected"
if(!$RunAcceptance){
    Write-Output 'M6_STANDARD_USER_PREFLIGHT=PASS (no modifications)'
    return
}
$beforeNodes=@(Get-Process -Name node -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Id)
$installed=$false
try{
    & $manager -Action Install -SourceDir $SourceDir
    if(!(Test-Path $exe)){throw 'Expected EXE missing after standard-user install.'}
    $installed=$true
    if((Get-FileHash $exe -Algorithm SHA256).Hash -cne $expected){throw 'Installed executable hash mismatch.'}
    foreach($p in @($install,$data)){
        $acl=Get-Acl -LiteralPath $p
        $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if($owner -cne $sid){throw "SID directory owner mismatch: $p"}
        if(@($acl.Access|Where-Object{ $_.IsInherited -or
             $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -in
                @('S-1-1-0','S-1-5-11','S-1-5-32-545') }).Count -ne 0){
            throw "Unexpected inherited or broad SID directory permissions: $p"
        }
    }
    Write-Output 'PASS genuine standard user installed verified EXE in privately owned D: SID directory'
    $expectedRun='"'+$exe+'" --autostart'
    if((Get-ItemProperty $run -Name RemoteCommanderTray).RemoteCommanderTray -cne $expectedRun){
        throw 'Standard user HKCU Run entry incorrect.'
    }
    if((Get-ItemProperty $uninstall).InstallLocation -ine $install){
        throw 'Standard user uninstaller registration incorrect.'
    }
    $shell=New-Object -ComObject WScript.Shell
    foreach($p in $links){
        if(!(Test-Path $p) -or $shell.CreateShortcut($p).TargetPath -ine $exe){
            throw 'Standard user shortcut incorrect.'
        }
    }
    Write-Output 'PASS standard-user HKCU Run, uninstall entry and both shortcuts'
    $settings=Get-Content -LiteralPath (Join-Path $data 'settings.json') -Raw|ConvertFrom-Json
    if($settings.startAgentOnLaunch -ne $false){throw 'Remote auto start is not disabled by default.'}
    & $manager -Action Install -SourceDir $SourceDir
    if((Get-FileHash (Join-Path $install 'rollback\RemoteCommanderTray.exe') -Algorithm SHA256).Hash -cne $expected){
        throw 'Upgrade backup not written correctly.'
    }
    & $manager -Action Rollback
    if((Get-FileHash $exe -Algorithm SHA256).Hash -cne $expected){throw 'Rollback digest mismatch.'}
    Write-Output 'PASS standard-user upgrade backup and rollback'
    & $manager -Action Uninstall -KeepUserData
    $installed=$false
    $postRun=Get-ItemProperty $run -ErrorAction SilentlyContinue
    if((Test-Path $exe) -or (Test-Path $uninstall) -or
        ($postRun -and $postRun.PSObject.Properties['RemoteCommanderTray']) -or
        @($links|Where-Object{Test-Path $_}).Count -gt 0){
        throw 'Uninstaller left app-owned binary, Run, shortcuts or uninstall entry.'
    }
    if(!(Test-Path (Join-Path $data 'settings.json'))){throw 'Expected retained settings missing.'}
    Write-Output 'PASS standard-user uninstall, retained settings and removed registration'
    $afterNodes=@(Get-Process -Name node -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Id)
    if(@(Compare-Object $beforeNodes $afterNodes).Count -ne 0){
        throw 'Node process inventory changed. Investigate before claiming Remote unaffected.'
    }
    Write-Output 'PASS Node PIDs unchanged; no Remote launched'
    Write-Output 'M6_STANDARD_USER_ACCEPTANCE=PASS'
}
finally{
    if($installed -or (Test-Path $exe)){
        try{& $manager -Action Uninstall -KeepUserData|Out-Null}
        catch{Write-Warning "Cleanup required for this user's test install: $($_.Exception.GetType().Name)"}
    }
    # Leave the new user's settings intact: never silently remove user data.
}
