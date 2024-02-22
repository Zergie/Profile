[CmdletBinding()]
param (
    # [Parameter(Mandatory, Position=0, ParameterSetName="UrlParameterSet")]
    [string]
    $Url,

    # [Parameter(Mandatory, Position=0, ParameterSetName="WorkitemParameterSet")]
    [int]
    $WorkitemId,

    [Parameter(Mandatory)]
    [string]
    $OutFolder,


    [Parameter()]
    [string]
    $Password
)
dynamicparam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Mail
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Mandatory = $true
    # $ParameterAttribute.ParameterSetName = "MailParameterSet"
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        . "$PSScriptRoot/Invoke-ExchangeWebServices.ps1" -Query "nextcloud,datenbank" -First 3 |
                ForEach-Object { "$($_.DateTimeSent.ToString("dd.MM.yyyy")) - $($_.Subject)" }
    ))
    $AttributeCollection.Add($ValidateSetAttribute)
    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Mail", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    return $RuntimeParameterDictionary
}
begin {
    switch ( $PSCmdlet.ParameterSetName ){
        "MailParameterSet" {
            $text = (
                        . "$PSScriptRoot/Invoke-ExchangeWebServices.ps1" `
                            -Query $PSBoundParameters["Mail"].Split("-")[1].Trim() `
                            -First 1
                    ).Body
        }
        "WorkitemParameterSet" {
            $text = (
                        . "$PSScriptRoot/Get-Issues.ps1" -WorkitemId $WorkitemId
                    ).fields.'System.Description'
        }
    }

    if ($text.Length -ne 0) {
        $Url = $text |
            Select-String "http.*nextcloud\.rocom\.de[^ \n\t]*" |
                ForEach-Object { $_.Matches.Value } |
                Select-Object -First 1

            $password = $text |
                Select-String "((?<=passwor[td])|pw)\s*[:]?\s*(?<password>[^ ]+)" |
                ForEach-Object { $_.Matches.Groups } |
                Where-Object Name -eq password |
                ForEach-Object Value |
                Select-Object -First 1

            if ($null -eq $Url -or $Url.Length -eq 0) {
                throw "Could not find nextcloud url!"
            } else {
                Write-Host -ForegroundColor Cyan "found url: $url"
                Write-Host -ForegroundColor Cyan "found password: $password"
            }
    }
}
end {
    Start-Process `
        -WindowStyle Minimized `
        -FilePath (Get-ChildItem C:\GIT\QuickAndDirty\bsc\CefSharpDownloader\ -Recurse -Filter CefSharpDownloader.exe |
                        Sort-Object LastWriteTime |
                        Select-Object -Last 1 |
                        ForEach-Object FullName)
    $cefDownloader = Get-Process CefSharpDownloader
    $cefDownloader.WaitForInputIdle() | Out-Null

    try {
        Invoke-WebRequest -Method Post -Uri http://localhost:8888 | Out-Null

        Invoke-WebRequest -Method Post -Uri http://localhost:8888/get -Body $Url | Out-Null
        if ($null -ne $password) {
            Invoke-WebRequest -Method Post -Uri http://localhost:8888/js -Body "
                input = document.querySelectorAll('input[name=password]')[0];
                input.value = 'zkpo1J73zE';
                button = document.querySelectorAll('#password-submit')[0];
                button.disabled = false;
                button.click();
            " | Out-Null
        }

        $files = ""
        while ($files.Length -lt 3) {
            Start-Sleep -Seconds 1
            $files = Invoke-WebRequest -Method Post -Uri http://localhost:8888/js -Body "
                console.log(Array.from(document.querySelectorAll('tr[data-type]')).map(x => x.querySelector('a')).map(x => x.href))
            " |
                ForEach-Object Content
        }
        $files = (Invoke-WebRequest -Method Post -Uri http://localhost:8888/js -Body "
            console.log(Array.from(document.querySelectorAll('tr[data-type]')).map(x => x.querySelector('a')).map(x => x.href))
        " |
            ForEach-Object Content |
            ConvertFrom-Json |
            ForEach-Object console).Split(",") |
            ForEach-Object { $_.Trim() }

        $cookie = Invoke-WebRequest -Method Post -Uri http://localhost:8888/cookies |
            ForEach-Object Content |
            ConvertFrom-Json |
            Get-Member -Type NoteProperty|
            Where-Object Name -like "oc*"|
            ForEach-Object{ "$($_.Definition.Substring(7))" }|
            Join-String -Separator ';'

        $count = ($files | Measure-Object).Count

        if ($count -gt 1) {
            $DownloadFolder = [System.IO.Path]::Combine($env:TEMP, [System.IO.Path]::GetRandomFileName())
            if (![System.IO.Path]::Exists($DownloadFolder)) {
                Remove-Item -Recurse -Force $DownloadFolder -ErrorAction SilentlyContinue
            }
            New-Item $DownloadFolder -ItemType Directory | Out-Null
        } else {
            $DownloadFolder = $OutFolder
        }

        $files |
            ForEach-Object {
                if ($count -gt 1) {
                    $filename = [System.Uri]::UnescapeDataString(($_ -replace ".+&files=", ''))
                } else {
                    $filename = "NextCloud.zip"
                }
                $path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($DownloadFolder, $filename))

                if ([System.IO.Path]::Exists($path)) {
                    Remove-Item $path
                }

                Write-Host -ForegroundColor Cyan "Downloding $_ => $path"
                Invoke-WebRequest $_ -Headers @{Cookie=$cookie} -OutFile $path

                if (![System.IO.Path]::Exists($path)) {
                    Write-Host -ForegroundColor Cyan "Downloding (without cookies) $_ => $path"
                    Invoke-WebRequest $_ -OutFile $path
                }

                if (![System.IO.Path]::Exists($path)) {
                    Write-Error "$path was not downloaded!"
                }

                if ($count -gt 1 -and $path.EndsWith(".zip")) {
                    Write-Host -ForegroundColor Cyan "Expand archive: $path"
                    Expand-Archive $path -DestinationPath $DownloadFolder
                    Remove-Item $path
                }
            }

        Invoke-WebRequest -Method Post -Uri http://localhost:8888/quit | Out-Null

        if ($count -gt 1) {
            $path = [System.IO.Path]::Combine($OutFolder, "NextCloud.zip")
            Write-Host -ForegroundColor Cyan "Compress archive => $path"

            Get-ChildItem $DownloadFolder |
                Compress-Archive -DestinationPath $path -Update
            # Remove-Item -Recurse -Force $DownloadFolder
        }
    }
    catch {
        $cefDownloader.Kill()
    }
}
