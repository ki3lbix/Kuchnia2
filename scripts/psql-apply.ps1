param(
  [Parameter(Mandatory = $true)]
  [string]$Conn,

  [Parameter(Mandatory = $true)]
  [string]$Sql
)

$ErrorActionPreference = 'Stop'

# Rozbij connection string
$pw   = ($Conn -split 'Password=')[1] -split ';' | Select-Object -First 1
$host = ($Conn -split 'Host=')[1] -split ';' | Select-Object -First 1
$db   = ($Conn -split 'Database=')[1] -split ';' | Select-Object -First 1
$user = ($Conn -split 'Username=')[1] -split ';' | Select-Object -First 1

# Ustaw hasło w zmiennej środowiskowej, aby psql nie pytał
$env:PGPASSWORD = $pw

Write-Host "▶️ Applying SQL file: $Sql to database '$db' on host '$host' as user '$user'" -ForegroundColor Cyan

# Uruchom psql
& psql -h $host -U $user -d $db -v "ON_ERROR_STOP=1" -f $Sql

if ($LASTEXITCODE -ne 0) {
  throw "❌ psql failed for $Sql"
} else {
  Write-Host "✅ Applied $Sql successfully" -ForegroundColor Green
}
