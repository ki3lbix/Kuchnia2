param(
  [Parameter(Mandatory = $true)]
  [string]$Conn,

  [Parameter(Mandatory = $true)]
  [string]$Sql
)

$ErrorActionPreference = 'Stop'

# --- Parsowanie connection stringa (case-insensitive, obsługa aliasów kluczy) ---
$map = @{}
foreach ($pair in $Conn.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
  $kv = $pair.Split('=', 2)
  if ($kv.Count -eq 2) {
    $k = $kv[0].Trim().ToLowerInvariant()
    $v = $kv[1].Trim()
    $map[$k] = $v
  }
}

# Obsługa aliasów: host/server; username/user id/user; port (opcjonalny)
$pgHost = $map['host']
if (-not $pgHost -and $map.ContainsKey('server')) { $pgHost = $map['server'] }
if (-not $pgHost) { $pgHost = 'localhost' }

$pgUser = $map['username']
if (-not $pgUser -and $map.ContainsKey('user id')) { $pgUser = $map['user id'] }
if (-not $pgUser -and $map.ContainsKey('user'))    { $pgUser = $map['user'] }

$pgPw   = $map['password']
$pgDb   = $map['database']
$pgPort = if ($map.ContainsKey('port')) { $map['port'] } else { '5432' }

# Walidacja pól krytycznych
if (-not $pgUser) { throw "Connection string missing 'Username'/'User Id'." }
if (-not $pgPw)   { throw "Connection string missing 'Password'." }
if (-not $pgDb)   { throw "Connection string missing 'Database'." }
if (-not (Test-Path -LiteralPath $Sql)) { throw "SQL file not found: $Sql" }

# Ustaw hasło dla psql
$env:PGPASSWORD = $pgPw

Write-Host "▶️ Applying: $Sql" -ForegroundColor Cyan
Write-Host "   Host=$pgHost Port=$pgPort Db=$pgDb User=$pgUser" -ForegroundColor DarkCyan

# Uruchom psql (ON_ERROR_STOP włącza fail na pierwszym błędzie)
& psql -h $pgHost -p $pgPort -U $pgUser -d $pgDb -v "ON_ERROR_STOP=1" -f $Sql

if ($LASTEXITCODE -ne 0) {
  throw "❌ psql failed for $Sql (exit $LASTEXITCODE)"
} else {
  Write-Host "✅ Applied $Sql successfully" -ForegroundColor Green
}
