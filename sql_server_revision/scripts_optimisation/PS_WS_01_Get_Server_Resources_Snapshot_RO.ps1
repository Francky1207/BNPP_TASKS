<#
NOM: PS_WS_01_Get_Server_Resources_Snapshot_RO.ps1 | CAT: 12-WINDOWS | P0
TYPE: READ ONLY | PERMS: Lecture locale Windows (RDP sur le serveur)
OBJET: Snapshot complet ressources Windows — CPU, RAM, Disques, Reseau, SQL
       Version plus complete que PS_DI_01 — a utiliser pour analyse approfondie
PARAM: $Iterations (repetitions), $IntervalleSecondes
#>
param([int]$Iterations = 1, [int]$IntervalleSecondes = 5)

for ($i = 1; $i -le $Iterations; $i++) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($Iterations -gt 1) { Write-Host "`n=== Iteration $i/$Iterations — $ts ===" -ForegroundColor Cyan }

    # CPU global
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $os  = Get-CimInstance Win32_OperatingSystem
    $ramTot = [Math]::Round($os.TotalVisibleMemorySize/1MB, 1)
    $ramLib = [Math]::Round($os.FreePhysicalMemory/1MB, 1)
    $ramPct = [Math]::Round(($ramTot-$ramLib)*100/$ramTot)

    Write-Host ("CPU:{0,3}%  RAM:{1,5}Go/{2,5}Go({3}%)  Heure:{4}" -f $cpu, ($ramTot-$ramLib), $ramTot, $ramPct, $ts) -ForegroundColor $(if ($cpu -gt 90 -or $ramPct -gt 90) {"Red"} elseif ($cpu -gt 70 -or $ramPct -gt 75) {"Yellow"} else {"Green"})

    # Disques
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $t = [Math]::Round($_.Size/1GB,1); $l = [Math]::Round($_.FreeSpace/1GB,1)
        $p = if ($t -gt 0) {[Math]::Round(($t-$l)*100/$t)} else {0}
        $c = if ($p -gt 90) {"Red"} elseif ($p -gt 80) {"Yellow"} else {"Green"}
        Write-Host ("  Disque {0}: {1}Go libre sur {2}Go ({3}% plein)" -f $_.DeviceID,$l,$t,$p) -ForegroundColor $c
    }

    # Process SQL Server
    $sql = Get-Process -Name "sqlservr" -ErrorAction SilentlyContinue
    if ($sql) {
        $sqlRam = [Math]::Round(($sql | Measure-Object WorkingSet64 -Sum).Sum/1MB)
        Write-Host ("  sqlservr: {0}Mo RAM | {1}s CPU cumule" -f $sqlRam, [Math]::Round(($sql|Measure-Object CPU -Sum).Sum,0)) -ForegroundColor White
    }

    if ($i -lt $Iterations) { Start-Sleep -Seconds $IntervalleSecondes }
}
