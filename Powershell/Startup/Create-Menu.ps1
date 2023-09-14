[cmdletbinding()]
param (
    [Parameter(Mandatory = $true,
               Position = 0,
               ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $false)]
    [ValidateNotNullOrEmpty()]
    [array]
    $Items,

    [Parameter(Mandatory = $false,
               ValueFromPipeline = $false,
               ValueFromPipelineByPropertyName = $false)]
    [string]
    $Title,

    [Parameter(Mandatory = $false,
               ValueFromPipeline = $false,
               ValueFromPipelineByPropertyName = $false)]
    [ValidateSet("Index", "Object")]
    [string]
    $ReturnValue = "Index"
)
begin {
    $ErrorActionPreference = 'Stop'
    $ItemsArray = @()

    function Write-Item {
        param($Item, $Selected)

        if ($Selected) {
            $fcolor = $host.UI.RawUI.ForegroundColor
            $bcolor = $host.UI.RawUI.BackgroundColor
        } else {
            $fcolor = $host.UI.RawUI.BackgroundColor
            $bcolor = $host.UI.RawUI.ForegroundColor
        }

        Write-Host " " -NoNewline
        Write-Host " $Item" `
            -ForegroundColor $fcolor `
            -BackgroundColor $bcolor `
            -NoNewLine
    }
}
process {
    $ItemsArray += $Items
}
end {
    $initialCursor = $host.UI.RawUI.CursorPosition

    # Initial Drawing
    if ($Title.Length -gt 0) {
        $paddedMenu = " $Title "
        Write-Host
        Write-Host " $paddedMenu"
        Write-Host " $("-" * $paddedMenu.Length)"
    }
    for ($i = 0; $i -le $ItemsArray.length;$i++) {
        if ($i -eq 0) {
            Write-Item $ItemsArray[$i] $false
            Write-Host
        } elseif ($($ItemsArray[$i])) {
            Write-Item $ItemsArray[$i] $true
            Write-Host
        }
    }

    $cursor  = $host.UI.RawUI.CursorPosition
    $keycode = 0
    $pos     = 0
    $oldPos  = 0

    While ($keycode -ne 13) {
        switch ($keycode)
        {
            38 { $pos-- }
            40 { $pos++ }
        }
        if ($pos -lt 0) {
            $pos = 0
        } elseif ($pos -ge $ItemsArray.Length) {
            $pos = $ItemsArray.Length -1
        }

        # Redraw Menu
        if ($oldPos -ne $pos -or $keycode -eq 0) {
            $host.UI.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0
                , ($cursor.Y - ($ItemsArray.Count - $oldPos)))
            Write-Item $ItemsArray[$oldPos] $true

            $host.UI.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0
                , ($cursor.Y - ($ItemsArray.Count - $pos)))
            Write-Item $ItemsArray[$pos] $false
        }

        $press   = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $keycode = $press.Virtualkeycode
        $oldPos  = $pos;
    }

    $host.UI.RawUI.CursorPosition = $cursor

    switch ($ReturnValue)
    {
        "Index"  { Write-Output $pos }
        "Object" { Write-Output $ItemsArray[$pos] }
    }
}
