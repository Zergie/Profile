[CmdletBinding()]
param (
    [Parameter(Mandatory, Position=0, ParameterSetName="UrlParameterSet")]
    [string]
    $Url,

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
    $ParameterAttribute.ParameterSetName = "MailParameterSet"
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        . "$PSScriptRoot/Invoke-ExchangeWebServices.ps1" -Query "nextcloud" -First 3 |
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
            $mail = . "$PSScriptRoot/Invoke-ExchangeWebServices.ps1" -Query $PSBoundParameters["Mail"].Split("-")[1].Trim() -First 1

            $Url = $mail.Body |
                        Select-String "http.*nextcloud\.rocom\.de[^ \n\t]*" |
                        ForEach-Object { $_.Matches.Value } |
                        Select-Object -First 1

            $Password = $mail.Body |
                        Select-String "(?<=passwor[td]).*|pw.*" |
                        ForEach-Object { $_.Matches.Value.TrimStart(' ', ':') } |
                        Select-Object -First 1

            if ($null -eq $Url -or $Url.Length -eq 0) {
                throw "Could not find nextcloud url!"
            }
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
        if ($null -ne $Password) {
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
            ForEach-Object console).Split(",")

        $cookie = Invoke-WebRequest -Method Post -Uri http://localhost:8888/cookies |
            ForEach-Object Content |
            ConvertFrom-Json |
            Get-Member -Type NoteProperty|
            Where-Object Name -like "oc*"|
            ForEach-Object{ "$($_.Definition.Substring(7))" }|
            Join-String -Separator ';'

        $files |
            Select-Object -Skip 1 |
            ForEach-Object {
                $filename = $_ -replace ".+&files=", ''
                $path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($OutFolder, $filename))

                Write-Host -ForegroundColor Cyan "Downloding $path"
                Invoke-WebRequest $_ -Headers @{Cookie=$cookie} -OutFile $path
            }

        Invoke-WebRequest -Method Post -Uri http://localhost:8888/quit | Out-Null
    }
    catch {
        $cefDownloader.Kill()
    }
}
