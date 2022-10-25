[cmdletbinding()]
param (
)
begin {
    if ($null -eq (Get-FormatData -TypeName 'User.Database')) {
        Update-FormatData -PrependPath "$PSScriptRoot\..\Format\User.Database.ps1xml"
    }
}
process {
    Invoke-Sqlcmd -Database master -Query "SELECT name, compatibility_level, state_desc FROM sys.databases ORDER BY name" |
        ForEach-Object {
            $object = [pscustomobject]@{
                name= $_.name.ToString()
                compatibility_level= $_.compatibility_level.ToString()
                state_desc= $_.state_desc.ToString()
            }
            $object.PSObject.TypeNames.Insert(0,'User.Database')
            $object
        }
}
end {        
} 

