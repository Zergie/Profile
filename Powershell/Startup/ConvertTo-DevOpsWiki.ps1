#Requires -PSEdition Core
param (
    [Parameter(Mandatory)]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Path
)
Install-Module -Scope CurrentUser PSParseHTML -ErrorAction Stop

$content = Get-Content $Path -Encoding utf8 | Out-String
$markdown = ((ConvertFrom-HTML -Content $content -Engine AngleSharp).QuerySelectorAll(".fl-accordion-item") |
    ForEach-Object {
        $children = $_.QuerySelectorAll("div")
        "## $($children[0].QuerySelector("a").TextContent)"
        $children[1].children |
            ForEach-Object {
                $n = $_
                ""

                switch ($n.tagname){
                    "h3"  { "### $($n.InnerHtml)" }
                    "p"   { "$($n.InnerHtml)" }
                    "pre" {
                        if ($n.InnerHtml -like "*<span *") {
                            '<pre>'
                            "$($n.InnerHtml)"
                            '</pre>'
                        } else {
                            '```'
                            "$($n.InnerHtml)"
                            '```'
                        }
                    }
                    default {
                        Write-Warning "unknow tag: $($n.tagname)"
                        $n.OuterHtml
                    }
                }
            }
    } |
    Out-String).Trim() `
        -replace "(;?\s+(--|var\(--|data-)darkreader-[^;>`"]+(;|`"`"|))","" `
        -replace "</?strong>","**" `
        -replace "&lt;","<" `
        -replace "&gt;",">" `
        -replace "&amp;","&" `
        -split "`n"

$(
    $current = ""
    $markdown |
        ForEach-Object {
            if ($_.StartsWith("## ")) {
                $current
                $current = [pscustomobject]@{
                    Title   = $_.Substring(3)
                    Content = ""
                }
            } else {
                $current.Content += "`n$($_)"
            }
        }
    $current
) | Where-Object { $_.Title.Length -gt 0 }
