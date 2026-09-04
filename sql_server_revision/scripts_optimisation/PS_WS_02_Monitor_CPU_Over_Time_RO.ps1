<#
NOM: PS_WS_02_Monitor_CPU_Over_Time_RO.ps1 | CAT: 12-WINDOWS | P0
TYPE: READ ONLY | PERMS: Lecture locale
OBJET: Monitor CPU Windows toutes les N secondes pendant X minutes
       Pour capturer des pics de CPU qui n'apparaissent qu'a certains moments
PARAMS: $DureeMinutes, $IntervalleSecondes
#>
param([int]$DureeMinutes = 5, [int]$IntervalleSecondes = 10)

$fin = (Get-Date).AddMinutes($DureeMinutes)
Write-Host "Monitoring CPU — $DureeMinutes min — toutes les $IntervalleSecondes s" -ForegroundColor Cyan
Write-Host "Debut: $(Get-Date -Format 'HH:mm:ss')  Fin prevue: $($fin.ToString('HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

while ((Get-Date) -lt $fin) {
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $sql = Get-Process -Name "sqlservr" -ErrorAction SilentlyContinue
    $sqlCpu = if ($sql) { [Math]::Round(($sql|Measure-Object CPU -Sum).Sum) } else { 0 }
    $c = if ($cpu -gt 90) {"Red"} elseif ($cpu -gt 70) {"Yellow"} else {"Green"}
    $bar = ("#" * [Math]::Round($cpu/5)).PadRight(20)
    Write-Host ("{0}  [{1}] {2,3}%  sqlservr:{3}sCPU" -f (Get-Date -Format "HH:mm:ss"), $bar, $cpu, $sqlCpu) -ForegroundColor $c
    Start-Sleep -Seconds $IntervalleSecondes
}
Write-Host "Fin monitoring" -ForegroundColor Cyan
