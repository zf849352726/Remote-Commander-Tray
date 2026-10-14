# Per-user package maintenance. No elevation, no implicit npm installations.
# The -TestMode switch isolates file operations and suppresses HKCU/shortcut writes.
[CmdletBinding()]
param(
    [ValidateSet('Install','Uninstall','Rollback','Check')]
    [string]$Action = 'Install',
    [string]$InstallDir = 'D:\Apps\RemoteCommanderTray',
    [string]$DataDir = (Join-Path 'D:\Apps\RemoteCommanderTrayData' ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)),
    [string]$SourceDir,
    [switch]$TestMode,
    [switch]$RemoveUserData,
    [switch]$KeepUserData
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($KeepUserData -and $RemoveUserData) {
    throw 'KeepUserData and RemoveUserData cannot both be specified.'
}
if ([string]::IsNullOrWhiteSpace($SourceDir)) { $SourceDir = Split-Path -Parent $PSCommandPath }
$AppName = 'RemoteCommanderTray'
$exeName = 'RemoteCommanderTray.exe'
$installerName = 'Manage-RemoteCommanderTray.ps1'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RemoteCommanderTray'
$expectedVersion = '0.3.0'
$pkgName = '@wonderwhy-er/desktop-commander'

function Assert-SafePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($full.Length -lt 6 -or $full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\') -or
        $full -ieq $env:WINDIR -or $full -ieq $env:USERPROFILE -or
        $full -ieq $env:LOCALAPPDATA) {
        throw "Unsafe target directory."
    }
    return $full
}

$InstallDir = Assert-SafePath $InstallDir
$DataDir = Assert-SafePath $DataDir
if ($TestMode -and ($InstallDir -notmatch '(?i)\\verification\\' -or
                    $DataDir -notmatch '(?i)\\verification\\')) {
    throw 'TestMode requires isolated directories under verification; real user data is forbidden.'
}
if (!$TestMode) {
    $expectedInstallDir = [IO.Path]::GetFullPath('D:\Apps\RemoteCommanderTray').TrimEnd('\')
    $expectedDataDir = [IO.Path]::GetFullPath(
        (Join-Path 'D:\Apps\RemoteCommanderTrayData' ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))).TrimEnd('\')
    if ($InstallDir -ine $expectedInstallDir -or $DataDir -ine $expectedDataDir) {
        throw 'Normal installation and removal must use the approved D: paths for the current Windows account.'
    }
}
$installedExe = Join-Path $InstallDir $exeName
$installedManager = Join-Path $InstallDir $installerName
$rollbackDir = Join-Path $InstallDir 'rollback'
$rollbackExe = Join-Path $rollbackDir $exeName
$rollbackInfo = Join-Path $rollbackDir 'backup.json'

function Ensure-PrivateDataDirectory {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if (!(Test-Path -LiteralPath $DataDir)) {
        New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    }
    # D: may inherit Authenticated Users:F. Make the per-account data tree private.
    # This only changes the current user's dedicated data folder, never D:\Apps itself.
    & icacls.exe $DataDir /inheritance:r /grant:r ("*" + $sid + ":(OI)(CI)F") '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict the D: data folder ACL; installation stopped.' }
    if (!(Test-Path -LiteralPath (Join-Path $DataDir 'settings.json'))) {
        # Conservative first-install preference: tray starts at login; Remote remains
        # manually stopped until the user explicitly enables Remote auto-start.
        '{"startAgentOnLaunch":false}' | Set-Content -LiteralPath (Join-Path $DataDir 'settings.json') -Encoding UTF8
    }
}

