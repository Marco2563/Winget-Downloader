[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$buildDir = $PSScriptRoot
$inputFile = Join-Path $buildDir "Winget-Downloader.ps1"
$outputFile = Join-Path $buildDir "Winget-Downloader.exe"

# Icon-Datei definieren (akzeptiert .ico oder .png)
$iconFile = Join-Path $buildDir "Winget-Downloader.ico"
if (-not (Test-Path $iconFile)) {
    $iconFile = Join-Path $buildDir "Winget-Downloader.png"
}

if (-not (Test-Path $inputFile)) {
    Write-Host "FEHLER: Winget-Downloader.ps1 wurde nicht im selben Verzeichnis gefunden!" -ForegroundColor Red
    Read-Host "Enter zum Beenden..."
    exit
}

Write-Host "Prüfe ps2exe-Modul..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installiere ps2exe Modul (einmalig)..." -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}

Import-Module ps2exe

Write-Host "Kompiliere Winget-Downloader.exe mit Icon..." -ForegroundColor Cyan

# Parameter für die Kompilierung
$ps2exeParams = @{
    InputFile    = $inputFile
    OutputFile   = $outputFile
    noConsole    = $true
    requireAdmin = $false
    title        = "Winget-Downloader V1.8"
    version      = "1.7.4.0"
    company      = "Marco Schneiderwind"
    product      = "Winget-Downloader"
    copyright    = "Marco Schneiderwind"
}

# Icon hinzufügen, falls vorhanden
if (Test-Path $iconFile) {
    Write-Host "  -> Nutze Icon: $iconFile" -ForegroundColor Green
    $ps2exeParams.Add('IconFile', $iconFile)
} else {
    Write-Host "  -> Warnung: Winget-Downloader.ico/.png nicht gefunden. Standard-Icon wird genutzt." -ForegroundColor Yellow
}

# Kompilieren ausführen
Invoke-PS2EXE @ps2exeParams

if (Test-Path $outputFile) {
    Write-Host "`nERFOLG! Die portable EXE wurde erstellt:" -ForegroundColor Green
    Write-Host "$outputFile" -ForegroundColor White
} else {
    Write-Host "`nFEHLER beim Erstellen der EXE." -ForegroundColor Red
}

Read-Host "`nEnter zum Beenden..."