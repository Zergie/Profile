[cmdletbinding()]
param(
    [Parameter(Mandatory, Position=0, ValueFromPipeline)]
    [string]
    $Path,

    [Parameter()]
    [string]
    $OutFile
)
begin {
}
process {
    $file = Get-Item $Path
    if ($OutFile.Length -eq 0) { $OutFile = "$env:TEMP\output.bin" }

    $(
        $stream = [System.IO.File]::OpenRead($file.FullName)
        $buffer = New-Object byte[] 1

        while ($stream.Position -lt $stream.Length) {
            $data = 0..15 |
                ForEach-Object {
                    $stream.Read($buffer, 0, $buffer.Length) | Out-Null
                    $buffer |
                        ForEach-Object {
                            [pscustomobject]@{
                                hex  = $_.ToString("x").PadLeft(2, "0")
                                text = if ([char]::IsControl($_)) {"."} else {[char]$_}
                            }
                        }
                }

            @(
                $data.hex
                "  "
                $data.text
            ) |
                Join-String -Separator " "
        }

        $stream.Close()
    ) |
        Join-String -Separator "`n" |
        Set-Content $OutFile
    
    if ($OutFile -eq "$env:TEMP\output.bin" ) {
        Get-Content $OutFile
    }
}
end {
}
