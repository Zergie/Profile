[CmdletBinding()]
param (
    [Parameter()]
    [string[]]
    $Include = @(
        "NET", ".NET", "C#", "vba", "vb6", "WiX", "MSI", "NSIS", "Installer", "PowerShell", "CI/CD", "Microsoft Sql-Server"
        "Software Architect", "Solutions Architect", "Technical Lead", "Lead Developer", "Systemarchitekt", "Enterprise Architecture", "Clean Architecture", "Azure DevOps Engineer",
        "Build Engineer", "Release Engineer", "Pipeline Engineer", "DevOps Architect", "Configuration Manager", "Infrastructure Automation", "WiX Toolset", "MSI-Entwicklung",
        "Setup Engineer", "Inno Setup", "Deployment Engineer"
    ),

    [Parameter()]
    [string[]]
    $Exclude,

    [Parameter()]
    [switch]
    $NoExport,

    [Parameter()]
    [switch]
    $All,

    [Parameter()]
    [int]
    $MaxAgeHours = 64
)
$ErrorActionPreference = 'Break'
$filename = "C:/Dokumente/Dokumente/Freelancer-Projects.xlsx"
$worksheetName = "Freelancer Projects"
$ThrottleLimit = 16

if ($All) { $NoExport = $true }

Import-Module ImportExcel
$known_projects = $(if ($All) {@()} else {(Import-Excel -Path $filename -WorksheetName $worksheetName -ErrorAction SilentlyContinue).ID})
Write-Host "Already known projects: $($known_projects.Count)"

$filter = @{}
Import-Excel -Path $filename -WorksheetName "Filter" -ErrorAction SilentlyContinue |
    ForEach-Object { $filter[$_.color] += @() + $_.Tag.Trim() }

$env:GetFreelancerProjects_Filter = $filter | ConvertTo-Json -Depth 5
if ($Exclude.Count -eq 0) {
    $Exclude = $filter.red
}

function Get-Html {
    param (
        [string]$Uri
    )
    Write-Debug $Uri
    $request = Invoke-WebRequest `
        -Uri $Uri `
        -TimeoutSec 10 `
        -UserAgent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3.1 Safari/605.1.15" `
        -UseBasicParsing
    $html = New-Object -Com "HTMLFile"
    [string]$htmlBody = $request.Content
    $html.write([ref]$htmlBody)
    $html
}
$GetHtmlFunctionDefinition = ${function:Get-Html}.ToString()

$typeName = 'User.FreelancerProject'
if ($null -eq (Get-FormatData -TypeName $typeName -ErrorAction SilentlyContinue)) {
    Update-FormatData -PrependPath "$PSScriptRoot\..\Format\${typeName}.ps1xml"
}

