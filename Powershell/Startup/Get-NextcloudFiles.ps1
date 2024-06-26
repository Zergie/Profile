[CmdletBinding()]
param (
    [Parameter(Mandatory, ParameterSetName="ClipboardParameterSet")]
    [switch]
    $Clipboard,

    [switch]
    $DebugParameterBindung
)
dynamicparam {
    Set-Alias "New-DynamicParameter" "$PSScriptRoot\New-DynamicParameter.ps1"
    Set-Alias "Invoke-RestApi" "$PSScriptRoot\Invoke-RestApi.ps1"
    Set-Alias "Invoke-ExchangeWebServices" "$PSScriptRoot\Invoke-ExchangeWebServices.ps1"
    @(
        [pscustomobject]@{
            Type = [string]
            Name = "OutFolder"
        }
        "Url", "Password" |
            ForEach-Object {
                [pscustomobject]@{
                    Type = [string]
                    Name = $_
                    ParameterSetName = "UrlParameterSet"
                }
            }
        [pscustomobject]@{
            Type = [string]
            Name = "Workitem"
            ParameterSetName = "WorkitemParameterSet"
            ValidateSet = Invoke-RestApi `
                -Endpoint "POST https://dev.azure.com/{organization}/{project}/_apis/wit/workitemsbatch?api-version=7.0" `
                -Body @{
                    ids= @() + (Invoke-RestApi `
                            -Endpoint "POST https://dev.azure.com/{organization}/{project}/{team}/_apis/wit/wiql?api-version=7.0" `
                            -Body @{ query = "SELECT [System.Id] FROM WorkItems WHERE [System.State] <> 'Done' AND [System.WorkItemType] <> 'Task' AND [System.IterationPath] = @currentIteration('[TauOffice]\TauOffice Team <id:48deb8b1-0e33-40d0-8879-71d5258a79f7>')" }).workItems.id
                    fields= @(
                        "System.Id"
                        "System.Title"
                     )
                } |
                ForEach-Object value |
                ForEach-Object fields |
                ForEach-Object { "$($_.'System.Id') - $($_.'System.Title')" } |
                Sort-Object
        }
        [pscustomobject]@{
            Type = [string]
            Name = "Mail"
            # ParameterSetName = "MailParameterSet"
            ValidateSet = Invoke-ExchangeWebServices -Query "nextcloud" -First 3 |
                ForEach-Object { "$($_.DateTimeSent.ToString("dd.MM.yyyy")) - $($_.Subject)" }
        }
    ) | New-DynamicParameter
}
begin {

    if ($DebugParameterBindung) {
        $KnownVariables  = @()
        $KnownVariables += (Get-Variable).Name
        $KnownVariables += "_"
    }

    switch ( $PSCmdlet.ParameterSetName ){
        "MailParameterSet" {
            $text = (
                        . "$PSScriptRoot/Invoke-ExchangeWebServices.ps1" `
                            -Query $PSBoundParameters.Mail.Split("-")[1].Trim() `
                            -First 1
                    ).Body
        }
        "WorkitemParameterSet" {
            $text = (
                        . "$PSScriptRoot/Get-Issues.ps1" -WorkitemId (
                            $PSBoundParameters.Workitem | ForEach-Object { $_.Split("-")[0] }
                        )
                    ).fields.'System.Description'
        }
        "ClipboardParameterSet" {
            $text = Get-Clipboard
        }
        "UrlParameterSet" {
            $Url = $PSBoundParameters.Url
            $Password = $PSBoundParameters.Password
        }
    }

    $OutFolder = $PSBoundParameters.OutFolder
    if ($OutFolder.Length -eq 0) { $OutFolder = "C:\Dokumente\Daten" }
    $OutFolder = (Get-Item $OutFolder).FullName

    if ($text.Length -ne 0) {
        $Url = $text |
            Select-String 'https?://nextcloud\.rocom\.de[^ "\n\t]*' |
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
            Write-Host -ForegroundColor Cyan "found Url: $url"
            Write-Host -ForegroundColor Cyan "found Password: $password"
        }
    }

    if ($DebugParameterBindung) {
        Get-Variable |
            Where-Object { $_.GetType().FullName -in 'System.Management.Automation.LocalVariable' }
        Get-Variable |
            Where-Object { $_.Name -notin $KnownVariables }
        exit
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
                    $filename = [System.Uri]::UnescapeDataString($_) -replace ".+(\?path|&files)=/*", ''
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

            if ([System.IO.Path]::Exists($path)) {
                Remove-Item $path
            }

            Get-ChildItem $DownloadFolder |
                Compress-Archive -DestinationPath $path -Update
            # Remove-Item -Recurse -Force $DownloadFolder
        }
    }
    catch {
        $cefDownloader.Kill()
    }
}
