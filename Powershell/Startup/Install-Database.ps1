[CmdletBinding()]
Param(
)
dynamicparam {
    $local_folder = "D:\Daten"
    $shouldUpdateJson = try { ((Get-Date) - (Get-ChildItem $env:TEMP -Filter docker_ftp.json).LastWriteTime).TotalDays -gt 15 } catch { $true }
    
    if ($shouldUpdateJson) {
        $ftp = Invoke-Expression (Get-Content -raw $dockerScript | Select-String -Pattern "\`$Global:ftp = (@\{[^}]+})").Matches.Groups[1].Value
        
        $FTPRequest = [System.Net.FtpWebRequest]::Create("$($ftp.url)/$($ftp.root)")
        $FTPRequest.Credentials = New-Object System.Net.NetworkCredential($ftp.user, $ftp.password)
        $FTPRequest.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $FTPResponse = $FTPRequest.GetResponse()
        $ResponseStream = $FTPResponse.GetResponseStream()
        $StreamReader = New-Object System.IO.StreamReader $ResponseStream
        $folders = ($StreamReader.ReadToEnd() -split "`n" ) | 
            Where-Object { -not $_.Contains(".") } |
            Where-Object { $_ -gt "" }
        $StreamReader.close()
        $ResponseStream.close()
        $FTPResponse.Close()
        
        $subfolders = New-Object System.Collections.ArrayList
        $folders |
            ForEach-Object {
                $FTPRequest = [System.Net.FtpWebRequest]::Create("$($ftp.url)/$_")
                $FTPRequest.Credentials = New-Object System.Net.NetworkCredential($ftp.user, $ftp.password)
                $FTPRequest.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
                $FTPResponse = $FTPRequest.GetResponse()
                $ResponseStream = $FTPResponse.GetResponseStream()
                $StreamReader = New-Object System.IO.StreamReader $ResponseStream
                ($StreamReader.ReadToEnd() -split "`n" ) | 
                    Where-Object { $_ -gt "" } |
                    ForEach-Object { $_.Trim("`r", "`n") } |
                    ForEach-Object { $subfolders.Add("ftp://$_") | Out-Null }
                $StreamReader.close()
                $ResponseStream.close()
                $FTPResponse.Close()
            }
        $subfolders | ConvertTo-Json | Out-File -Encoding UTF8 "$env:TEMP/docker_ftp.json"
    }
    
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Path
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $true
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        @(
            Get-ChildItem -Directory "$local_folder" | Where-Object { Test-Path ("$_\*.bak") } 
            Get-ChildItem -File "$local_folder\*.zip"
            Get-ChildItem -File "$local_folder\*.7z"
        ) | ForEach-Object { 
            ".\" + $_.FullName.Substring("$local_folder\".Length) 
            "./" + $_.FullName.Substring("$local_folder\".Length) 
        }

        Get-Content "$env:TEMP/docker_ftp.json" -Encoding UTF8 | ConvertFrom-Json
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Path", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    return $RuntimeParameterDictionary
}
process {
    $Path = $PSBoundParameters['Path']

    if ($Path.StartsWith(".")) {
        $Path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine("D:\Daten", $Path))
    }

    if ($PSDefaultParameterValues["*:Database"] -ne "master") {
        $old = $PSDefaultParameterValues["*:Database"]
        Set-SqlDatabase master
    }

    $result = @{}
    $p = $PSBoundParameters.GetEnumerator() | ForEach-Object -Process { $result.Add($_.Key, $_.Value) } -End{ $result }
    $p.Remove("Path")

    & $dockerScript -Install $Path @p
        
    if ($null -ne $old) {
        Set-SqlDatabase $old
    }
}