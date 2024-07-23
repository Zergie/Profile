param(
)

$mappings = @{
    ".mmd" = @{
                Output       = 'png'
                FilePath     = 'mmdc.cmd'
                ArgumentList = @(
                    '-i'
                    '"{input}"'
                    '-o'
                    '"{output}"'
                )
    }
    ".xml" = @{
                Output       = 'html'
                FilePath     = 'nvim'
                ArgumentList = @(
                    '-R'
                    '"{input}"'
                    '+"set nonumber"'
                    '+"set norelativenumber"'
                    '+TOhtml'
                    '+"w {output}"'
                    '+qa!'
                )
    }
    ".bmpr" = @{
                Output       = ''
                ScriptBlock  = {
                    param([string] $file, [string] $output)

                    $hwnd_terminal = Start-ThreadJob {
                        (Add-Type `
                        -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
                        ' `
                        -Name WindowAPI `
                        -PassThru)::GetForegroundWindow()
                    } | Wait-Job | Receive-Job

                    $process_old = Get-Process 'Balsamiq Mockups 3' |
                                        Where-Object MainWindowTitle -like "*$file*" |
                                        Select-Object -First 1

                    if ($null -eq $process_old) {
                        $process = Start-Process `
                                        -PassThru `
                                        -FilePath "C:\Program Files (x86)\Balsamiq Mockups 3\Balsamiq Mockups 3.exe" `
                                        -ArgumentList @(
                                            '"$file.FullName"'
                                        )
                        $process.WaitForInputIdle()
                        $process_old = $process
                    }

                    $setForegroundWindow = {
                        param([string] $hwnd)

                        $type = Add-Type `
                            -MemberDefinition '
                            [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
                            [DllImport("user32.dll")] public static extern int SetForegroundWindow(IntPtr hwnd);
                            ' `
                            -Name WindowAPI `
                            -PassThru

                        $hwnd = [int]::Parse($hwnd)
                        $hwnd = [IntPtr]::new($hwnd)
                        $type::ShowWindowAsync($hwnd, 4) | Out-Null
                        $type::SetForegroundWindow($hwnd) | Out-Null
                    }

                    Start-ThreadJob -ScriptBlock $setForegroundWindow -ArgumentList $process_old.MainWindowHandle | Wait-Job | Receive-Job

                    Write-Host $output
                    Start-ThreadJob -ArgumentList $output {
                        param([string] $output)
                        Add-Type -AssemblyName System.Windows.Forms
                        [System.Windows.Forms.SendKeys]::SendWait("+^R")
                        Start-Sleep -Milliseconds 1000
                        [System.Windows.Forms.SendKeys]::SendWait("$output{Enter}")
                        Start-Sleep -Milliseconds 1000
                        [System.Windows.Forms.SendKeys]::SendWait("{Tab}{Enter}")
                    } | Wait-Job | Receive-Job

                    Start-ThreadJob -ScriptBlock $setForegroundWindow -ArgumentList $hwnd_terminal | Wait-Job | Receive-Job

                    $process_old.WaitForInputIdle()
                    if ($null -ne $process) {
                        $process.CloseMainWindow()
                    }
                }
    }
}

$processes = Get-ChildItem |
    ForEach-Object {
        $file = $_
        $mapping = $mappings[$file.Extension]

        if ($null -ne $mapping) {
            $output = [System.IO.Path]::ChangeExtension($_, $mapping.Output).TrimEnd('.')
            $outdated = if (!(Test-Path $output)) {
                $true
            } elseif ((Get-ChildItem $output | Measure-Object LastWriteTime -Maximum).Maximum -lt $file.LastWriteTime) {
                $true
            } else {
                $false
            }

            if ($outdated) {
                Get-ChildItem $output -ErrorAction SilentlyContinue |
                    Remove-Item -Force -Recurse

                if ([string]::IsNullOrWhiteSpace($mapping.Output)) {
                    New-Item -ItemType Directory -Path $output -ErrorAction SilentlyContinue | Out-Null
                }

                if ($null -ne $mapping.ScriptBlock) {
                    Write-Host -ForegroundColor Cyan ">> $file -> $output"
                    Invoke-Command -ScriptBlock $mapping.ScriptBlock -ArgumentList $file.FullName,$output | Out-Null
                } else {
                    Write-Host -ForegroundColor Cyan "$file -> $output"
                    $p = @{
                        FilePath = $mapping.FilePath
                        ArgumentList = $mapping.ArgumentList |
                                            ForEach-Object { $_ -replace "{input}",$file.FullName -replace "{output}",$output }
                    }

                    $p | ConvertTo-Json -Compress | Write-Debug
                    Start-Process -PassThru @p
                }
            } else {
                Write-Host -ForegroundColor DarkCyan "$output is up to date."
            }
        }
    }

foreach ($p in $processes) {
    $p.WaitForExit()
}

function Invoke-VBScript {
    param(
         [Parameter(Mandatory = $true)]
         [string]
         $script
    )
    $path = "$($env:TEMP)\script.vbs"
    Set-Content -Path "$path" -Value $script

    $line = 0
    $script -split "`n" |
        ForEach-Object `
            -Begin   {"== vba script ==" } `
            -Process {
                $line++
                    $line.ToString().PadRight(3) + $_.ToString()
            } `
            -End     { "== end vba script ==" } |
        Write-Verbose

    cscript.exe "$path" //nologo
    Remove-Item "$path"
}
exit
Write-Host -ForegroundColor Cyan ""
Write-Host -ForegroundColor Cyan "Updateing Word"
Invoke-VBScript @"
dim stdout : set stdout = CreateObject("Scripting.FileSystemObject").GetStandardStream(1)
dim application: set application = GetObject(, "Word.Application")
dim ActiveDocument: set ActiveDocument = application.ActiveDocument

dim obj
For Each obj In ActiveDocument.StoryRanges
    obj.Fields.Update
Next

For Each obj In ActiveDocument.TablesOfContents
    obj.Update
Next

For Each obj In ActiveDocument.TablesOfFigures
    obj.Update
Next

For Each obj In ActiveDocument.TablesOfAuthorities
    obj.Update
Next

ActiveDocument.Range.Fields.Update

set db = Nothing
set application = Nothing
set stdout = Nothing
"@
