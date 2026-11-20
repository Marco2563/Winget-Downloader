try {
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$baseDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\')
}
$configFile = Join-Path $baseDir "apps.json"

$defaultApps = @(
    "7zip.7zip"
)

function Write-AppsJson {
    param([object[]]$Items)

    $cleanItems = @()
    foreach ($x in @($Items)) {
        $s = ([string]$x).Trim()
        if (-not [string]::IsNullOrWhiteSpace($s) -and ($cleanItems -notcontains $s)) {
            $cleanItems += $s
        }
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("[")
    for ($i = 0; $i -lt $cleanItems.Count; $i++) {
        $escaped = $cleanItems[$i].Replace('\', '\\').Replace('"', '\"')
        if ($i -lt ($cleanItems.Count - 1)) {
            [void]$sb.AppendLine("  ""$escaped"",")
        } else {
            [void]$sb.AppendLine("  ""$escaped""")
        }
    }
    [void]$sb.AppendLine("]")

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($configFile, $sb.ToString(), $utf8Bom)
    return [string[]]$cleanItems
}

function Read-AppsJson {
    if (-not (Test-Path -LiteralPath $configFile)) {
        return (Write-AppsJson -Items $defaultApps)
    }
    try {
        $raw = [System.IO.File]::ReadAllText($configFile, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return (Write-AppsJson -Items $defaultApps)
        }
        $parsed = $raw | ConvertFrom-Json
        $items = @()
        if ($null -ne $parsed) {
            if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string])) {
                foreach ($entry in $parsed) {
                    $s = ([string]$entry).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($s)) { $items += $s }
                }
            } else {
                $s = ([string]$parsed).Trim()
                if (-not [string]::IsNullOrWhiteSpace($s)) { $items += $s }
            }
        }
        if ($items.Count -eq 0) {
            return (Write-AppsJson -Items $defaultApps)
        }
        return [string[]]$items
    } catch {
        return [string[]]$defaultApps
    }
}

$script:appList = Read-AppsJson

$script:dlQueue = @()
$script:dlIndex = 0
$script:dlProc = $null
$script:dlTempDir = ""
$script:dlStop = $false
$script:dlRunning = $false

# Design
$colBgMain     = [System.Drawing.Color]::FromArgb(32, 34, 37)
$colBgSurface  = [System.Drawing.Color]::FromArgb(44, 47, 51)
$colBgInput    = [System.Drawing.Color]::FromArgb(54, 57, 63)
$colBgFooter   = [System.Drawing.Color]::FromArgb(26, 28, 31)
$colBorder     = [System.Drawing.Color]::FromArgb(72, 76, 82)
$colText       = [System.Drawing.Color]::FromArgb(230, 232, 235)
$colTextMuted  = [System.Drawing.Color]::FromArgb(160, 165, 172)
$colBtnNeutral = [System.Drawing.Color]::FromArgb(64, 68, 75)
$colBtnAccent  = [System.Drawing.Color]::FromArgb(88, 101, 242)
$colBtnSuccess = [System.Drawing.Color]::FromArgb(46, 125, 91)
$colBtnDanger  = [System.Drawing.Color]::FromArgb(158, 52, 52)

$form = New-Object System.Windows.Forms.Form
$form.Text = "Winget Offline-Downloader"
$form.Size = New-Object System.Drawing.Size(820, 560)
$form.StartPosition = "CenterScreen"
$form.BackColor = $colBgMain
$form.ForeColor = $colText
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(12, 12)
$tabs.Size = New-Object System.Drawing.Size(780, 475)
$form.Controls.Add($tabs)

$tabDownload = New-Object System.Windows.Forms.TabPage
$tabDownload.Text = "Downloader"
$tabDownload.BackColor = $colBgSurface
$tabDownload.ForeColor = $colText
$tabs.TabPages.Add($tabDownload)

