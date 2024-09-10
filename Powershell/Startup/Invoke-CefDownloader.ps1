[cmdletbinding(DefaultParameterSetName="ActionParameterSet")]
param(
    [Parameter(Mandatory,
               ParameterSetName="KillParameterSet",
               ValueFromPipeline)]
    [switch]
    ${Kill}
)
DynamicParam {
    Set-Alias "New-DynamicParameter" "$PSScriptRoot\New-DynamicParameter.ps1"
    @(
        [pscustomobject]@{
            Position = 0
            Type = [string]
            Name = "Action"
            ParameterSetName = "ActionParameterSet"
            ValidateSet = Select-String `
                            -Path "C:\git\QuickAndDirty\bsc\CefSharpDownloader\CefSharpDownloader\HttpServer.cs" `
                            -Pattern '(?<=case "/)[^"]+' |
                                ForEach-Object { $_.Matches.Value } |
                                ForEach-Object { $_[0].ToString().ToUpper() + $_.Substring(1) }
        }
        [pscustomobject]@{
            Position = 1
            Type = [string]
            Name = "Body"
            ParameterSetName = "ActionParameterSet"
        }
    ) | New-DynamicParameter


}
Begin {
    $cefDownloader = Get-Process CefSharpDownloader -ErrorAction SilentlyContinue
    if ($null -eq $cefDownloader) {
        Start-Process `
            -WindowStyle Minimized `
            -FilePath (Get-ChildItem C:\GIT\QuickAndDirty\bsc\CefSharpDownloader\ -Recurse -Filter CefSharpDownloader.exe |
                            Sort-Object LastWriteTime |
                            Select-Object -Last 1 |
                            ForEach-Object FullName)
        $cefDownloader = Get-Process CefSharpDownloader
        $cefDownloader.WaitForInputIdle() | Out-Null
    }

    if ($null -eq $cefDownloader) {
        Write-Error "Could not get instance of CefSharpDownloader"
        exit
    }
}
Process {
    if ($PSBoundParameters.ContainsKey("Action")) {
        Invoke-WebRequest -Method Post -Uri http://localhost:8888/$($PSBoundParameters.Action) -Body $PSBoundParameters.Body
    }
    if ($Kill) {
        $cefDownloader.Kill()
    }
}
