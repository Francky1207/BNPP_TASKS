<#
NOM: PS_ET_02_List_CRE_Files_Recent_RO.ps1 | CAT: 10-ETL | P0
TYPE: READ ONLY | PERMS: Lecture dossier reseau
OBJET: Fichiers CRE modifies recemment dans un repertoire partage
       Verifier que les fichiers source ont ete deposes avant de lancer DATA STUDIO
PARAM: $RepCRE, $HeuresRetroactif
#>
param(
    [string]$RepCRE          = "C:\CRE",
    [int]$HeuresRetroactif   = 24,
    [string[]]$Extensions    = @("*.xlsx","*.csv","*.xls")
)
$limite = (Get-Date).AddHours(-$HeuresRetroactif)
Write-Host "Fichiers CRE modifies dans les $HeuresRetroactif dernieres heures" -ForegroundColor Cyan
Write-Host "Repertoire : $RepCRE" -ForegroundColor Cyan
Write-Host "Depuis : $($limite.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$count = 0
foreach ($ext in $Extensions) {
    Get-ChildItem -Path $RepCRE -Filter $ext -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $limite } |
    Sort-Object LastWriteTime -Descending |
    ForEach-Object {
        $count++
        $taille = [Math]::Round($_.Length/1KB, 1)
        Write-Host ("{0,-50} {1,8} Ko  {2}" -f $_.Name, $taille, $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
    }
}
Write-Host ""
Write-Host "Total : $count fichier(s) recent(s)" -ForegroundColor $(if ($count -eq 0) {"Red"} else {"Green"})
if ($count -eq 0) { Write-Host "ALERTE : Aucun fichier recent — le depot CRE n'a pas eu lieu" -ForegroundColor Red }
