param (
    [Parameter(Mandatory=$false,
               ParameterSetName="ParameterSetName")]
    [switch]
    $Plain
)
begin {
}
process {
    Invoke-Sqlcmd -Database master -Query "SELECT name, compatibility_level, state_desc FROM sys.databases ORDER BY name" |
        ForEach-Object {
            [PSCustomObject]@{
                name= $_.name.ToString()
                compatibility_level= $_.compatibility_level.ToString()
                state_desc= $_.state_desc.ToString()
            }
        } |
        ForEach-Object {
            $object = $_

            if (!$Plain) {
                if ($object.name -eq $($PSDefaultParameterValues["*:Database"])) {
                    foreach ($prop in $object | Get-Member -MemberType NoteProperty) 
                    {
                        $object.($prop.name) = "`e[38;5;2m$($object.($prop.name))`e[0m"
                    }
                }
            }

            $object
        }
}
end {        
} 

