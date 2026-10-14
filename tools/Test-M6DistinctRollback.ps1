[CmdletBinding()]
param([string]$RepoRoot='D:\DesktopCommanderRemote')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($RepoRoot)
$base=Join-Path $root 'verification\m6-distinct-rollback'
$v1=Join-Path $root 'verification\m6-dist\staging'
$v2=Join-Path $base 'version2'
$exe2=Join-Path $root 'verification\m6-distinct-v2\publish\RemoteCommanderTray.exe'
$manager=Join-Path $root 'tools\Manage-RemoteCommanderTray.ps1'
$install=Join-Path $base 'installed'
$data=Join-Path $base 'data'
$exe=Join-Path $install 'RemoteCommanderTray.exe'
$registryKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
function RunValue {
  try {
    $reg=Get-ItemProperty -Path $registryKey -ErrorAction Stop
    $prop=$reg.PSObject.Properties['RemoteCommanderTray']
    if ($null -eq $prop) { return $null }
    return $prop.Value
  } catch { return $null }
}
$runBefore=RunValue
$nodesBefore=@(Get-CimInstance Win32_Process |
  Where-Object {$_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander'} |
  Select-Object -ExpandProperty ProcessId)
if (!(Test-Path $exe2)) { throw 'Distinct build v2 is not published.' }
if (!(Test-Path (Join-Path $v1 'release-manifest.json'))) { throw 'v1 manifest missing.' }
if (Test-Path $base) { Remove-Item -LiteralPath $base -Recurse -Force }
New-Item -ItemType Directory -Force $v2,$data|Out-Null
try {
  Copy-Item -LiteralPath $exe2 -Destination (Join-Path $v2 'RemoteCommanderTray.exe')
  Copy-Item -LiteralPath $manager -Destination (Join-Path $v2 'Manage-RemoteCommanderTray.ps1')
  Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $v2 'LICENSE')
  $m2=Get-Content -Raw (Join-Path $v1 'release-manifest.json') | ConvertFrom-Json
  $m2.appVersion='0.2.0-preview.2'
  $m2.sha256=(Get-FileHash $exe2 -Algorithm SHA256).Hash
  $m2|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $v2 'release-manifest.json') -Encoding UTF8
  $m1=Get-Content -Raw (Join-Path $v1 'release-manifest.json')|ConvertFrom-Json
  if ($m1.sha256 -ceq $m2.sha256) { throw 'Binary digests unexpectedly equal.' }
  Set-Content -LiteralPath (Join-Path $data 'settings.json') -Value '{"startAgentOnLaunch":false,"testMarker":"retain"}'
  & $manager -Action Install -TestMode -InstallDir $install -DataDir $data -SourceDir $v1 | Out-Null
  if ((Get-FileHash $exe -Algorithm SHA256).Hash -cne $m1.sha256) {throw 'Install v1 hash mismatch.'}
  Write-Output "PASS actual v1 EXE install, SHA256=$($m1.sha256)"
  & $manager -Action Install -TestMode -InstallDir $install -DataDir $data -SourceDir $v2 | Out-Null
  if ((Get-FileHash $exe -Algorithm SHA256).Hash -cne $m2.sha256) { throw 'Install v2 hash mismatch.' }
  $rollback=Join-Path $install 'rollback\RemoteCommanderTray.exe'
  if ((Get-FileHash $rollback -Algorithm SHA256).Hash -cne $m1.sha256) {throw 'Rollback backup is not the previous v1 binary.'}
  $currentManifest=Get-Content -Raw (Join-Path $install 'release-manifest.json')|ConvertFrom-Json
  if ($currentManifest.appVersion -cne '0.2.0-preview.2') { throw 'Upgraded manifest wrong.' }
  Write-Output "PASS actual v2 EXE upgrade, SHA256=$($m2.sha256)"
  & $manager -Action Rollback -TestMode -InstallDir $install -DataDir $data | Out-Null
  if ((Get-FileHash $exe -Algorithm SHA256).Hash -cne $m1.sha256) { throw 'Rollback did not restore v1.' }
  $restored=Get-Content -Raw (Join-Path $install 'release-manifest.json')|ConvertFrom-Json
  if ($restored.appVersion -cne $m1.appVersion -or $restored.sha256 -cne $m1.sha256) { throw 'Rollback metadata mismatch.' }
  Write-Output 'PASS distinct binary v2 -> v1 rollback including release manifest'
  & $manager -Action Install -TestMode -InstallDir $install -DataDir $data -SourceDir $v2 | Out-Null
  [IO.File]::WriteAllText($rollback,'tampered old EXE',[Text.Encoding]::ASCII)
  $caught=$false
  try {
    & $manager -Action Rollback -TestMode -InstallDir $install -DataDir $data|Out-Null
  } catch { $caught=$true }
  if (!$caught -or (Get-FileHash $exe -Algorithm SHA256).Hash -cne $m2.sha256) {
    throw 'Tampered-backup rollback was not safely rejected.'
  }
  Write-Output 'PASS modified backup rejected, verified active v2 unchanged'
  $settings=Get-Content -Raw (Join-Path $data 'settings.json')|ConvertFrom-Json
  if ($settings.testMarker -cne 'retain') { throw 'Upgrade overwrote settings.' }
  & $manager -Action Uninstall -TestMode -KeepUserData -InstallDir $install -DataDir $data | Out-Null
  if ((Test-Path $exe) -or !(Test-Path (Join-Path $data 'settings.json'))) {
    throw 'Uninstall failed or removed settings.'
  }
  Write-Output 'PASS uninstall retained settings and removed app-owned binaries'
  if ((RunValue) -cne $runBefore) { throw 'Test modified HKCU Run.' }
  $nodesAfter=@(Get-CimInstance Win32_Process|
    Where-Object {$_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander'}|
    Select-Object -ExpandProperty ProcessId)
  if (@(Compare-Object $nodesBefore $nodesAfter).Count -ne 0) {throw 'Test changed existing Remote PIDs.'}
  Write-Output 'PASS no HKCU Run mutation, no Remote process changes'
  Write-Output 'M6_DISTINCT_EXE_ROLLBACK=PASS'
} finally {
  if (Test-Path $base) { Remove-Item $base -Recurse -Force }
}
