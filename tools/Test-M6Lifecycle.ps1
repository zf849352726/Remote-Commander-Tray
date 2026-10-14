[CmdletBinding()]
param([string]$Root)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (!$Root) { $Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath) }
$stage = Join-Path $Root 'verification\m6-dist\staging'
$script = Join-Path $Root 'tools\Manage-RemoteCommanderTray.ps1'
$sandbox = Join-Path $Root 'verification\m6-sandbox'
$install = Join-Path $sandbox 'Installed'
$data = Join-Path $sandbox 'Data'
$exe = Join-Path $install 'RemoteCommanderTray.exe'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
function Get-CurrentRunValue {
    try {
        $entry = Get-ItemProperty -Path $runKey -ErrorAction Stop
        $property = $entry.PSObject.Properties['RemoteCommanderTray']
        if ($null -eq $property) { return $null }
        return $property.Value
    } catch { return $null }
}$before = (Get-CurrentRunValue)
$realInstall = 'D:\Apps\RemoteCommanderTray'
if ($install -ieq $realInstall) { throw 'Test directory equals real installation.' }
if (!(Test-Path (Join-Path $stage 'release-manifest.json'))) { throw 'Build the staging release first.' }
if (Test-Path $sandbox) { Remove-Item -LiteralPath $sandbox -Force -Recurse }
New-Item -ItemType Directory -Force $install,$data | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $data 'settings.json') -Value '{"test":true}' -Encoding UTF8
    & $script -Action Install -TestMode -InstallDir $install -DataDir $data -SourceDir $stage | Out-Null
    if (!(Test-Path $exe)) { throw 'Initial install failed.' }
    $currentHash = (Get-FileHash $exe -Algorithm SHA256).Hash
    $manifest = Get-Content -LiteralPath (Join-Path $stage 'release-manifest.json') -Raw | ConvertFrom-Json
    if ($currentHash -cne $manifest.sha256) { throw 'Initial installed EXE checksum failed.' }
    Write-Output 'PASS initial isolated install and digest validation'
    # Existing settings are preserved; D: permissions must still become private.
    $access = @(Get-Acl -LiteralPath $data).Access
    if ($access | Where-Object { $_.IsInherited -or $_.IdentityReference.Value -match 'Authenticated Users|\\Users$' }) {
        throw 'Per-account settings/log ACL still allows inherited or unrelated user access.'
    }
    Write-Output 'PASS per-account D: data ACL is private'

    Set-Content -LiteralPath $exe -Value 'LEGACY-BINARY-MARKER' -Encoding ASCII
    & $script -Action Install -TestMode -InstallDir $install -DataDir $data -SourceDir $stage | Out-Null
    $backup = Join-Path $install 'rollback\RemoteCommanderTray.exe'
    if (!(Test-Path $backup) -or (Get-Content -Raw $backup) -notmatch 'LEGACY-BINARY-MARKER') {
        throw 'Old version was not backed up.'
    }
    if ((Get-FileHash $exe -Algorithm SHA256).Hash -cne $currentHash) {
        throw 'Upgrade did not install the expected staged version.'
    }
    Write-Output 'PASS upgrade creates a hash-verified rollback backup'

    & $script -Action Rollback -TestMode -InstallDir $install -DataDir $data | Out-Null
    if ((Get-Content -Raw $exe) -notmatch 'LEGACY-BINARY-MARKER') { throw 'Rollback failed.' }
    Write-Output 'PASS rollback restores the previous EXE'

    & $script -Action Install -TestMode -InstallDir $install -DataDir $data -SourceDir $stage | Out-Null
    Set-Content -LiteralPath $backup -Value 'TAMPERED' -Encoding ASCII
    $priorHash = (Get-FileHash $exe -Algorithm SHA256).Hash
    $threw = $false
    try {
        & $script -Action Rollback -TestMode -InstallDir $install -DataDir $data | Out-Null
    } catch { $threw = $true }
    if (!$threw) { throw 'Tampered rollback unexpectedly succeeded.' }
    if ((Get-FileHash $exe -Algorithm SHA256).Hash -cne $priorHash) {
        throw 'Tampered rollback changed current EXE.'
    }
    Write-Output 'PASS tampered backup is rejected without modifying current version'

    & $script -Action Uninstall -TestMode -InstallDir $install -DataDir $data | Out-Null
    if (Test-Path $exe) { throw 'Uninstall did not remove owned executable.' }
    if (!(Test-Path (Join-Path $data 'settings.json'))) { throw 'Uninstall deleted user data without approval.' }
    Write-Output 'PASS uninstall removes owned files and preserves user data'

    & $script -Action Install -TestMode -InstallDir $install -DataDir $data -SourceDir $stage | Out-Null
    & $script -Action Uninstall -TestMode -InstallDir $install -DataDir $data -RemoveUserData | Out-Null
    if (Test-Path $data) { throw 'Explicit removal failed.' }
    Write-Output 'PASS explicit test-mode data removal'

    # A fresh installation must default to manually controlled Remote startup,
    # while keeping the tray itself eligible for Windows login startup.
    & $script -Action Install -TestMode -InstallDir $install -DataDir $data -SourceDir $stage | Out-Null
    $firstSettings = Get-Content -LiteralPath (Join-Path $data 'settings.json') -Raw | ConvertFrom-Json
    if ($firstSettings.startAgentOnLaunch -ne $false) { throw 'New user Remote startup was not disabled by default.' }
    Write-Output 'PASS fresh user defaults Remote autostart to off'
    & $script -Action Uninstall -TestMode -InstallDir $install -DataDir $data -RemoveUserData | Out-Null

    $threw = $false
    try { & $script -Action Check -TestMode -InstallDir $realInstall -DataDir $data | Out-Null }
    catch { $threw = $true }
    if (!$threw) { throw 'TestMode allowed a real installation path.' }
    Write-Output 'PASS test-mode path guard'

    $after = (Get-CurrentRunValue)
    if ($after -cne $before) { throw 'Test unexpectedly changed HKCU Run.' }
    Write-Output 'PASS no actual HKCU Run changes'
} finally {
    if (Test-Path $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
