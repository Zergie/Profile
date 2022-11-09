
    param (
        [Parameter(Mandatory=$true,
                   Position=0,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [Alias("PSPath")]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path
    )
    Get-Content $Path -Encoding 1250 |
    ForEach-Object {
        
        if ($_ -like "PASSWORT=*") {
            $_.SubString(9) |
                ForEach-Object {
                    $text = $_
                    foreach ($i in Select-String -InputObject $_ -Pattern "#\d+#" -AllMatches | ForEach-Object Matches | ForEach-Object Value) {
                        $c = [char]([int] $i.Replace('#', ''))
                        $text = $text -replace $i,$c
                    }
                    $key = [System.Convert]::FromBase64String("fvj1q7pqbhknRMSxzzR7N36o2iTUkaCQmGfzVVBumXIOOWutjGwGfHvFwycZXukmAiwi0EjMLDfFf9FNsHMaTG8=")
                    $text = [System.Text.Encoding]::GetEncoding(1250).GetBytes($text)
                    Write-Debug "bytes = $($text)"
                    $text = [System.Text.Encoding]::GetEncoding(1250).GetString(
                        $(
                            for ($i=0; $i -lt $text.Length; $i++) {
                                $new = $text[$i] -bxor ($key[$i] -bxor 255 ) -bxor ($i -band 255)
                                Write-Debug "$($text[$i]) x $($key[$i]) -> $new"
                                $new
                            }
                        )
                    ).SubString(1, $text.Length-17)
                    "PASSWORT=$text"
                }
        } else {
            $_
        }

    }

