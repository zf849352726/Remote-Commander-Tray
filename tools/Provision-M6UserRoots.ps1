[CmdletBinding()]
param([string]$Root='D:\Apps',[switch]$Apply)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root).TrimEnd('\')
$repo='D:\DesktopCommanderRemote'
$sandbox=Join-Path $repo 'verification\m6-acl-sandbox'
if ($Root -ine 'D:\Apps' -and !$Root.StartsWith($sandbox+'\',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Only D:\Apps or M6 isolated provision sandbox is allowed.'
}
$parents=@('RemoteCommanderTray','RemoteCommanderTrayData')
foreach($name in $parents){
    $path=Join-Path $Root $name
    if (!(Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Parent missing or linked: $path"
    }
}
$authenticatedUsers=[Security.Principal.SecurityIdentifier]::new('S-1-5-11')
$inherit=[Security.AccessControl.InheritanceFlags]::None
$prop=[Security.AccessControl.PropagationFlags]::None
$allow=[Security.AccessControl.AccessControlType]::Allow
$rights=[Security.AccessControl.FileSystemRights]::CreateDirectories
$rule=[Security.AccessControl.FileSystemAccessRule]::new(
    $authenticatedUsers,$rights,$inherit,$prop,$allow)
$backups=Join-Path $repo 'verification\m6-acl-backups'
New-Item -ItemType Directory -Force $backups|Out-Null
$original=@{}
foreach($name in $parents){
    $path=Join-Path $Root $name
    $acl=Get-Acl -LiteralPath $path
    if ($acl.Access|Where-Object {
        $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-11' -and
        $_.FileSystemRights -band ([Security.AccessControl.FileSystemRights]::WriteData -bor
          [Security.AccessControl.FileSystemRights]::Delete -bor
          [Security.AccessControl.FileSystemRights]::ChangePermissions)
    }) {throw "Broad Authenticated Users ACL already present: $path"}
    $original[$name]=$acl
}
if (!$Apply) {
    Write-Output "DRY_RUN=PASS: will grant Authenticated Users CreateDirectories on THESE FOLDERS ONLY (no inheritance): $($parents -join ', ')"
    exit 0
}
$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$done=@()
try{
    foreach($name in $parents){
        $path=Join-Path $Root $name
        $acl=Get-Acl -LiteralPath $path
        $matching=@($acl.Access|Where-Object {
            $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-11' -and
            !$_.IsInherited -and $_.InheritanceFlags -eq [Security.AccessControl.InheritanceFlags]::None -and
            $_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::CreateDirectories
        })
        if($matching.Count -eq 0){
            $backupFile=Join-Path $backups "PerUser-$name-$stamp.sddl"
            [IO.File]::WriteAllText($backupFile,
                $acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access),
                [Text.UTF8Encoding]::new($false))
            $acl.AddAccessRule($rule)
            Set-Acl -LiteralPath $path -AclObject $acl
            $done+= $name
        }
        Write-Output "PROVISIONED=$path"
    }
    Write-Output 'M6_PER_USER_ROOTS=PASS'
}
catch{
    $reason=$_.Exception.Message
    # Remove ONLY the matching ACE introduced by this run, never reset the parent root.
    foreach($name in $done){
        $path=Join-Path $Root $name
        $acl=Get-Acl -LiteralPath $path
        $acl.RemoveAccessRuleSpecific($rule)
        Set-Acl -LiteralPath $path -AclObject $acl
    }
    throw "Provision failed and new ACEs reverted: $reason"
}
