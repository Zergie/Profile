$log = [ordered]@{
    date      = (Get-Date).ToString()
    args      = $args
    debug     = @()
    exception = @{
    }
}
function Write-Log {

    $log |
        ConvertTo-Json -Depth 2 |
        Set-Content "$env:TEMP\Start-Slicer.log" -Force -Encoding utf8
}
function Write-Debug {
    param([string] $message)
    Write-Host $message
    $log.debug += $message
}
try {
    $item = Get-ChildItem ("$args*" -replace '(\[|\])','``$1') | Sort-Object LastWriteTime | Select-Object -Last 1
    Push-Location $item.Directory
    $file = $item.Name

    Write-Log
    Add-Type -AssemblyName System.Web

    foreach ($try in 0..5) {
        $http = [System.Net.HttpListener]::new()
        $port = Get-Random -Minimum 49152 -Maximum 65535
        $http.Prefixes.Add("http://localhost:$port/")
        try {
            Write-Debug "Starting on port $port"
            $http.Start()
            break;
        } catch { }
    }
    if (!$http.IsListening) {
        $http.Start()
    }
    if ($http.IsListening) {
        Write-Debug "IsListening on port $port"
        # $url = "orcaslicer://open?file=$([System.Web.HttpUtility]::UrlEncode("http://localhost:$port/file.stl"))"
        $urlFile = "$([System.IO.Path]::GetFileName($args).Trim()).stl"
        Write-Debug "urlFile: $urlFile"
        $url = "orcaslicer://open?file=$("http://localhost:$port/$urlFile")"
        Write-Debug "Starting '$url'"
        Start-Process $url
    }
    if ($http.IsListening) {
        $context = $http.GetContextAsync()
        if ($context.Wait(5000)) {
            $context = $context.Result
        } else {
            $http.Stop()
            $http.Close()
            throw "No connection received within timeout."
        }
    }
    Write-Debug ">> $($context.Request.HttpMethod) $($context.Request.Url)"
    $fs = [System.IO.File]::OpenRead($item.FullName)
    $context.Response.ContentLength64 = $fs.Length
    $context.Response.SendChunked = $false
    $context.Response.ContentType = "application/octet-stream"
    $context.Response.AddHeader("Content-disposition", "attachment; filename=" + $file)
    $fs.CopyTo($context.Response.OutputStream)
    $context.Response.StatusCode = 200
    $context.Response.StatusDescription = "Ok"
    Write-Debug "<< $($context.Response.StatusCode) $($context.Response.StatusDescription)"
    $context.Response.OutputStream.Close()
    Write-Debug "Waiting 10 seconds before closing."
    Write-Log
    Start-Sleep -Seconds 10
    $http.Stop()
    $http.Close()
    $fs.Dispose()
    $http.Dispose()
    Write-Debug "All done. Bye bye!"
    Pop-Location
} catch {
    Write-Host -ForegroundColor Red $_.Message
    $log.exception.FullyQualifiedErrorId = $exception.FullyQualifiedErrorId
    $log.exception.Message               = $exception.Message
    $log.exception.PositionMessage       = $exception.PositionMessage
} finally {
    Write-Log
}
