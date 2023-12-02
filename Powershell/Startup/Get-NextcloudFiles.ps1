[CmdletBinding()]
param (
    [Parameter(Position=0, Mandatory=$true)]
    [string]
    $Url,

    [Parameter(Mandatory=$true)]
    [string]
    $OutFolder,

    [Parameter()]
    [string]
    $Password
)
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

                Write-Host -ForegroundColor Cyan "Downloding $filename"
                Invoke-WebRequest $_ -Headers @{Cookie=$cookie} -OutFile $path
            }

        Invoke-WebRequest -Method Post -Uri http://localhost:8888/quit | Out-Null
    }
    catch {
        $cefDownloader.Kill()
    }
}
