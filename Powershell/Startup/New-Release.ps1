#Requires -PSEdition Core
param(
    [Parameter(Mandatory=$false,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Date = (Get-Date).ToString("yyyy-MM-dd"),

    [Parameter()]
    [switch]
    $Reset
)
DynamicParam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Name
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $true
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        "$((Get-Date).Year-1)\Q4"
        "$((Get-Date).Year)\Q1"
        "$((Get-Date).Year)\Q2"
        "$((Get-Date).Year)\Q3"
        "$((Get-Date).Year)\Q4"
        "$((Get-Date).Year+1)\Q1"
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Name", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    return $RuntimeParameterDictionary
}
begin {
    $Name = $PSBoundParameters['Name']

    $dat = [datetime]::Parse($Date)
    $Branch = "release/$($dat.Year.ToString('0000'))-$($dat.Month.ToString('00'))-$($dat.Day.ToString('00'))"
    Write-Debug "Branch: $Branch"

    $Year = [int]$Name.SubString(0,4)
    Write-Debug "Year: $Year"

    $Quartal = [int]$Name.SubString(6,1)
    Write-Debug "Quartal: $Quartal"

    $symbolicRef = "refs/heads/release/$Year/Q$Quartal"
    Write-Debug "symbolic-ref: $symbolicRef"

    $MasterYear = if ($Quartal -eq 4) { $Year + 1 } else { $Year }
    Write-Debug "Master Year: $MasterYear"

    $MasterQuartal = if ($Quartal -eq 4) { 1 } else { $Quartal + 1 }
    Write-Debug "Master Quartal: $MasterQuartal"
}
process {
    if ($Reset) {
        $commands = @(
            "git checkout master"
            "git push -d origin $Branch"
            "git branch -D $Branch"
            "git reset --hard origin/master"
        )

        Write-Host
        Write-Host "You are about to execute following commands:"
        $commands | ForEach-Object { Write-Host "`t$_" }
        Write-Host
        Read-Host "Press ENTER to continue, ctrl-c to cancel."
        $commands |
            ForEach-Object {
                Write-Host -ForegroundColor Cyan $_
                Invoke-Expression $_
            }
    } else {
        if ((Get-GitStatus).Branch -ne "master") {
            Write-Host -ForegroundColor Cyan "git checkout master"
            git checkout master
        }

        Write-Host -ForegroundColor Yellow "Adding dbms patches"
        $highest = Get-ChildItem struktur\ |
            Where-Object Name -Match "^(main|department)_" |
            ForEach-Object Name |
            Select-String "^(?<database>[a-z]+)_(?<Year>\d{4})(?<Revision>\w)(?<Number>\d{3})" |
            ForEach-Object Matches |
            ForEach-Object {
                [pscustomobject]@{
                    Database = $_.Groups['database'].Value
                    Year     = $_.Groups['Year'].Value
                    Revision = $_.Groups['Revision'].Value
                    Number   = $_.Groups['Number'].Value
                }
            } |
            Where-Object Year -eq $MasterYear |
            Sort-Object Year, Revision |
            Select-Object -Last 1

        "main","department" |
            ForEach-Object {
                $revision = if ($null -eq $highest) { 'a' } else { [char](([int]($highest.Revision.ToCharArray()[-1]))+1) }
                $path = "struktur\${_}_${MasterYear}${Revision}000.xml"

                @(
                    "<?xml version='1.0' encoding='utf-8'?>"
                    "<?xml-model href='../dbms/schema/schema-patch.xsd'?>"
                    "<schema-patch version='1.2' xmlns='http://schema.rocom-sevice.de/dbms-patch/1.0'>"
                    "</schema-patch>"
                ) | Set-Content -Path $path -Encoding utf8

                Write-Host -ForegroundColor Cyan "git add $path"
                git add $path
            }

        Write-Host -ForegroundColor Yellow "Updating copyright year"
        Get-ChildItem -Recurse -Include "AssemblyInfo.cs" -PipelineVariable path |
        ForEach-Object {
            $path |
                Get-Content -Encoding utf8 |
                ForEach-Object {
                    if ($_ -match 'AssemblyCopyright\("') {
                        $new_line = $_ -replace 'AssemblyCopyright\("([^"]+)"\)'`
                            , "AssemblyCopyright(`"Copyright © rocom GmbH ${MasterYear}`")"
                        $new_line.TrimEnd()
                    } else {
                        $_.TrimEnd()
                    }
                } |
                Out-String |
                ForEach-Object { $_.TrimEnd() } |
                Set-Content -Path $path -Encoding utf8

            Write-Host -ForegroundColor Cyan "git add $path"
            git add $path
        }


        Write-Host -ForegroundColor Cyan "git commit"
        git commit -m "added new dbms patch versions, updated copyright"

        if ((Get-GitStatus).Branch -ne $Branch) {
            Write-Host -ForegroundColor Cyan "git checkout -B $Branch origin/master"
            git checkout -b $Branch origin/master
            git push --set-upstream origin $Branch
        }

        Write-Host -ForegroundColor Yellow "Patching *.yml"
        Get-ChildItem -Recurse -Filter *.yml |
            ForEach-Object {
                $path = $_.FullName

                Get-Content $path -Encoding utf8 |
                    ForEach-Object {
                        $line=$_
                        if ($line -match "#.* or .*") {
                            if ($PSBoundParameters['Debug'].IsPresent) { Write-Host $line -ForegroundColor Red }

                            $m = $line |
                                    Select-String -Pattern "#(.*) or (.*)" |
                                    Select-Object -First 1 |
                                    ForEach-Object { $_.Matches.Groups[1];$_.Matches.Groups[2] }

                            $value_master = $m[0].Value.Trim()
                            $value_release = $m[1].Value.Trim()

                            $replacement = switch ($value_release) {
                                "SetupXXXX_Qx"       { "Setup${Year}_Q${Quartal}" }
                                "release/xxxx-xx-xx" { $Branch }
                                default              { $value_release }
                            }

                            $new_line = $line -replace "(?<!#\s*)${value_master}","${replacement}"
                            if ($PSBoundParameters['Debug'].IsPresent) { Write-Host $new_line -ForegroundColor Green }

                            $new_line
                        } else {
                            $line
                        }
                    } |
                    Out-String |
                    ForEach-Object { $_.TrimEnd() } |
                    Set-Content $path -Encoding utf8

                Write-Host -ForegroundColor Cyan "git add $path"
                git add $path
            }

        Write-Host -ForegroundColor Cyan "git commit"
        git commit -m "Release $Name"

        Write-Host -ForegroundColor Cyan "git symbolic-ref"
        git symbolic-ref $symbolicRef refs/heads/$Branch

        Write-Host -ForegroundColor Cyan "ssh mkdir CD/Tau-Office/Setup${Year}_Q${Quartal}"
        ssh u266601-sub2@u266601-sub2.your-storagebox.de -p 23 mkdir CD/Tau-Office/Setup${Year}_Q${Quartal}

        Write-Host -ForegroundColor Cyan "git slog --name-only -1 master"
        git slog --name-only -1 master

        Write-Host -ForegroundColor Cyan "git slog --name-only -1 $Branch"
        git slog --name-only -1 $Branch

        Write-Host
        Write-Host  "==========================================================================="
        Write-Host  " Please review changes in `e[36m$Branch`e[0m and push them to origin."
        Write-Host  " Please also review changes in `e[36mmaster`e[0m and push them to origin."
        Write-Host  "==========================================================================="
        Write-Host
    }
}
end {}
