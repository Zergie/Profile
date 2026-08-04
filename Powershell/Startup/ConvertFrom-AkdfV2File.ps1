#Requires -PSEdition Core

[CmdletBinding()]
param (
    [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [string]
    $InputObject
)

begin {
    $definitions = @{
        VORSATZ = @(
            'MerkmalVerwaltungssatz:1', 'MerkmalPlausi:1', 'Verfahrenskuerzel:3', 'Programm:8',
            'Reserviert_5:8', 'Verarbeitungsdatum:10', 'Bemerkungen:30', 'Gemeindekennzeichen:4',
            'Kassenzeichen:4', 'Reserviert_10:375'
        )
        PKA = @(
            'Gemeindekennzeichen:4', 'Haushaltskennzeichen:4', 'KassenzeichenPersKto:12', 'Abgabeart:4',
            'Status:2', 'Anredeschluessel:4', 'Name:30', 'Vorname:30', 'Namenszusatz:30',
            'AkademischerGrad:30', 'Adelspraedikat:30', 'StrassenGemeindeKennzahlAnwender:4',
            'StrassenNummer:9', 'StrassenName:30', 'HausnummerVon:4', 'HausnummerVonErgaenzung:2',
            'HausnummerVonBisKennzeichen:1', 'HausnummerBis:4', 'HausnummerBisErgaenzung:2',
            'Landeskennzeichen:3', 'Postleitzahl:7', 'Ort:30', 'Ortsteil:30', 'Adresszusatz:30',
            'Postfach:8', 'Telefon:20', 'Telefax:20', 'Bankleitzahl:9', 'Kontonummer:12',
            'Abbuchermerkmal:1', 'Erstattungsmerkmal:1', 'MerkmalVerarbeitungsart:1',
            'Haushaltsjahr:4', 'Reserviert_34:32', 'MerkmalAdressbuchung:1'
        )
        PKS = @(
            'Gemeindekennzeichen:4', 'Haushaltskennzeichen:4', 'KassenzeichenPersKto:12', 'Abgabeart:4',
            'Buchungsart:1', 'Haushaltjahr:4', 'Einzelart:4', 'BuchungsschluesselSoll:2',
            'UrsprungsjahrKassenrest:4', 'BuchungsschluesselIst:1', 'Zahlweg:4', 'Zahlart:1',
            'GesamtbetragCent:13', 'Reserviert_15:1', 'Faelligkeitsdatum:10', 'Bemerkung:90',
            'RatenbetragCent:13', 'Reserviert_20:1', 'Ratenschluessel:4',
            'FaelligkeitErsteRate:10', 'FaelligkeitRestRate:10', 'RestRatenbetragCent:13',
            'Reserviert_26:1', 'Bescheiddatum:10', 'Bescheidnummer:1', 'Veranlagungsjahr:4',
            'Veranlagungsobjekt:20', 'WirksamkeitsdatumSollabgang:10', 'GebuehrenbetragCent:13',
            'Reserviert_34:1', 'Wertstellungsdatum:10', 'MerkmalSollListen:1',
            'MerkmalMahnverfahren:1', 'MerkmalVariable:1', 'Reserviert_39:161',
            'MerkmalPersonenkontenbuchung:1'
        )
    }
}

process {
    foreach ($line in $InputObject -split '\r?\n') {
        if ([string]::IsNullOrEmpty($line)) {
            continue
        }

        $recordType = if ($line.StartsWith('GJ')) {
            'VORSATZ'
        } elseif ($line[-1] -eq 'A') {
            'PKA'
        } elseif ($line[-1] -eq 'P') {
            'PKS'
        } else {
            throw 'Unknown AKDF record type.'
        }

        $expectedLength = if ($recordType -eq 'VORSATZ') { 444 } else { 445 }
        if ($line.Length -ne $expectedLength) {
            throw "Invalid $recordType record length ($($line.Length)); expected $expectedLength."
        }

        $record = [ordered]@{
            RecordType = $recordType
        }
        $offset = 0

        foreach ($definition in $definitions[$recordType]) {
            $name, $length = $definition -split ':', 2
            $record[$name] = $line.Substring($offset, [int]$length).Trim()
            $offset += [int]$length
        }

        [pscustomobject]$record
    }
}
