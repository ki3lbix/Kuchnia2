param([string]$Url="http://localhost:5000/health")
try {
  $resp = Invoke-RestMethod -Uri $Url -TimeoutSec 5
  if ($resp.status -ne "ok"){ throw "Unhealthy" }
  Write-Host "OK"
} catch { Write-Error $_; exit 1 }
