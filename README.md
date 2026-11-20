Dieses PowerShell-Skript implementiert den Winget Offline-Downloader mit einer grafischen Benutzeroberfläche (Windows Forms) im Dark Mode. Es ermöglicht das Suchen von Windows-Paketen über winget, das Verwalten einer Paketliste in einer apps.json sowie das Herunterladen von .exe- und .msi-Installern inklusive automatischem Aufräumen alter Versionen.

Überblick & Funktionsweise
Konfiguration über apps.json: Beim Start ermittelt das Skript sein eigenes Verzeichnis ($baseDir) und lädt daraus die Datei apps.json. Existiert diese nicht oder ist sie leer/ungültig, wird sie automatisch mit dem Standardpaket 7zip.7zip angelegt und als UTF-8 mit BOM gespeichert.

Asynchroner Download ohne UI-Freeze: Downloads werden über Start-Process -FilePath "winget.exe" ... -WindowStyle Hidden in ein temporäres Unterverzeichnis (temp_<Paketname>) gestartet. Ein System.Windows.Forms.Timer prüft alle 200 ms, ob der Prozess noch läuft, damit die Oberfläche bedienbar bleibt und per Stop-Button abgebrochen werden kann.

Datei-Abgleich & Bereinigung: Nach Abschluss eines winget download-Laufs sucht das Skript im Temp-Ordner nach .exe- und .msi-Dateien (und ignoriert Redistributable-Pakete). Neue Dateien werden ins Zielverzeichnis kopiert; falls eine Datei bereits existiert, wird sie übersprungen. Bei neuen Dateien versucht das Skript anhand von Namenspräfix bzw. Paket-ID alte Versionen derselben App im Zielverzeichnis zu löschen.

Winget-Suche & Parser: Im zweiten Tab führt winget search eine Suche aus und parst die Konsolenausgabe zeilenweise (Parse-WingetSearchOutput), um Programmname, Winget-ID und Version in einem DataGridView darzustellen.

Aufbau des Skripts
Initialisierung & JSON-Verwaltung (Write-AppsJson, Read-AppsJson)

Setzt UTF-8-Encoding für die Konsole, lädt System.Windows.Forms und System.Drawing und initialisiert die Paketliste.

GUI-Definition ($form, $tabs)

Tab „Downloader“: CheckedListBox für die Auswahl der Pakete, Buttons für Alle an-/abwählen, Download starten und Stop, ein Protokollfeld ($txtLog) sowie eine Fortschrittsanzeige ($progressBar).

Tab „Datenbank & Winget-Suche“: Suchfeld + DataGridView für Suchergebnisse, Button zum Hinzufügen zur apps.json sowie eine ListBox zum Entfernen gespeicherter Pakete.

Footer: Zeigt den Entwicklernamen (Marco Schneiderwind) an.

Download-Steuerung & Abbruchlogik (Start-NextAppInQueue, $timer.Add_Tick, Finish-DownloadSession, Kill-WingetNow)

Verwaltet die Warteschlange ($script:dlQueue), löscht beim Beenden/Abbrechen temporäre Ordner sowie übrig gebliebene .yaml-Dateien im Basisverzeichnis und beendet bei Bedarf laufende winget-/AppInstaller-Prozesse.