$tabSettings = New-Object System.Windows.Forms.TabPage
$tabSettings.Text = "Datenbank & Winget-Suche"
$tabSettings.BackColor = $colBgSurface
$tabSettings.ForeColor = $colText
$tabs.TabPages.Add($tabSettings)

# Tab 1: Downloader
$lblActive = New-Object System.Windows.Forms.Label
$lblActive.Text = "Gespeicherte Pakete (apps.json):"
$lblActive.Location = New-Object System.Drawing.Point(12, 12)
$lblActive.Size = New-Object System.Drawing.Size(260, 20)
$lblActive.ForeColor = $colText
$lblActive.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$tabDownload.Controls.Add($lblActive)

$clbApps = New-Object System.Windows.Forms.CheckedListBox
$clbApps.Location = New-Object System.Drawing.Point(12, 36)
$clbApps.Size = New-Object System.Drawing.Size(270, 318)
$clbApps.CheckOnClick = $true
$clbApps.BorderStyle = "FixedSingle"
$clbApps.BackColor = $colBgInput
$clbApps.ForeColor = $colText
$tabDownload.Controls.Add($clbApps)

$btnToggleAll = New-Object System.Windows.Forms.Button
$btnToggleAll.Text = "Alle an-/abwählen"
$btnToggleAll.Location = New-Object System.Drawing.Point(12, 362)
$btnToggleAll.Size = New-Object System.Drawing.Size(270, 30)
$btnToggleAll.BackColor = $colBtnNeutral
$btnToggleAll.ForeColor = $colText
$btnToggleAll.FlatStyle = "Flat"
$btnToggleAll.FlatAppearance.BorderColor = $colBorder
$tabDownload.Controls.Add($btnToggleAll)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Download starten"
$btnStart.Location = New-Object System.Drawing.Point(12, 398)
$btnStart.Size = New-Object System.Drawing.Size(130, 32)
$btnStart.BackColor = $colBtnAccent
$btnStart.ForeColor = [System.Drawing.Color]::White
$btnStart.FlatStyle = "Flat"
$btnStart.FlatAppearance.BorderSize = 0
$btnStart.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$tabDownload.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop"
$btnStop.Location = New-Object System.Drawing.Point(152, 398)
$btnStop.Size = New-Object System.Drawing.Size(130, 32)
$btnStop.BackColor = $colBtnDanger
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnStop.FlatStyle = "Flat"
$btnStop.FlatAppearance.BorderSize = 0
$btnStop.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnStop.Enabled = $false
$tabDownload.Controls.Add($btnStop)

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Status & Protokoll (Ziel: $baseDir):"
$lblLog.Location = New-Object System.Drawing.Point(298, 12)
$lblLog.Size = New-Object System.Drawing.Size(460, 20)
$lblLog.ForeColor = $colText
$lblLog.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$tabDownload.Controls.Add($lblLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(298, 36)
$txtLog.Size = New-Object System.Drawing.Size(462, 355)
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.BackColor = $colBgFooter
$txtLog.ForeColor = $colText
$txtLog.BorderStyle = "FixedSingle"
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$tabDownload.Controls.Add($txtLog)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(298, 398)
$progressBar.Size = New-Object System.Drawing.Size(462, 32)
$tabDownload.Controls.Add($progressBar)

# Tab 2: Einstellungen & Suche
$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "Neues Programm über Winget suchen:"
$lblSearch.Location = New-Object System.Drawing.Point(12, 12)
$lblSearch.Size = New-Object System.Drawing.Size(300, 20)
$lblSearch.ForeColor = $colText
$lblSearch.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$tabSettings.Controls.Add($lblSearch)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(12, 36)
$txtSearch.Size = New-Object System.Drawing.Size(360, 26)
$txtSearch.BackColor = $colBgInput
$txtSearch.ForeColor = $colText
$txtSearch.BorderStyle = "FixedSingle"
$tabSettings.Controls.Add($txtSearch)

$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Text = "Suchen"
$btnSearch.Location = New-Object System.Drawing.Point(380, 35)
$btnSearch.Size = New-Object System.Drawing.Size(100, 27)
$btnSearch.BackColor = $colBtnAccent
$btnSearch.ForeColor = [System.Drawing.Color]::White
$btnSearch.FlatStyle = "Flat"
$btnSearch.FlatAppearance.BorderSize = 0
$tabSettings.Controls.Add($btnSearch)

$dgvResults = New-Object System.Windows.Forms.DataGridView
$dgvResults.Location = New-Object System.Drawing.Point(12, 72)
$dgvResults.Size = New-Object System.Drawing.Size(468, 315)
$dgvResults.AllowUserToAddRows = $false
$dgvResults.AllowUserToDeleteRows = $false
$dgvResults.ReadOnly = $true
$dgvResults.SelectionMode = "FullRowSelect"
$dgvResults.MultiSelect = $false
$dgvResults.RowHeadersVisible = $false
$dgvResults.EnableHeadersVisualStyles = $false
$dgvResults.BackgroundColor = $colBgInput
$dgvResults.GridColor = $colBorder
$dgvResults.BorderStyle = "FixedSingle"
$dgvResults.DefaultCellStyle.BackColor = $colBgInput
$dgvResults.DefaultCellStyle.ForeColor = $colText
$dgvResults.DefaultCellStyle.SelectionBackColor = $colBtnAccent
$dgvResults.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
$dgvResults.ColumnHeadersDefaultCellStyle.BackColor = $colBtnNeutral
$dgvResults.ColumnHeadersDefaultCellStyle.ForeColor = $colText
$dgvResults.ColumnHeadersDefaultCellStyle.SelectionBackColor = $colBtnNeutral
$dgvResults.ColumnHeadersDefaultCellStyle.SelectionForeColor = $colText
$dgvResults.AutoSizeColumnsMode = "Fill"
[void]$dgvResults.Columns.Add("Name", "Programmname")
[void]$dgvResults.Columns.Add("Id", "Winget-ID")
[void]$dgvResults.Columns.Add("Version", "Version")
$tabSettings.Controls.Add($dgvResults)

$btnAddSelected = New-Object System.Windows.Forms.Button
$btnAddSelected.Text = "Markiertes Paket zur Liste hinzufügen"
$btnAddSelected.Location = New-Object System.Drawing.Point(12, 396)
$btnAddSelected.Size = New-Object System.Drawing.Size(468, 34)
$btnAddSelected.BackColor = $colBtnSuccess
$btnAddSelected.ForeColor = [System.Drawing.Color]::White
$btnAddSelected.FlatStyle = "Flat"
$btnAddSelected.FlatAppearance.BorderSize = 0
$btnAddSelected.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$tabSettings.Controls.Add($btnAddSelected)

$lblManage = New-Object System.Windows.Forms.Label
$lblManage.Text = "Aktive Liste verwalten:"
$lblManage.Location = New-Object System.Drawing.Point(496, 12)
$lblManage.Size = New-Object System.Drawing.Size(260, 20)
$lblManage.ForeColor = $colText
$lblManage.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$tabSettings.Controls.Add($lblManage)

$lstManage = New-Object System.Windows.Forms.ListBox
$lstManage.Location = New-Object System.Drawing.Point(496, 36)
$lstManage.Size = New-Object System.Drawing.Size(264, 351)
$lstManage.BorderStyle = "FixedSingle"
$lstManage.BackColor = $colBgInput
$lstManage.ForeColor = $colText
$tabSettings.Controls.Add($lstManage)

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = "Ausgewähltes Paket entfernen"
$btnRemove.Location = New-Object System.Drawing.Point(496, 396)
$btnRemove.Size = New-Object System.Drawing.Size(264, 34)
$btnRemove.BackColor = $colBtnDanger
$btnRemove.ForeColor = [System.Drawing.Color]::White
$btnRemove.FlatStyle = "Flat"
$btnRemove.FlatAppearance.BorderSize = 0
$tabSettings.Controls.Add($btnRemove)

# Footer
$footerPanel = New-Object System.Windows.Forms.Panel
$footerPanel.Location = New-Object System.Drawing.Point(12, 493)
$footerPanel.Size = New-Object System.Drawing.Size(780, 24)
$footerPanel.BorderStyle = "FixedSingle"
$footerPanel.BackColor = $colBgFooter
$form.Controls.Add($footerPanel)

$lblFooter = New-Object System.Windows.Forms.Label
$lblFooter.Text = "Entwickler: Marco Schneiderwind"
$lblFooter.Location = New-Object System.Drawing.Point(6, 3)
$lblFooter.Size = New-Object System.Drawing.Size(400, 18)
$lblFooter.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblFooter.ForeColor = $colTextMuted
$footerPanel.Controls.Add($lblFooter)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 200

function Refresh-Lists {
    $clbApps.Items.Clear()
    $lstManage.Items.Clear()
    foreach ($item in @($script:appList)) {
        [void]$clbApps.Items.Add([string]$item, $true)
        [void]$lstManage.Items.Add([string]$item)
    }
}

function Write-Log {
    param([string]$Message)
    $txtLog.AppendText("$Message`r`n")
}

function Kill-WingetNow {
    if ($null -ne $script:dlProc) {
        try {
            if (-not $script:dlProc.HasExited) {
                $script:dlProc.Kill()
            }
        } catch {}
        try {
            Stop-Process -Id $script:dlProc.Id -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    try {
        Get-Process -Name "winget", "AppInstaller" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Finish-DownloadSession {
    param([bool]$StoppedByUser)

    $timer.Stop()
    Kill-WingetNow

    if (-not [string]::IsNullOrWhiteSpace($script:dlTempDir) -and (Test-Path -LiteralPath $script:dlTempDir)) {
        Remove-Item -LiteralPath $script:dlTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Get-ChildItem -LiteralPath $baseDir -Filter "*.yaml" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    Write-Log "----------------------------------------"
    if ($StoppedByUser) {
        Write-Log "Vorgang durch Stop-Button abgebrochen."
    } else {
        Write-Log "Vorgang abgeschlossen."
    }

    $script:dlRunning = $false
    $script:dlStop = $false
    $script:dlProc = $null
    $script:dlTempDir = ""
    $btnStop.Enabled = $false
    $btnStart.Enabled = $true
    $btnToggleAll.Enabled = $true
    $clbApps.Enabled = $true
}

function Start-NextAppInQueue {
    if ($script:dlStop) {
        Finish-DownloadSession -StoppedByUser $true
        return
    }

    if ($script:dlIndex -ge $script:dlQueue.Count) {
        Finish-DownloadSession -StoppedByUser $false
        return
    }

    $appId = $script:dlQueue[$script:dlIndex]
    Write-Log "Prüfe: $appId"

    $script:dlTempDir = Join-Path $baseDir ("temp_" + ($appId.Split('.')[-1]))
    if (Test-Path -LiteralPath $script:dlTempDir) {
        Remove-Item -LiteralPath $script:dlTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    try {
        $wingetArgs = @(
            "download",
            "--id", $appId,
            "--download-directory", $script:dlTempDir,
            "--accept-source-agreements",
            "--accept-package-agreements",
            "--disable-interactivity"
        )
        $script:dlProc = Start-Process -FilePath "winget.exe" -ArgumentList $wingetArgs -WindowStyle Hidden -PassThru
    } catch {
        Write-Log "  - Fehler bei $appId : $_"
        $script:dlProc = $null
        $script:dlIndex++
        $progressBar.Value = [Math]::Min($script:dlIndex, $progressBar.Maximum)
    }
}

$timer.Add_Tick({
    if (-not $script:dlRunning) {
        $timer.Stop()
        return
    }

    if ($script:dlStop) {
        Finish-DownloadSession -StoppedByUser $true
        return
    }

    if ($null -eq $script:dlProc) {
        Start-NextAppInQueue
        return
    }

    $stillRunning = $false
    try {
        $p = Get-Process -Id $script:dlProc.Id -ErrorAction SilentlyContinue
        if ($null -ne $p) {
            $stillRunning = $true
        }
    } catch {
        $stillRunning = $false
    }

    if ($stillRunning) {
        return
    }

    $appId = $script:dlQueue[$script:dlIndex]
    $script:dlProc = $null

    try {
        $downloadedFiles = Get-ChildItem -LiteralPath $script:dlTempDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in ".exe", ".msi" }

        if ($downloadedFiles) {
            foreach ($file in $downloadedFiles) {
                if ($file.Name -match "Redistributable") { continue }
                $targetFile = Join-Path $baseDir $file.Name
                $isNew = $false

                if (Test-Path -LiteralPath $targetFile) {
                    Write-Log "  - $($file.Name) ist bereits aktuell."
                } else {
                    Copy-Item -LiteralPath $file.FullName -Destination $targetFile -Force
                    Write-Log "  - Heruntergeladen: $($file.Name)"
                    $isNew = $true
                }

                if ($isNew) {
                    $idPart = $appId.Split('.')[-1]
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                    $namePrefix = ($baseName -split '[_\-\s]\d')[0].Trim()
                    if ([string]::IsNullOrWhiteSpace($namePrefix)) { $namePrefix = $idPart }

                    $oldFiles = Get-ChildItem -LiteralPath $baseDir -File -ErrorAction SilentlyContinue | Where-Object {
                        $_.Extension -in ".exe", ".msi" -and
                        $_.FullName -ne $targetFile -and
                        ($_.Name -like "*$namePrefix*" -or $_.Name -like "*$idPart*")
                    }
                    foreach ($oldFile in $oldFiles) {
                        Remove-Item -LiteralPath $oldFile.FullName -Force -ErrorAction SilentlyContinue
                        Write-Log "  - Alte Version geloescht: $($oldFile.Name)"
                    }
                }
            }
        } else {
            Write-Log "  - Nicht im Winget-Katalog verfügbar: $appId"
        }
    } catch {
        Write-Log "  - Fehler bei $appId : $_"
    }

    if (-not [string]::IsNullOrWhiteSpace($script:dlTempDir) -and (Test-Path -LiteralPath $script:dlTempDir)) {
        Remove-Item -LiteralPath $script:dlTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $script:dlIndex++
    $progressBar.Value = [Math]::Min($script:dlIndex, $progressBar.Maximum)

    if ($script:dlIndex -lt $script:dlQueue.Count) {
        Start-NextAppInQueue
    } else {
        Finish-DownloadSession -StoppedByUser $false
    }
})

function Parse-WingetSearchOutput {
    param([string]$RawText)

    $results = @()
    $lines = $RawText -split "`r?`n"
    $headerFound = $false

    foreach ($line in $lines) {
        $clean = ($line -replace '[\r\b]', '').TrimEnd()
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }

        if ($clean -match '^\s*Name\s+Id\s+Version') {
            $headerFound = $true
            continue
        }

        if (-not $headerFound) { continue }
        if ($clean -match '^\s*-+\s*$') { continue }
        if ($clean -match '^\s*[/\\|\-]\s*$') { continue }
        if ($clean -match '^\d+\s+(weitere|more)\b') { continue }

        $parts = [regex]::Split($clean.Trim(), '\s{2,}|\t+') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        if ($parts.Count -ge 2) {
            $name = $parts[0].Trim()
            $id = $parts[1].Trim()
            $ver = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "" }

            if ($ver -match '^(\S+)\s+(winget|msstore)$') {
                $ver = $matches[1]
            }

            if ($id -and $id -notmatch '^-+$' -and $id -notmatch '\s') {
                $results += [PSCustomObject]@{
                    Name    = $name
                    Id      = $id
                    Version = $ver
                }
            }
        }
    }

    return $results
}

Refresh-Lists

$btnToggleAll.Add_Click({
    $anyUnchecked = $false
    for ($i = 0; $i -lt $clbApps.Items.Count; $i++) {
        if (-not $clbApps.GetItemChecked($i)) {
            $anyUnchecked = $true
            break
        }
    }
    for ($i = 0; $i -lt $clbApps.Items.Count; $i++) {
        $clbApps.SetItemChecked($i, $anyUnchecked)
    }
})

$btnSearch.Add_Click({
    $query = $txtSearch.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($query)) { return }

    $btnSearch.Enabled = $false
    $btnSearch.Text = "Suche..."
    $dgvResults.Rows.Clear()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $rawOutput = & winget search $query --accept-source-agreements 2>&1 | Out-String
        $parsedItems = Parse-WingetSearchOutput -RawText $rawOutput

        foreach ($entry in $parsedItems) {
            [void]$dgvResults.Rows.Add($entry.Name, $entry.Id, $entry.Version)
        }

        if ($dgvResults.Rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Keine passenden Winget-Pakete für '$query' gefunden.", "Ergebnis", "OK", "Information")
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Fehler bei der Winget-Suche: $_", "Fehler", "OK", "Error")
    }

    $btnSearch.Text = "Suchen"
    $btnSearch.Enabled = $true
})

$txtSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq "Enter") {
        $e.SuppressKeyPress = $true
        $btnSearch.PerformClick()
    }
})

$btnAddSelected.Add_Click({
    if ($dgvResults.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Bitte zuerst ein Programm in der Tabelle auswählen.", "Hinweis", "OK", "Information")
        return
    }
    $selectedId = ([string]$dgvResults.SelectedRows[0].Cells["Id"].Value).Trim()
    if ([string]::IsNullOrWhiteSpace($selectedId)) { return }

    $current = @($script:appList)
    if ($current -contains $selectedId) {
        [System.Windows.Forms.MessageBox]::Show("'$selectedId' ist bereits in der Liste vorhanden.", "Info", "OK", "Information")
        return
    }

    $updated = @($current) + $selectedId
    $script:appList = Write-AppsJson -Items $updated
    Refresh-Lists
    [System.Windows.Forms.MessageBox]::Show("'$selectedId' wurde zur Liste hinzugefügt!", "Gespeichert", "OK", "Information")
})

$btnRemove.Add_Click({
    if ($lstManage.SelectedIndex -lt 0) { return }
    $toRemove = [string]$lstManage.SelectedItem
    $current = @($script:appList)
    $updated = @($current | Where-Object { ([string]$_) -ne $toRemove })
    $script:appList = Write-AppsJson -Items $updated
    Refresh-Lists
})

$btnStop.Add_Click({
    if (-not $script:dlRunning) { return }
    $script:dlStop = $true
    $btnStop.Enabled = $false
    Write-Log "Stop gedrückt..."
    Finish-DownloadSession -StoppedByUser $true
})

$btnStart.Add_Click({
    if ($script:dlRunning) { return }

    $selectedApps = @()
    for ($i = 0; $i -lt $clbApps.Items.Count; $i++) {
        if ($clbApps.GetItemChecked($i)) {
            $selectedApps += [string]$clbApps.Items[$i]
        }
    }
    if ($selectedApps.Count -eq 0) { return }

    $script:dlQueue = $selectedApps
    $script:dlIndex = 0
    $script:dlStop = $false
    $script:dlRunning = $true
    $script:dlProc = $null
    $script:dlTempDir = ""

    $btnStart.Enabled = $false
    $btnStop.Enabled = $true
    $btnToggleAll.Enabled = $false
    $clbApps.Enabled = $false
    $txtLog.Clear()
    $progressBar.Maximum = $selectedApps.Count
    $progressBar.Value = 0

    Write-Log "Starte Download in: $baseDir"
    Write-Log "----------------------------------------"

    Start-NextAppInQueue
    $timer.Start()
})

[void]$form.ShowDialog()