function Get-CurrentRunValue {
    try {
        $entry = Get-ItemProperty -Path $runKey -ErrorAction Stop
        $property = $entry.PSObject.Properties[$AppName]
        if ($null -eq $property) { return $null }
        return $property.Value
    } catch { return $null }
}
function Assert-NotRunning {
    $running = @(Get-Process -Name 'RemoteCommanderTray' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        throw "Close Remote Commander Tray via Exit Application before installing, uninstalling or rolling back. Existing processes were not terminated."
    }
}
function FileHash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Ensure-NoUnrelatedShortcut([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { return }
    $shell = New-Object -ComObject WScript.Shell
    $target = $shell.CreateShortcut($Path).TargetPath
    if ($target -ine $installedExe) { throw "A shortcut exists at $Path and belongs to another program." }
}
function Write-Shortcut([string]$Path) {
    Ensure-NoUnrelatedShortcut $Path
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($Path)
    $link.TargetPath = $installedExe
    $link.WorkingDirectory = $InstallDir
    $link.Description = 'Remote Commander Tray'
    $link.Save()
}
function Get-ShortcutPaths {
    return @(
        (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Remote Commander Tray.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'Remote Commander Tray.lnk')
    )
}
function Integrate-Windows {
    if ($TestMode) { return }
    $paths = @(Get-ShortcutPaths)
    foreach ($link in $paths) { Ensure-NoUnrelatedShortcut $link }
    $regValue = '"' + $installedExe + '" --autostart'
    $existing = (Get-CurrentRunValue)
    if ($existing -and $existing -ne $regValue) {
        throw "Existing HKCU Run entry points elsewhere. No unrelated entry was overwritten."
    }
    New-Item -Path $runKey -Force | Out-Null
    New-ItemProperty -Path $runKey -Name $AppName -Value $regValue -PropertyType String -Force | Out-Null
    New-Item -Path $uninstallKey -Force | Out-Null
    $uninstallCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $installedManager + '" -Action Uninstall'
    Set-ItemProperty $uninstallKey -Name DisplayName -Value 'Remote Commander Tray'
    Set-ItemProperty $uninstallKey -Name Publisher -Value 'Remote Commander Tray contributors'
    Set-ItemProperty $uninstallKey -Name UninstallString -Value $uninstallCommand
    Set-ItemProperty $uninstallKey -Name InstallLocation -Value $InstallDir
    Set-ItemProperty $uninstallKey -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty $uninstallKey -Name NoRepair -Value 1 -Type DWord
    foreach ($link in $paths) { Write-Shortcut $link }
}
function Remove-WindowsIntegration {
    if ($TestMode) { return }
    $existing = (Get-CurrentRunValue)
    $expected = '"' + $installedExe + '" --autostart'
    if ($existing -eq $expected) {
        Remove-ItemProperty -Path $runKey -Name $AppName -ErrorAction SilentlyContinue
    }
    if (Test-Path $uninstallKey) {
        $registered = (Get-ItemProperty -Path $uninstallKey).InstallLocation
        if ($registered -ieq $InstallDir) { Remove-Item $uninstallKey -Recurse -Force }
    }
    foreach ($link in @(Get-ShortcutPaths)) {
        if (Test-Path -LiteralPath $link) {
            $shell = New-Object -ComObject WScript.Shell
            if ($shell.CreateShortcut($link).TargetPath -ieq $installedExe) {
                Remove-Item -LiteralPath $link -Force
            }
        }
    }
}
function Check-Dependency {
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (!$node -or !$npm) {
        Write-Output "Node.js and npm are required. Install them separately before enabling Remote."
        return $false
    }
    $root = (& $npm.Source root -g 2>$null | Select-Object -Last 1)
    if (!$root) { return $false }
    $manifest = Join-Path $root '@wonderwhy-er\desktop-commander\package.json'
    if (!(Test-Path -LiteralPath $manifest)) {
        Write-Output "Remote dependency is not installed globally. Required: npm install -g $pkgName@$expectedVersion"
        return $false
    }
    try {
        $json = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($json.name -cne $pkgName -or $json.version -cne $expectedVersion) {
            Write-Output "Installed Remote version differs. Required: $pkgName@$expectedVersion"
            return $false
        }
    } catch {
        Write-Output "Cannot verify installed Remote package manifest."
        return $false
    }
    Write-Output "Remote dependency verified: $pkgName@$expectedVersion"
    return $true
}

switch ($Action) {
    'Check' {
        if (Test-Path -LiteralPath $installedExe) {
            Write-Output "Installed tray SHA256: $(FileHash $installedExe)"
        } else {
            Write-Output 'Tray is not installed at the selected directory.'
        }
        [void](Check-Dependency)
        break
    }
    'Install' {
        Assert-NotRunning
        $sourceExe = Join-Path $SourceDir $exeName
        $sourceManager = Join-Path $SourceDir $installerName
        $manifest = Join-Path $SourceDir 'release-manifest.json'
        foreach ($required in @($sourceExe, $sourceManager, $manifest)) {
            if (!(Test-Path -LiteralPath $required)) { throw "Missing package component: $required" }
        }
        $release = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
        $digest = FileHash $sourceExe
        if ($digest -cne $release.sha256 -or $release.remoteVersion -cne $expectedVersion) {
            throw "Package digest or pinned dependency mismatch. Installation aborted."
        }

        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        # Keep the per-user settings/logs on D: with an explicit private ACL.
        Ensure-PrivateDataDirectory
        $newExe = Join-Path $InstallDir ($exeName + '.new')
        try {
            Copy-Item -LiteralPath $sourceExe -Destination $newExe -Force
            if ((FileHash $newExe) -cne $digest) { throw "Staged EXE checksum mismatch." }
            if (Test-Path -LiteralPath $installedExe) {
                New-Item -ItemType Directory -Path $rollbackDir -Force | Out-Null
                Copy-Item -LiteralPath $installedExe -Destination $rollbackExe -Force
                foreach ($related in @($installerName, 'release-manifest.json')) {
                    $prior = Join-Path $InstallDir $related
                    if (Test-Path -LiteralPath $prior) {
                        Copy-Item -LiteralPath $prior -Destination (Join-Path $rollbackDir $related) -Force
                    }
                }
                @{sha256=(FileHash $rollbackExe); savedUtc=[DateTime]::UtcNow.ToString('O')} |
                    ConvertTo-Json | Set-Content -LiteralPath $rollbackInfo -Encoding UTF8
            }
            Move-Item -LiteralPath $newExe -Destination $installedExe -Force
            Copy-Item -LiteralPath $sourceManager -Destination $installedManager -Force
            Copy-Item -LiteralPath $manifest -Destination (Join-Path $InstallDir 'release-manifest.json') -Force
            $licensePath = Join-Path $SourceDir 'LICENSE'
            if (Test-Path -LiteralPath $licensePath) {
                Copy-Item -LiteralPath $licensePath -Destination (Join-Path $InstallDir 'LICENSE') -Force
            }
            Integrate-Windows
        } finally {
            if (Test-Path $newExe) { Remove-Item -LiteralPath $newExe -Force }
        }

        Write-Output "Installed tray: $installedExe"
        [void](Check-Dependency) # Advisory only: never install npm silently.
        break
    }
    'Rollback' {
        Assert-NotRunning
        if (!(Test-Path -LiteralPath $rollbackExe) -or !(Test-Path -LiteralPath $rollbackInfo)) {
            throw "No verified previous release exists. Nothing was modified."
        }
        $info = Get-Content -LiteralPath $rollbackInfo -Raw | ConvertFrom-Json
        if ((FileHash $rollbackExe) -cne $info.sha256) { throw "Backup digest mismatch." }
        $newExe = $installedExe + '.new'
        try {
            Copy-Item -LiteralPath $rollbackExe -Destination $newExe -Force
            if ((FileHash $newExe) -cne $info.sha256) { throw "Staged rollback checksum mismatch." }
            Move-Item -LiteralPath $newExe -Destination $installedExe -Force
            $previousManifest = Join-Path $rollbackDir 'release-manifest.json'
            if (Test-Path -LiteralPath $previousManifest) {
                Copy-Item -LiteralPath $previousManifest -Destination (Join-Path $InstallDir 'release-manifest.json') -Force
                Remove-Item -LiteralPath $previousManifest -Force
            } else {
                Remove-Item -LiteralPath (Join-Path $InstallDir 'release-manifest.json') -Force -ErrorAction SilentlyContinue
            }
            $previousManager = Join-Path $rollbackDir $installerName
            if (Test-Path -LiteralPath $previousManager) {
                Copy-Item -LiteralPath $previousManager -Destination $installedManager -Force
                Remove-Item -LiteralPath $previousManager -Force
            }
            Remove-Item -LiteralPath $rollbackExe -Force
            Remove-Item -LiteralPath $rollbackInfo -Force
            Write-Output "Rolled back EXE to SHA256: $($info.sha256)"
            Write-Output 'Remote npm version is unchanged. If it also needs rollback, stop external Remote first and explicitly install the required pinned version.'
        } finally {
            if (Test-Path $newExe) { Remove-Item $newExe -Force }
        }
        break
    }
    'Uninstall' {
        Assert-NotRunning
        $removeDataApproved = [bool]$TestMode
        if (!$TestMode -and !$KeepUserData) {
            Add-Type -AssemblyName System.Windows.Forms
            $answer = [System.Windows.Forms.MessageBox]::Show(
                "Keep this tray application's settings and logs for a future reinstall? Official Desktop Commander authorization is always preserved.",
                'Uninstall Remote Commander Tray',
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($answer -eq [System.Windows.Forms.DialogResult]::Cancel) {
                throw 'Uninstall cancelled without changing the installation.'
            }
            if ($answer -eq [System.Windows.Forms.DialogResult]::No) {
                $RemoveUserData = $true
                $removeDataApproved = $true
            }
            if ($RemoveUserData -and !$removeDataApproved) {
                $confirmation = [System.Windows.Forms.MessageBox]::Show(
                    "Delete this tray application's settings and logs? The official Remote authentication files will not be deleted.",
                    'Confirm local data deletion',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning)
                if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) {
                    throw 'Uninstall cancelled; data not removed.'
                }
                $removeDataApproved = $true
            }
        }
        Remove-WindowsIntegration
        # Do not remove any official Desktop Commander credentials or global npm packages.
        foreach ($owned in @($installedExe, $installedManager, (Join-Path $InstallDir 'release-manifest.json'), (Join-Path $InstallDir 'LICENSE'))) {
            if (Test-Path -LiteralPath $owned) { Remove-Item -LiteralPath $owned -Force }
        }
        foreach ($owned in @($rollbackExe, $rollbackInfo, (Join-Path $rollbackDir 'release-manifest.json'), (Join-Path $rollbackDir $installerName))) {
            if (Test-Path -LiteralPath $owned) { Remove-Item -LiteralPath $owned -Force }
        }
        if ((Test-Path $rollbackDir) -and !(Get-ChildItem -LiteralPath $rollbackDir -Force)) {
            Remove-Item -LiteralPath $rollbackDir
        }
        if ($RemoveUserData) {
            if (!$TestMode -and !$removeDataApproved) { throw 'Data removal not confirmed.' }
            if (Test-Path $DataDir) { Remove-Item -LiteralPath $DataDir -Recurse -Force }
        }
        if ((Test-Path $InstallDir) -and !(Get-ChildItem -LiteralPath $InstallDir -Force)) {
            Remove-Item -LiteralPath $InstallDir
        }
        Write-Output "Tray uninstalled; logs/settings $(if($RemoveUserData){'removed'}else{'preserved'})."
        break
    }
}
