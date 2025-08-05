# OMC Webcam Deploy Script
# Lädt lokale Änderungen zu GitHub hoch

Write-Host "=== OMC Webcam Deploy ===" -ForegroundColor Green

# Prüfen ob es Änderungen gibt
$changes = git status --porcelain
if ([string]::IsNullOrEmpty($changes)) {
    Write-Host "Keine Änderungen zum Deployen." -ForegroundColor Yellow
    exit 0
}

Write-Host "Gefundene Änderungen:" -ForegroundColor Cyan
git status --short

# Commit-Message abfragen
$commitMessage = Read-Host "Commit-Message eingeben (oder Enter für Standard-Message)"
if ([string]::IsNullOrEmpty($commitMessage)) {
    $commitMessage = "Update OMC Webcam Scripts - $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
}

# Git-Operationen
Write-Host "`nFüge Dateien hinzu..." -ForegroundColor Blue
git add .

Write-Host "Erstelle Commit..." -ForegroundColor Blue
git commit -m "$commitMessage"

Write-Host "Pushe zu GitHub..." -ForegroundColor Blue
git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Deploy erfolgreich! Die Änderungen sind auf GitHub." -ForegroundColor Green
    Write-Host "Loggen Sie sich jetzt in Dataplicity ein und führen Sie './update.sh' aus." -ForegroundColor Yellow
} else {
    Write-Host "`n❌ Deploy fehlgeschlagen!" -ForegroundColor Red
}