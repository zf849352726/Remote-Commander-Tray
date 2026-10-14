[CmdletBinding()]
param([string]$InstallDir='D:\Apps\RemoteCommanderTray',
      [string]$DataBaseDir='D:\Apps\RemoteCommanderTrayData')
$ErrorActionPreference='Stop'
$paths=@($InstallDir,$DataBaseDir,(Split-Path -Parent $InstallDir))
$wellKnown=@('S-1-1-0','S-1-5-11','S-1-5-32-545')
# Use individual write/delete bits only. Composite FullControl and Modify also
# include read/synchronize, which must not flag read-only Users permissions.
$dangerous=[Security.AccessControl.FileSystemRights](
    [Security.AccessControl.FileSystemRights]::WriteData -bor
    [Security.AccessControl.FileSystemRights]::AppendData -bor
    [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
    [Security.AccessControl.FileSystemRights]::Delete -bor
    [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
    [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
    [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
    [Security.AccessControl.FileSystemRights]::TakeOwnership)
$violations=0
foreach($path in ($paths|Select-Object -Unique)){
    if(!(Test-Path -LiteralPath $path)){Write-Output "NOT_PRESENT: $path";continue}
    $acl=Get-Acl -LiteralPath $path
    foreach($entry in $acl.Access){
        $sid=$null
        try{$sid=$entry.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value}
        catch{$sid=[string]$entry.IdentityReference}
        if($entry.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
            $sid -in $wellKnown -and (($entry.FileSystemRights -band $dangerous) -ne 0)){
            Write-Output ("UNSAFE_WRITE_ACCESS: {0} | {1} | {2} | inherited={3}" -f $path,$sid,$entry.FileSystemRights,$entry.IsInherited)
            $violations++
        }
    }
}
if($violations -gt 0){
    Write-Output ("M6_INSTALL_ACL_AUDIT=FAIL; writable broad-group entries={0}" -f $violations)
    exit 2
}
Write-Output 'M6_INSTALL_ACL_AUDIT=PASS'
