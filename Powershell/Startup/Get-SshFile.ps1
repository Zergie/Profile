[cmdletbinding()]
param(
    [Parameter(Mandatory,
               ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $path
)
begin {

}
process {
    foreach ($item in $path) {
        $cmd = ". $env:windir\System32\OpenSSH\scp.exe -P 23 u266601-sub2@u266601-sub2.your-storagebox.de:$item ."
        Write-Debug $cmd
        Invoke-Expression $cmd
    }
}
end {

}
