param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Path
)

function Update-Content {
    param (
        [string] $Sequence,
        [string] $Replacement
    )
    $SequenceBytes = [System.Text.Encoding]::ASCII.GetBytes($Sequence)
    $SequenceLength = $SequenceBytes.Length
    $Index = -1

    for ($i = 0; $i -le $Content.Length - $SequenceLength; $i++) {
        if ($Content[$i] -eq $SequenceBytes[0]) {
            $Match = $true
            for ($j = 1; $j -lt $SequenceLength; $j++) {
                if ($Content[$i + $j] -ne $SequenceBytes[$j]) {
                    $Match = $false
                    break
                }
            }
            if ($Match) {
                $Index = $i
                break
            }
        }
    }

    if ($Index -ge 0) {
        $ReplacementBytes = [System.Text.Encoding]::ASCII.GetBytes($Replacement)
        $NewContent = @()
        $NewContent += $Content[0..($Index - 1)]
        $NewContent += $ReplacementBytes
        $NewContent += $Content[($Index + $SequenceLength)..($Content.Length - 1)]
        return $NewContent
    } else {
        Write-Output "Sequence '$SequenceString' not found"
    }
}


$Path = (Resolve-Path $Path).Path
$Content = [System.IO.File]::ReadAllBytes($Path)
$Content = Update-Content -Sequence "/m#8Annlich" -Replacement "/m#E4nnlich"
$Content = Update-Content -Sequence "/eingetragene#20Lebenspartnerschaft#20begr#9Fndet#20seit" -Replacement "/eingetragene#20Lebenspartnerschaft#20begr#FCndet#20seit"
[System.IO.File]::WriteAllBytes($Path, $Content)

Invoke-Item $Path
