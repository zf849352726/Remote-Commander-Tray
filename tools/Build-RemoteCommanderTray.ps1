[CmdletBinding()]
param([string]$Root)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath) }
$Root = [IO.Path]::GetFullPath($Root)
$tools = Join-Path $Root 'tools'
$base = Join-Path $Root 'verification\m6-dist'
$stage = Join-Path $base 'staging'
$publish = Join-Path $base 'publish'
$installer = Join-Path $base 'RemoteCommanderTray-Setup-0.2.0-preview.3-win-x64.exe'
$sed = Join-Path $base 'package.sed'

if (!(Test-Path "$env:WINDIR\System32\iexpress.exe")) { throw 'Windows IExpress is not available.' }
$lock = Get-Content -Raw (Join-Path $tools 'remote-package-lock.json') | ConvertFrom-Json
if ($lock.name -cne '@wonderwhy-er/desktop-commander' -or $lock.version -cne '0.3.0') { throw 'Invalid locked dependency metadata.' }
New-Item -ItemType Directory -Force $stage,$publish | Out-Null
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$env:DOTNET_CLI_HOME = Join-Path $Root 'verification\dotnet-home'
$env:NUGET_PACKAGES = Join-Path $Root 'verification\nuget-packages'
$env:NUGET_HTTP_CACHE_PATH = Join-Path $Root 'verification\nuget-http'
$env:TEMP = 'D:\temp'
$env:TMP = 'D:\temp'

& dotnet publish (Join-Path $Root 'src\RemoteCommanderTray\RemoteCommanderTray.csproj') -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=false -p:Version=0.2.0-preview.3 -o $publish --verbosity minimal
if ($LASTEXITCODE -ne 0) { throw 'Self-contained publish failed.' }

$exe = Join-Path $publish 'RemoteCommanderTray.exe'
if (!(Test-Path $exe)) { throw 'The self-contained executable is missing.' }
Copy-Item -LiteralPath $exe -Destination (Join-Path $stage 'RemoteCommanderTray.exe') -Force
Copy-Item -LiteralPath (Join-Path $tools 'Manage-RemoteCommanderTray.ps1') -Destination (Join-Path $stage 'Manage-RemoteCommanderTray.ps1') -Force
Copy-Item -LiteralPath (Join-Path $tools 'install.cmd') -Destination (Join-Path $stage 'install.cmd') -Force
Copy-Item -LiteralPath (Join-Path $Root 'LICENSE') -Destination (Join-Path $stage 'LICENSE') -Force
$version = '0.2.0-preview.3'
$commit = (& git -C $Root rev-parse HEAD).Trim()
$manifest = [ordered]@{
    appVersion = $version
    gitCommit = $commit
    runtime = 'win-x64'
    remoteName = $lock.name
    remoteVersion = $lock.version
    npmIntegrity = $lock.integrity
    sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'release-manifest.json') -Encoding UTF8
$sedContent = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[SourceFiles]
SourceFiles0=%SourceFiles0%
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
%FILE3%=
%FILE4%=
[Strings]
InstallPrompt=Install Remote Commander Tray for this Windows user?
DisplayLicense=
FinishMessage=The tray has been installed. A fixed Remote npm version is required separately.
TargetName=$installer
FriendlyName=Remote Commander Tray
AppLaunched=install.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=install.cmd
UserQuietInstCmd=install.cmd
SourceFiles0=$stage\
FILE0=RemoteCommanderTray.exe
FILE1=Manage-RemoteCommanderTray.ps1
FILE2=release-manifest.json
FILE3=install.cmd
FILE4=LICENSE
"@
[IO.File]::WriteAllText($sed, $sedContent, [Text.Encoding]::ASCII)
if (Test-Path -LiteralPath $installer) { Remove-Item -LiteralPath $installer -Force }
& "$env:WINDIR\System32\iexpress.exe" /N /Q $sed
$rc = $LASTEXITCODE
if ($rc -ne 0) { throw "IExpress failed (exit $rc)." }
# IExpress may detach makecab.exe and return before the final EXE is written.
$ready = $false
for ($attempt = 0; $attempt -lt 120; $attempt++) {
    $active = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(iexpress|makecab)\.exe$' -and $_.CommandLine -like ('*' + $base + '*') })
    if ((Test-Path -LiteralPath $installer) -and $active.Count -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (!$ready) { throw 'Installer packaging did not complete successfully.' }
$packageDigest = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToUpperInvariant()
@{
    installer = $installer
    installerSha256 = $packageDigest
    publishedExeSha256 = $manifest.sha256
    appVersion = $version
    remoteVersion = $lock.version
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $base 'checksums.json') -Encoding UTF8
Write-Output "IExpress installer built: $installer"
Write-Output "SHA256=$packageDigest"
