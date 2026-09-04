<#
NOM: PS_FS_01_Check_Disk_Space_All_Drives_RO.ps1 | CAT: 07-FICHIERS | P0
TYPE: READ ONLY | PERMS: Lecture locale Windows (RDP)
OBJET: Espace libre sur tous les lecteurs du serveur avec seuils d'alerte
PARAM: $SeuilAlerte (% utilisation pour declencher alerte, defaut 80)
#>
param([int]$SeuilAlerte = 80)
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PS_FS_01 — ESPACE DISQUE TOUS LECTEURS — $ts" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $total = [Math]::Round($_.Size / 1GB, 2)
    $libre = [Math]::Round($_.FreeSpace / 1GB, 2)
    $util  = [Math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
    $pct   = if ($total -gt 0) { [Math]::Round($util * 100 / $total) } else { 0 }
    $bar   = ("#" * [Math]::Round($pct/5)).PadRight(20)
    $c     = if ($pct -gt 90) {"Red"} elseif ($pct -gt $SeuilAlerte) {"Yellow"} else {"Green"}
    $diag  = if ($pct -gt 90) {"CRITIQUE"} elseif ($pct -gt $SeuilAlerte) {"ALERTE"} else {"OK"}
    Write-Host ("{0,-5} [{1}] {2,3}% — Total:{3,6}Go Libre:{4,6}Go — {5}" -f $_.DeviceID, $bar, $pct, $total, $libre, $diag) -ForegroundColor $c
}
Write-Host "================================================================" -ForegroundColor Cyan
