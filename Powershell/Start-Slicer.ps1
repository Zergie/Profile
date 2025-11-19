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
$args = "C:/Users/user/AppData/Local/Temp/Neutron/Body1.stl"
try {
    $item = Get-ChildItem ("$args*" -replace '(\[|\])','``$1') | Sort-Object LastWriteTime | Select-Object -Last 1
    $extension = $item.Extension
    Push-Location $item.Directory
    $file = $item.Name

    $result = $null
    # $result = (Invoke-RestMethod "http://localhost:5000/bodies").result
    if ($result) {
        Write-Debug "Found bodies, selecting the selected one..."
        $selected = $result |
            Get-Member -Type NoteProperty |
            ForEach-Object Name |
            ForEach-Object { $result.$_ } |
            Where-Object selected -EQ $true |
            Select-Object -First 1
        Write-Debug "Selected body: $($selected.name)"
        if ($selected) {
            # rotate the normal so it points to world-up (0,0,1) as an axis-angle (degrees)
            if ($selected.orientation) {
                Write-Debug "Calculating rotation vector..."
                function ConvertTo-RotationDeg {
                    param ([object]$vec)
                    $v = [PSCustomObject]@{ x = [double]$vec[0]; y = [double]$vec[1]; z = [double]$vec[2] }
                    $target = [PSCustomObject]@{x = 0.0; y = 0.0; z = 1.0}

                    $v_norm = [math]::Sqrt($v.x*$v.x + $v.y*$v.y + $v.z*$v.z)
                    if ($v_norm -eq 0.0) { return [PSCustomObject]@{ x = 0.0; y = 0.0; z = 0.0 } }

                    $v = [PSCustomObject]@{
                        x = $v.x / $v_norm
                        y = $v.y / $v_norm
                        z = $v.z / $v_norm
                    }

                    $dot = $v.x*$target.x + $v.y*$target.y + $v.z*$target.z
                    $dot = [math]::Max(-1.0, [math]::Min(1.0, $dot))

                    $eps = 1e-6
                    if (([math]::Abs($v.x - $target.x) -lt $eps) -and ([math]::Abs($v.y - $target.y) -lt $eps) -and ([math]::Abs($v.z - $target.z) -lt $eps)) {
                        return @([double]0.0, [double]0.0, [double]0.0)
                    }

                    if (([math]::Abs($v.x + $target.x) -lt $eps) -and ([math]::Abs($v.y + $target.y) -lt $eps) -and ([math]::Abs($v.z + $target.z) -lt $eps)) {
                        return @([double]180.0, [double]0.0, [double]0.0)
                    }

                    # cross product v x target
                    $axis = [PSCustomObject]@{
                        x = $v.y*$target.z - $v.z*$target.y
                        y = $v.z*$target.x - $v.x*$target.z
                        z = $v.x*$target.y - $v.y*$target.x
                    }
                    $axis_norm = [math]::Sqrt($axis.x*$axis.x + $axis.y*$axis.y + $axis.z*$axis.z)
                    if ($axis_norm -eq 0.0) { return @([double]0.0, [double]0.0, [double]0.0) }
                    $axis = [PSCustomObject]@{ x = $axis.x/$axis_norm; y = $axis.y/$axis_norm; z = $axis.z/$axis_norm }
                    $angle_deg = [math]::Acos($dot) * (180.0 / [math]::PI)

                    return [PSCustomObject]@{
                        x = [math]::Round($axis.x * $angle_deg, 3)
                        y = [math]::Round($axis.y * $angle_deg, 3)
                        z = [math]::Round($axis.z * $angle_deg, 3)
                    }
                }

                $rotVec = ConvertTo-RotationDeg $selected.orientation[0]

                $pyScript = "
                    import sys, getopt, math, stl

                    args = {k: v for k, v in getopt.getopt(sys.argv[1:],'i:o:r:')[0]}
                    rx, ry, rz = (float(x) for x in args.get('-r', '0,0,0').split(','))

                    stl_mesh = stl.mesh.Mesh.from_file(args['-i'])
                    if (rx != 0.0): stl_mesh.rotate([1.0, 0.0, 0.0], math.radians(rx))
                    if (ry != 0.0): stl_mesh.rotate([0.0, 1.0, 0.0], math.radians(ry))
                    if (rz != 0.0): stl_mesh.rotate([0.0, 0.0, 1.0], math.radians(rz))
                    stl_mesh.save(args['-o'])
                " -split "`n" |
                    ForEach-Object { $_.TrimStart() } |
                    Out-String

                $output = [System.IO.Path]::Combine($item.DirectoryName, "$([System.IO.Path]::GetFileNameWithoutExtension($item.Name))-rotated$($item.Extension)")
                $expression = "python -c `$pyScript -i $item -o $output -r $($rotVec.x),$($rotVec.y),$($rotVec.z)"
                Write-Debug $expression
                Invoke-Expression $expression
                $item = Get-ChildItem $output
            }
        }
    }

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
        $urlFile = "$([System.IO.Path]::GetFileName($args).Trim()).$extension"
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
