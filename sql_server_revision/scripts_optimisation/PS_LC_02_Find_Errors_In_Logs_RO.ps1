<#
NOM: PS_LC_02_Find_Errors_In_Logs_RO.ps1 | CAT: 13-LOGS | P0
TYPE: READ ONLY | PERMS: Lecture fichier
OBJET: Extraire rapidement toutes les lignes ERROR/WARNING dans un log
       Version rapide — ne faire que la detection d'erreurs
PARAM: $DossierLogs (cherche dans tous les .log/.txt), $Motif
#>
param(
    [string]$DossierLogs = "C:\Logs",     # <- Adapter
    [string]$Motif       = "ERROR|ERREUR|EXCEPTION|FAILED|SqlException|ORA-",
    [int]$HeuresRetroactif = 24
)
$limite = (Get-Date).AddHours(-$HeuresRetroactif)
$total = 0

Get-ChildItem -Path $DossierLogs -Include "*.log","*.txt" -Recurse -ErrorAction SilentlyContinue |
Where-Object { $_.LastWriteTime -ge $limite } |
ForEach-Object {
    $fichier = $_
    $matches = Select-String -Path $fichier.FullName -Pattern $Motif -ErrorAction SilentlyContinue
    if ($matches) {
        Write-Host "`nFICHIER: $($fichier.Name) ($($matches.Count) erreurs)" -ForegroundColor Red
        $matches | Select-Object -First 20 | ForEach-Object {
            Write-Host ("  L{0,5}: {1}" -f $_.LineNumber, $_.Line.Trim()) -ForegroundColor Yellow
            $total++
        }
        if ($matches.Count -gt 20) { Write-Host "  ... + $($matches.Count - 20) erreurs (voir fichier directement)" }
    }
}
Write-Host "`nTotal erreurs trouvees dans les logs des $HeuresRetroactif dernieres heures : $total" -ForegroundColor $(if ($total -gt 0) {"Red"} else {"Green"})
