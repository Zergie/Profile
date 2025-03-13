$item = Get-ChildItem ("$args*" -replace '(\[|\])','``$1') | Sort-Object LastWriteTime | Select-Object -Last 1
Push-Location $item.Directory
$file = $item.Name

$Debug = $false
$Debug = $Debug -or $path.Length -eq 0
if ($Debug) {
    Write-Host -ForegroundColor Yellow "`$args=" -NoNewline
    $args | ConvertTo-Json | Write-Host -ForegroundColor Yellow
    Write-Host -ForegroundColor Yellow "`$Location=$(Get-Location)"
    Write-Host -ForegroundColor Yellow "`$file=$file"
}

$http = [System.Net.HttpListener]::new()
$http.Prefixes.Add("http://localhost:8080/")
$http.Start()
if ($http.IsListening) {
    Start-Process "orcaslicer://open?file=$([System.Web.HttpUtility]::UrlEncode("http://localhost:8080/$file"))"
}
$context = $http.GetContext()
Write-Host -ForegroundColor Magenta ">> $($context.Request.HttpMethod) $($context.Request.Url)"
$fs = [System.IO.File]::OpenRead((Resolve-Path $file).Path)
$context.Response.ContentLength64 = $fs.Length
$context.Response.SendChunked = $false
$context.Response.ContentType = "application/octet-stream"
$context.Response.AddHeader("Content-disposition", "attachment; filename=" + $file)
$fs.CopyTo($context.Response.OutputStream)
$context.Response.StatusCode = 200
$context.Response.StatusDescription = "Ok"
Write-Host -ForegroundColor Magenta "<< $($context.Response.StatusCode) $($context.Response.StatusDescription)"
$context.Response.OutputStream.Close()
$fs.Dispose()
$http.Stop()
$http.Close()
$http.Dispose()
Pop-Location

if ($Debug) { Read-Host }
