[CmdletBinding()]
param([string]$Root='D:\Apps', [switch]$Apply, [string]$BackupPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root).TrimEnd('\')
$production=$Root -ieq 'D:\Apps'
$repo='D:\DesktopCommanderRemote'
$sandboxPrefix=Join-Path $repo 'verification\m6-acl-sandbox'
if (!$production -and !$Root.StartsWith($sandboxPrefix + '\',[StringComparison]::OrdinalIgnoreCase)) {
  throw 'Target must be D:\Apps or the isolated project ACL test sandbox.'
}
if (!(Test-Path -LiteralPath $Root -PathType Container)) {throw 'Target directory missing.'}
$target=Get-Item -LiteralPath $Root -Force
if (($target.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {throw 'Target is a reparse point.'}
if ($production) {
  $allowed=@('RemoteCommanderTray','RemoteCommanderTrayData')
  foreach($child in @(Get-ChildItem -LiteralPath $Root -Force)){
    if ($child.Name -notin $allowed -or !$child.PSIsContainer -or
      ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Unexpected child in D:\Apps: $($child.Name); nothing changed."
    }
  }
  foreach($name in $allowed){
    if (!(Test-Path -LiteralPath (Join-Path $Root $name) -PathType Container)) {
      throw "Missing $name in D:\Apps; nothing changed."
    }
  }
}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if (!$sid) {throw 'No current Windows account SID.'}
$backups=Join-Path $repo 'verification\m6-acl-backups'
New-Item -ItemType Directory -Force $backups | Out-Null
if (!$BackupPath) {
  $tag=if($production){'D-Apps'}else{'Sandbox'}
  $BackupPath=Join-Path $backups ($tag+'-'+(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')+'.acl')
}
$BackupPath=[IO.Path]::GetFullPath($BackupPath)
if (!$BackupPath.StartsWith($backups+'\',[StringComparison]::OrdinalIgnoreCase)) {
  throw 'Backup must be inside project verification directory.'
}
Write-Output ('TARGET='+$Root)
Write-Output ('USER_SID='+$sid)
Write-Output ('BACKUP='+$BackupPath)
if (!$Apply){
  Write-Output 'DRY_RUN=PASS: Proposed access: current SID Full, SYSTEM Full, Administrators Full, Users ReadExecute.'
  exit 0
}
if (Test-Path -LiteralPath $BackupPath) {throw 'Refusing to overwrite ACL backup.'}
# SDDL snapshot of the root and descendants for auditing. On this host,
# icacls /restore failed with Win32 1300. Tested rollback is /reset on the
# exact root, permitted only when the original root had inherited-only ACLs.
& icacls.exe $Root /save $BackupPath /T /C *> $null
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $BackupPath)) {throw 'ACL backup failed; nothing changed.'}
$exe=Join-Path $Root 'RemoteCommanderTray\RemoteCommanderTray.exe'
$beforeHash=if(Test-Path $exe){(Get-FileHash $exe -Algorithm SHA256).Hash}else{$null}
$acl=Get-Acl -LiteralPath $Root
# A root with only inherited ACEs can be reverted exactly with icacls /reset.
# Refuse the operation if any explicit original grants would be lost by that rollback.
if ($acl.AreAccessRulesProtected -or @($acl.Access | Where-Object { !$_.IsInherited }).Count -ne 0) {
  throw 'Original root contains explicit ACLs; automatic rollback via /reset would be unsafe.'
}
$originalDacl=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access)
$acl.SetAccessRuleProtection($true,$false)
$inherit=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
$prop=[Security.AccessControl.PropagationFlags]::None
$allow=[Security.AccessControl.AccessControlType]::Allow
$grants=@(
  @($sid,[Security.AccessControl.FileSystemRights]::FullControl),
  @('S-1-5-18',[Security.AccessControl.FileSystemRights]::FullControl),
  @('S-1-5-32-544',[Security.AccessControl.FileSystemRights]::FullControl),
  @('S-1-5-32-545',[Security.AccessControl.FileSystemRights]::ReadAndExecute)
)
foreach($grant in $grants){
  $rule=[Security.AccessControl.FileSystemAccessRule]::new(
    [Security.Principal.SecurityIdentifier]::new([string]$grant[0]),
    [Security.AccessControl.FileSystemRights]$grant[1],$inherit,$prop,$allow)
  $acl.SetAccessRule($rule)
}
try {
  Set-Acl -LiteralPath $Root -AclObject $acl
  if ($beforeHash -and (Get-FileHash $exe -Algorithm SHA256).Hash -cne $beforeHash) {
    throw 'EXE SHA256 changed unexpectedly.'
  }
  & (Join-Path $repo 'tools\Audit-M6InstallPermissions.ps1') -InstallDir (Join-Path $Root 'RemoteCommanderTray') -DataBaseDir (Join-Path $Root 'RemoteCommanderTrayData')
  if ($LASTEXITCODE -ne 0) {throw 'Audit found remaining broad write access.'}
  if (!(Get-Acl -LiteralPath $Root).AreAccessRulesProtected) {throw 'Parent inheritance remains enabled.'}
  Write-Output 'M6_ACL_APPLY=PASS'
}
catch {
  $msg=$_.Exception.Message
  Write-Output ('RESTORE_REASON='+$msg)
  # /restore returned Win32 error 1300 in a sandbox on this Windows machine.
  # /reset on the exact root was tested and reinstated the original inherited DACL
  # on the root and children without touching siblings or the D: volume ACL.
  & icacls.exe $Root /reset *> $null
  $rc=$LASTEXITCODE
  if ($rc -ne 0){throw ('ACL apply failed AND /reset rollback failed (code '+$rc+'): '+$msg)}
  $restored=(Get-Acl -LiteralPath $Root).GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access)
  if ($restored -cne $originalDacl) {
    throw ('ACL apply failed; /reset did not match the original DACL. Inspect backup '+$BackupPath+'. '+$msg)
  }
  throw ('ACL apply failed; original inherited DACL restored via /reset: '+$msg)
}
