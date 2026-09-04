<#
NOM: PS_WS_04_Check_Disk_Space_Alert_RO.ps1 | CAT: 12-WINDOWS | P0
TYPE: READ ONLY | PERMS: Lecture locale
OBJET: Alerter si un disque depasse le seuil d'utilisation
       Utilisable comme verification pre-traitement (avant un gros ETL)
PARAM: $SeuilPct (defaut 80%)
#>
param([int]$SeuilPct = 80)
$alertes = 0
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $total = $_.Size; $libre = $_.FreeSpace
    if ($total -gt 0) {
        $pct = [Math]::Round(($total-$libre)*100/$total)
        if ($pct -ge $SeuilPct) {
            $alertes++
            Write-Host ("ALERTE: {0} — {1}% plein ({2}Go libre sur {3}Go)" -f $_.DeviceID, $pct, [Math]::Round($libre/1GB,1), [Math]::Round($total/1GB,1)) -ForegroundColor Red
        } else {
            Write-Host ("OK: {0} — {1}% plein ({2}Go libre)" -f $_.DeviceID, $pct, [Math]::Round($libre/1GB,1)) -ForegroundColor Green
        }
    }
}
exit $alertes  # code retour utilisable dans un orchestrateur
