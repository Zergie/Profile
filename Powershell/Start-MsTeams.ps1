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
    Start-Process "$env:LOCALAPPDATA\Microsoft\WindowsApps\ms-teams.exe" -WindowStyle Minimized
}
