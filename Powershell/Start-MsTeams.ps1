[cmdletbinding()]
param(
)

$date = Get-Date
$continue = $(switch ($date.DayOfWeek) {
    "Monday"    { $true }
    "Tuesday"   { $true }
    "Wednesday" { $true }
    "Thursday"  { $true }
    "Friday"    { $true }
    "Saturday"  { $false }
    "Sunday"    { $false }
})
$continue = $true

if ($continue) {
    . "C:\Program Files\WindowsApps\MSTeams_25153.1010.3727.5483_x64__8wekyb3d8bbwe\ms-teams.exe"
}
