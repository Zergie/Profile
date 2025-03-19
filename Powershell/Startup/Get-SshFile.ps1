[cmdletbinding()]
param(
    [Parameter(Mandatory,
               ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $path
)
dynamicparam {
    Set-Alias "Invoke-Ssh" "$PSScriptRoot\Invoke-Ssh.ps1"
    Register-ArgumentCompleter -CommandName "Get-SshFile.ps1" -ParameterName "Path" -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
        if ($fakeBoundParameter.Contains("Path")) {
            Invoke-Ssh tree -if --noreport -L 1 $($fakeBoundParameter.Path | Select-Object -Last 1) |
                    Select-Object -Skip 1 |
                    ForEach-Object { New-Object System.Management.Automation.CompletionResult($_,$_,'ParameterValue', $_) }
        } else {
            Invoke-Ssh tree -if --noreport -L 1 |
                    Select-Object -Skip 1 |
                    ForEach-Object { $_.SubString(2) } |
                    ForEach-Object { New-Object System.Management.Automation.CompletionResult($_,$_,'ParameterValue', $_) }
        }
    }
}
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
