<#
NOM     : PS_DI_01_Get_Server_Resources_Snapshot_RO.ps1
CAT     : 01 - DIAGNOSTIC INITIAL | PRIORITE : P0
TYPE    : READ ONLY | RISQUE : FAIBLE
PERMS   : Lecture locale Windows (RDP sur le serveur)
OBJET   : Snapshot instantané CPU / RAM / Disques / Process SQL Server
          Exécuter en parallèle des scripts SQL lors d'un incident
          pour déterminer si le problème vient de SQL Server ou de l'OS
#>
param([string]$InstanceSQL = ".")
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PS_DI_01 — SNAPSHOT RESSOURCES WINDOWS — $ts" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

Write-Host "`n[CPU]" -ForegroundColor Yellow
$cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
$c = if ($cpu -gt 90) {"Red"} elseif ($cpu -gt 70) {"Yellow"} else {"Green"}
Write-Host "  CPU global : $cpu%" -ForegroundColor $c

Write-Host "`n[MEMOIRE]" -ForegroundColor Yellow
$os = Get-CimInstance Win32_OperatingSystem
$ramTotal = [Math]::Round($os.TotalVisibleMemorySize / 1024)
$ramLibre = [Math]::Round($os.FreePhysicalMemory / 1024)
$ramUtil = $ramTotal - $ramLibre
$pctRam = [Math]::Round($ramUtil * 100 / $ramTotal)
$c = if ($pctRam -gt 90) {"Red"} elseif ($pctRam -gt 75) {"Yellow"} else {"Green"}
Write-Host "  Total: $ramTotal Mo | Utilisee: $ramUtil Mo ($pctRam%) | Libre: $ramLibre Mo" -ForegroundColor $c

Write-Host "`n[DISQUES]" -ForegroundColor Yellow
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $total = [Math]::Round($_.Size / 1GB, 1)
    $libre = [Math]::Round($_.FreeSpace / 1GB, 1)
    $pct = if ($total -gt 0) { [Math]::Round(($total - $libre) * 100 / $total) } else { 0 }
    $c = if ($pct -gt 90) {"Red"} elseif ($pct -gt 75) {"Yellow"} else {"Green"}
    Write-Host ("  {0,-5} Total:{1,6}Go Libre:{2,6}Go Utilise:{3,3}%" -f $_.DeviceID, $total, $libre, $pct) -ForegroundColor $c
}

Write-Host "`n[PROCESSUS SQL SERVER]" -ForegroundColor Yellow
$sql = Get-Process -Name "sqlservr" -ErrorAction SilentlyContinue
if ($sql) {
    $sql | ForEach-Object {
        Write-Host ("  PID:{0} RAM:{1}Mo CPU:{2}s Threads:{3}" -f $_.Id, [Math]::Round($_.WorkingSet64/1MB), [Math]::Round($_.CPU,1), $_.Threads.Count) -ForegroundColor White
    }
} else { Write-Host "  Processus sqlservr non trouve" -ForegroundColor Red }

Write-Host "`n[TOP 5 PAR RAM]" -ForegroundColor Yellow
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 |
    ForEach-Object { Write-Host ("  {0,-25} {1,6}Mo" -f $_.ProcessName, [Math]::Round($_.WorkingSet64/1MB)) }

Write-Host "`n================================================================" -ForegroundColor Cyan
