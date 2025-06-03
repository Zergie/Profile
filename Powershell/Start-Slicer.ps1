$exception = $null
$conversation = @()
function Write-Log {
    [ordered]@{
        date         = (Get-Date).ToString()
        args         = $args
        conversation = $conversation
        exception    = @{
            FullyQualifiedErrorId = $exception.FullyQualifiedErrorId
            Message               = $exception.Exception.ErrorRecord.Exception.Message
            PositionMessage       = $exception.InvocationInfo.PositionMessage
        }
    } |
        ConvertTo-Json -Depth 2 |
        Set-Content "$env:TEMP\Start-Slicer.log" -Force
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
            Write-Host "Starting on port $port"
            $http.Start()
            break;
        } catch { }
    }
    if (!$http.IsListening) {
        $http.Start()
    }
    if ($http.IsListening) {
        Write-Host "IsListening on port $port"
        $url = "orcaslicer://open?file=$([System.Web.HttpUtility]::UrlEncode("http://localhost:$port/file.stl"))"
        $url = "orcaslicer://open?file=$("http://localhost:$port/$file.stl")"
        Write-Host "Starting '$url'"
        Start-Process $url
    }
    if ($http.IsListening) {
        $context = $http.GetContextAsync()
        if ($context.Wait(5000)) {
            $context = $context.Result
        } else {
            Write-Host "No connection received within timeout. Closing HttpListener."
            $http.Stop()
            $http.Close()
            throw "No connection received within timeout."
        }
    }
    Write-Host ">> $($context.Request.HttpMethod) $($context.Request.Url)"
    $conversation += ">> $($context.Request.HttpMethod) $($context.Request.Url)"
    $fs = [System.IO.File]::OpenRead($item.FullName)
    $context.Response.ContentLength64 = $fs.Length
    $context.Response.SendChunked = $false
    $context.Response.ContentType = "application/octet-stream"
    $context.Response.AddHeader("Content-disposition", "attachment; filename=" + $file)
    $fs.CopyTo($context.Response.OutputStream)
    $context.Response.StatusCode = 200
    $context.Response.StatusDescription = "Ok"
    Write-Host "<< $($context.Response.StatusCode) $($context.Response.StatusDescription)"
    $conversation += "<< $($context.Response.StatusCode) $($context.Response.StatusDescription)"
    $context.Response.OutputStream.Close()
    Start-Sleep -Seconds 10
    $http.Stop()
    $http.Close()
    $fs.Dispose()
    $http.Dispose()
    Pop-Location
} catch {
    $exception = $_
} finally {
    Write-Log
}
