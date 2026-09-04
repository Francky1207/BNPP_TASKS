<#
NOM: PS_WS_03_Get_Top_Processes_By_CPU_RO.ps1 | CAT: 12-WINDOWS | P0
TYPE: READ ONLY | PERMS: Lecture locale
OBJET: Top processus Windows par consommation CPU et RAM
       Identifier si le CPU est consomme par SQL Server ou un autre process
#>
param([int]$TopN = 15)
Write-Host "Top $TopN processus — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host ("{0,-30} {1,8} {2,10} {3,8}" -f "Processus","PID","RAM(Mo)","CPU(s)") -ForegroundColor Yellow
Write-Host ("-" * 60)
Get-Process | Sort-Object CPU -Descending | Select-Object -First $TopN | ForEach-Object {
    Write-Host ("{0,-30} {1,8} {2,10} {3,8}" -f $_.ProcessName, $_.Id, [Math]::Round($_.WorkingSet64/1MB), [Math]::Round($_.CPU,1))
}
