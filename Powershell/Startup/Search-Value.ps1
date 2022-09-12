
    param (
        [Parameter(Mandatory = $true)]
        [string] 
        $Database,

        [Parameter(Mandatory=$true)]
        [string]
        $Pattern
    )

    Get-SqlTable -Database $Database |
        ForEach-Object { 
            [pscustomobject]@{
                table=$_.Name
                rows=Get-SqlTable -Database $Database -Table $_.Name
            }
        } |
        ForEach-Object {
            $parent=$_
            foreach ($item in $_.rows) {
                Get-Member -InputObject $item -Type NoteProperty |
                    ForEach-Object { 
                        [pscustomobject] @{
                            table=$parent.table
                            column=$_.Name
                            value=$item.($_.Name) 
                            row = $item
                        }
                    }
            }
        } |
        Where-Object Value -Match $Pattern

