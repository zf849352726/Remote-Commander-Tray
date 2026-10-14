[CmdletBinding()]
param(
    [string]$InstallDir='D:\Apps\RemoteCommanderTray',
    [string]$DataBaseDir='D:\Apps\RemoteCommanderTrayData'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$paths=@($InstallDir,$DataBaseDir,(Split-Path -Parent $InstallDir))
$wellKnown=@('S-1-1-0','S-1-5-11','S-1-5-32-545')
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
        $writeBits=[int64]($entry.FileSystemRights -band $dangerous)
        if($entry.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
            $sid -notin $wellKnown -or $writeBits -eq 0) {continue}

        # Explicit non-inheriting "create SUBFOLDER only" permission at the TWO
        # provisioned roots allows a standard user to create their own SID folder.
        # It never grants the right to edit files, delete siblings or inherit a
        # write permission into another user's SID folder.
        $narrow=[int64][Security.AccessControl.FileSystemRights]::CreateDirectories
        $isAllowedCreateOnly =
            $sid -eq 'S-1-5-11' -and
            $path -in @($InstallDir,$DataBaseDir) -and
            !$entry.IsInherited -and
            $entry.InheritanceFlags -eq [Security.AccessControl.InheritanceFlags]::None -and
            $entry.PropagationFlags -eq [Security.AccessControl.PropagationFlags]::None -and
            $writeBits -eq $narrow
        if($isAllowedCreateOnly){
            Write-Output ("LIMITED_CREATE_DIRS_ONLY: {0}" -f $path)
            continue
        }
        Write-Output ("UNSAFE_WRITE_ACCESS: {0} | {1} | {2} | inherited={3}" -f $path,$sid,$entry.FileSystemRights,$entry.IsInherited)
        $violations++
    }
}
if($violations -gt 0){
    Write-Output ("M6_INSTALL_ACL_AUDIT=FAIL; writable broad-group entries={0}" -f $violations)
    exit 2
}
Write-Output 'M6_INSTALL_ACL_AUDIT=PASS'
exit 0