Write-Host "Searching for projects with query:" -NoNewline
$projects = $Include |
    Sort-Object -Unique |
    ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        ${function:Get-Html} = $using:GetHtmlFunctionDefinition

        # Get the project of listings page
        Write-Host " '$_'" -NoNewline

        $params = @(
            [ordered]@{
                'remoteInPercent[0]' = 100
                'query'       = $_
                'countries[]' = 1
                'sort'        = 1
                'pagenr'      = 1
            }
            [ordered]@{
                'remoteInPercent[0]' = 1
                'location'    = 2930367
                'radius'      = 50
                'city'        = 'Bad Endorf'
                'query'       = $_
                'countries[]' = 1
                'sort'        = 1
                'pagenr'      = 1
            }
        ).GetEnumerator()  |
            ForEach-Object { "$([System.Web.HttpUtility]::UrlEncode($_.Name))=$([System.Web.HttpUtility]::UrlEncode($_.Value))" } |
            Join-String -Separator '&'
        $uri = "https://www.freelancermap.de/projektboerse.html?$params"

        $html = Get-Html -Uri $uri
        $html.getElementsByClassName("project-card") |
            ForEach-Object {
                # Extract basic project info
                $project_card = $_
                $project = [PSCustomObject]@{
                    RawContent = $project_card
                    Title      = $project_card.querySelector("[data-testid='title']").innerText
                    Link       = "https://www.freelancermap.de/" + $project_card.querySelector("[data-testid='title']").pathname.TrimStart("/")
                    Date       = [datetime]::Parse($project_card.querySelector("[data-testid='created']").innerText)
                    CreatedBy  = $project_card.querySelector(".mg-b-display-m").innerText
                    Age        = $null

                    RawDetails = $null
                    Tags       = $null
                    Description= $null
                    Contact    = $null
                    ProjectId  = $null
                    Score      = $null
                    ScoreDescription = $null
                }
                $project.Age = [System.Math]::Round(((Get-Date) - $project.Date).TotalHours)
                $project
            }
    } |
    Group-Object Link |
    ForEach-Object {
        # Remove duplicates, keep the most recent
        $_.Group | Select-Object ProjectId, Title, Link, Date, Age, CreatedBy | ConvertTo-Json | Write-Debug
        $_.Group | Sort-Object Age | Select-Object -First 1
    } |
    Where-Object {
        # Filter by age, considering weekends
        $weekday = (Get-Date).DayOfWeek
        if ($_.Age -le $MaxAgeHours) {
            # pass
        } elseif ($weekday -eq 'Monday' -and $_.Date.DayOfWeek -in @('Friday', 'Saturday', 'Sunday')) {
            # pass
        } else {
            return $false
        }

        return $true
    } |
    ForEach-Object -Parallel {
        ${function:Get-Html} = $using:GetHtmlFunctionDefinition

        # Get detailed project info
        $_.RawDetails = Get-Html -Uri $_.Link
        $_.Tags = $_.RawDetails.getElementsByClassName("badge") |
            ForEach-Object textContent |
            Where-Object { $_ -notin "IT" }
        $_.Description = $_.RawDetails.getElementsByClassName("project-body-description") | ForEach-Object textContent

        $project_body_infos = $_.RawDetails.getElementsByClassName("project-body-info") |
            ForEach-Object childNodes |
            ForEach-Object {

                foreach ($item in $_.childNodes) {
                    if ($item.className -like "*project-body-info-title*") {
                        $key = $item.textContent
                    } else {
                        [PSCustomObject]@{
                            Key   = $key
                            Value = $item.textContent.Trim()
                        }
                    }
                }
            }
        $_.Contact = ($project_body_infos | Where-Object { $_.Key -eq "Ansprechpartner" }).Value
        $_.ProjectId = ($project_body_infos | Where-Object { $_.Key -eq "Projekt-ID" }).Value
        $_
    } |
    Where-Object {
        # Exclude known projects
        if ($_.ProjectId -in $known_projects) {
            return $false
        }
        return $true
    }

Write-Host
$projects = $projects |
    ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $tags = $_.Tags | Where-Object { $_ -in $using:Exclude }
        if ($tags.Count -gt 0) {
            # Exclude by tags
            Write-Host -ForegroundColor Red "Excluded project '$($_.Title)' due to tags: $($tags -join ", ")"
            $_.Score = 0
            $_.ScoreDescription = "Excluded due to tags: $($tags -join ", ")"
        } else {
            # Get CV score
            $response = . "$using:PSScriptRoot\Get-ProjectCvScore.ps1" -ProjectDescription $_.Description -Silent
            Write-Host "Evaluated project '$($_.Title)' with score $($response.Score) %"
            $_.Score = $response.Score
            $_.ScoreDescription = $response.Description
        }

        $_
    }

# output to console with formatting and sorting
Write-Host "New projects found: $($projects.Count)"
$projects |
    ForEach-Object {
        $_.PSObject.TypeNames.Insert(0, $typeName)
        $_
    } |
    Sort-Object Age

if ($projects.Count -gt 0 -and !$NoExport) {
    # output to Excel
    $excel = $projects |
        ForEach-Object {
            [PSCustomObject]@{
                ID         = $(
                    $link = [OfficeOpenXml.ExcelHyperLink]::new($_.Link)
                    $link.Display = $_.ProjectId
                    $link
                )
                Title      = $_.Title
                Tags       = ($_.Tags -join ", ")
                CreatedBy  = $_.CreatedBy
                Contact    = $_.Contact
                CreatedOn  = $_.Date
                Description= $_.Description
                Score      = $_.Score
                ScoreDescription = $_.ScoreDescription
                Comments   = "new"
            }
        } |
        Export-Excel `
            -Path $filename `
            -WorksheetName $worksheetName `
            -Append `
            -PassThru

    $worksheet = $excel.Workbook.Worksheets[$worksheetName]
    $calculatedColumns = $worksheet.Cells["2:2"] | Where-Object { $_.Formula.Length -gt 0 } | ForEach-Object { $_.Start.Column }
    $worksheet.Cells["A:A"] |
        ForEach-Object {
            if ($_.Start.Row -gt 2) {
                foreach ($col in $calculatedColumns) {
                    $columnLetter = [OfficeOpenXml.ExcelCellAddress]::GetColumnLetter($col)
                    $cell         = $worksheet.Cells["${columnLetter}$($_.Start.Row)"]
                    $template     = $worksheet.Cells["${columnLetter}2"]

                    $template.Copy($cell)
                    $cell.Formula = $template.Formula
                }
            }
        }
    Close-ExcelPackage $excel
    Remove-Module ImportExcel

    Invoke-Item $filename
}