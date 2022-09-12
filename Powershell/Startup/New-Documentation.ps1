#Requires -PSEdition Core

[CmdletBinding()]
param (
    # Specifies a path to one or more locations.
    [Parameter(Mandatory=$false,
               Position=0,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false,
               HelpMessage="Path to empty word document.")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Template = "$PSScriptRoot\Template.docx",

    
    [parameter(Mandatory=$false,
               ParameterSetName="ParameterSetName",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [object[]]
    $workitem,

    [parameter(Mandatory=$false,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [switch]
    $Interactive,

    [parameter(Mandatory=$false,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [switch]
    $Update
)
Begin {
    if ($null -eq $workitem) {
        $workitem = @( 
                        Get-GitStatus |
                            ForEach-Object Branch |
                            Select-String -Pattern \d+$ |
                            ForEach-Object { Get-Issues -id $_.Matches.Value }
                    )
    }

    $hwnd = Start-Job {
        (Add-Type `
        -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        ' `
        -Name WindowAPI `
        -PassThru)::GetForegroundWindow()
    } | Wait-Job | Receive-Job

    $word = New-Object -ComObject Word.Application
    $word.visible = $true

    Start-Job -ArgumentList $hwnd {
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
    } | Wait-Job | Receive-Job
}
Process {
    Write-Host "Processing workitem $($workitem.id)"
    
    $word.Documents.Open($Template) | Out-Null

    $f = $word.Selection.Find()
    $f.Forward = $true
    $f.text = "__"

    $i = 0
    while ($f.Execute()) {
        $word.Selection.MoveEnd(2, 1) | Out-Null

        $text = switch -Regex ($i) {
            "^(0)$"  {
                $null
                $workitem.fields.'System.Title' 
            }
            "^(1)$"  {
                $null
                $null 
            }
            "^(2)$"  {
                $null
                $workitem.id 
            }
            "^(3)$"  {
                $null
                $workitem.fields.'System.AssignedTo'.displayName 
            }
            "^(4)$"  {
                $null
                $workitem.fields.'System.ChangedDate'.ToString("dd.MM.yyyy") 
            }
            "^(5)$"  {
                "In welchen Fachbereich wurde getestet?"
                "mehrere Fachbereiche" 
            }
            "^(6)$"  {
                "Welche Rechte wurden für den Test zusätzlich freigeschaltet?"
                "keine" 
            }
            "^(7)$"  {
                "Wurden neue Rechte hinzugefügt, wenn ja, welche?"
                "nein" 
            }
            "^(8)$"  {
                "Wurden neue Platzhalter hinzugefügt, wenn ja, welche?"
                "nein" 
            }
            "^(9)$"  {
                "Wurden Felder im LG hinzugefügt, wenn ja welche? Welcher LG?"
                "nein" 
            }
            "^(10)$" {
                "Wurden Anpassungen zur Aufgabendefinition vorgenommen, wenn ja, welche?"
                "nein" 
            }
            "^(11)$" {
                "Wurden Anpassungen in anderen Funktionen vorgenommen, die mit getestet werden müssen?"
                "nein" 
            }
            "^(12)$" {
                "Gibt es Besonderheiten/Abhängigkeiten, die getestet werden müssen?"
                "nein" 
            }
            "^(13)$" {
                "Software-technische Dokumentation"
                ""
            }
        }

        $word.ActiveWindow.ScrollIntoView($word.Selection.Range, $false) | Out-Null

        if ($Interactive -and $null -ne $text[0]) {
            $answer = Read-Host "$($text[0]) [$($text[1])]"
            if ($answer.Length -gt 0) {
                $text = $answer
            } else {
                $text = $text[1]
            }
        } else {
            $text = $text[1]
        }

        if ($null -ne $text) {
            $word.Selection.text = "$text"
            # $word.Selection.text = "$i"
        }

        $word.Selection.Move(1, 1) | Out-Null
        $i++
    }
    
    # $word.Selection.Start = $word.ActiveDocument.Range.End
    # $word.Selection.End = $word.ActiveDocument.Range.End
    # $word.Selection.Move(3, -1) | Out-Null
    # $word.Selection.Move(5, 1) | Out-Null
    # $word.Selection.Start = $word.Selection.End
    # $word.Selection.text = "siehe Aufgabenbeschreibung"

    # Set-Content -Path "C:\temp\temp.html" -Value "<html><body>$($workitem.fields.'System.Description')</body></html>"
    # $word.Selection.InsertFile("C:\temp\temp.html", [Type]::Missing, [Type]::Missing, $false, $false)

    $filename = "$((Get-Location).Path)\$($workitem.id).docx"
    Remove-Item $filename -Force -ErrorAction SilentlyContinue
    $word.ActiveDocument.SaveAs2($filename) | Out-Null
    $word.ActiveDocument.Close() | Out-Null

    if ($Update) {
        Get-ChildItem $filename | Update-Documentation
    } else {
        Get-ChildItem $filename
    }
}
End {    
    $word.Quit() | Out-Null
}