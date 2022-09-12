
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Allgemein","Asd","Asylberatung","Betreuen","Betreuen2","Bh","BW","Daten","Heim","Kurhilfe","Obdachlosenhilfe","Prüfer","schulden","Stationaer","Sucht","Verwaltung","Vis","Wohnungslosenhilfe","KinderJugend", "UNA")]
        [String]
        $License
    )

    $date = [int]([DateTime]::Now.AddDays(90) - [DateTime]::new(2001, 7, 17)).TotalDays

    $range = switch ($License)
    {
        "Allgemein"            { @(1900, 1999) }
        "Asd"                  { @(3500, 3999) }
        "Asylberatung"         { @(2500, 2999) }
        "Betreuen"             { @(4000, 4499) }
        "BeglaubigungsManager" { @(5500, 5999) }
        "Bh"                   { @(7000, 7999) }
        "BW"                   { @(3100, 3499) }
        "Daten"                { @(4500, 4999) }
        "Heim"                 { @(6500, 6999) }
        "Kurhilfe"             { @(5000, 5499) }
        "Obdachlosenhilfe"     { @(1500, 1899) }
        "Prüfer"               { @(3000, 3099) }
        "schulden"             { @(9000, 9999) }
        "Straffälligenhilfe"   { @(6000, 6499) }
        "Sucht"                { @(8000, 8999) }
        "Verwaltung"           { @( 500,  999) }
        "Vis"                  { @(   1,  499) }
        "Wohnungslosenhilfe"   { @(2000, 2499) }
        "KinderJugend"         { @(1000, 1499) }
        "UNA"                  { @(   1, 9999) }
    }

    $fb = Get-Random -Minimum $range[0] -Maximum $range[1]
    while ($fb % 3 -ne 0) { $fb = Get-Random -Minimum $range[0] -Maximum $range[1] }

    $postalCode = switch ($License)
    {
        "UNA"   { 11 }
        default { 83 }
    }

    $checksum = ($date + $fb + $postalCode) * 49

    $LicenseString = "{0:0000}-{1:0000}-{2:00}{3:00-0000}" -f $date, $fb, $postalCode, $checksum
    $LicenseString | Set-Clipboard

    Write-Host "License copied to clipboard!"

