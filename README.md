# 🎬 vdr-rectools

**vdr-rectools** (ehemals *vdr-reccleaner*) ist eine modulare, vollautomatisierte Bash-Suite für den Video Disk Recorder (VDR). Sie dient zur Verwaltung, Reparatur, Konvertierung und nahtlosen Integration von VDR-Aufnahmen in Media-Center wie Plex oder Kodi.

---

## ✨ Features

* **📥 Smart Import (MKV/MP4/TS):** Importiert externe Videodateien schonend durch reines Remuxing (`-c copy`) in das VDR-eigene `.ts`-Format.
* **📝 Intelligente Metadaten:** Liest beim Import `.nfo`-Dateien (Titel, Plot) ein und schreibt sie direkt in die `info`-Datei des VDR für eine perfekte Darstellung.
* **🎬 TVScraper Integration:** Triggert nach dem Import optional einen Metadaten-Scrape im VDR (Modi: `immediate` oder `batch`).
* **🛠️ Smart Repair:** Repariert defekte Aufnahmen in einem zweistufigen Verfahren: Zuerst ein schneller Header-Fix, bei Bedarf gefolgt von einem kompletten Re-Encoding.
* **💬 Auto-Subtitles:** Sucht beim Import automatisch nach passenden Untertiteln und legt sie als `.srt` direkt zur Aufnahme.
* **🗜️ H.265 Shrink-Modus:** Komprimiert große Aufnahmen auf Knopfdruck in den platzsparenden HEVC-Codec (H.265).
* **📺 VDR OSD-Integration:** Klinkt sich automatisch in das `reccmds.conf` Befehlsmenü des VDR ein.
* **✉️ Intelligentes Reporting:** Sendet Erfolgs- oder Fehlermeldungen per E-Mail.
* **🧹 Auto-Cleanup:** Findet und löscht leere Aufnahmeordner im Video-Verzeichnis.

---

## � Der Import-Workflow im Detail

Der Import ist das Herzstück von `vdr-rectools`. Wenn eine Videodatei im `IMPORT_DIR` gefunden wird, passiert Folgendes im Hintergrund:

1.  **Metadaten finden:** Das Skript sucht nach einer passenden `.nfo`-Datei (z.B. `Mein Film.nfo`). Werden darin `<title>` und `<plot>` gefunden, werden diese für die VDR-Aufnahme übernommen. Andernfalls wird der Dateiname als Titel verwendet.
2.  **Struktur anlegen:** Es wird ein VDR-konformer Aufnahmeordner erstellt (z.B. `/srv/vdr/video/Mein_Film/2026-04-22.10.00.1-0.rec/`).
3.  **Schonendes Remuxing:** Die Quelldatei (`.mkv`, `.mp4` etc.) wird ohne Qualitätsverlust in eine VDR-kompatible `.ts`-Datei umgewandelt (`-c copy`).
4.  **Reparatur & Index:** Die neue `.ts`-Datei wird durch `smart_repair` geschickt, um Timestamps zu korrigieren. Anschließend wird der VDR-Index (`index`) neu generiert.
5.  **Metadaten schreiben:** Die `info`-Datei wird mit Titel und Beschreibung aus Schritt 1 befüllt.
6.  **Untertitel & TVScraper:** Das Skript sucht nach Untertiteln und triggert (falls konfiguriert) das TVScraper-Plugin.
7.  **Aufräumen:** Nach dem erfolgreichen Import wird die Originaldatei aus dem Import-Verzeichnis gelöscht.

---

## �📦 Systemvoraussetzungen

Das Skript ist für Debian/Ubuntu-basierte Systeme (wie yaVDR) optimiert. Folgende Abhängigkeiten werden bei der Installation des `.deb`-Pakets automatisch aufgelöst:

* `vdr`
* `ffmpeg`
* `bash` (>= 4.0)
* `coreutils`, `findutils`
* `subliminal` (für den Untertitel-Download)
* `bsd-mailx` oder `mailutils` (für das Reporting)

---

## 🚀 Installation

### Variante A: Installation über das fertige `.deb` Paket (Empfohlen)
Lade dir das aktuellste Release von der GitHub Releases Seite herunter und installiere es bequem via APT.

```bash
# Ersetze * durch die aktuelle Versionsnummer
sudo apt install ./vdr-rectools_*.deb
```

### Variante B: Manuelle Installation aus dem Quellcode
Diese Methode ist für Entwickler oder für manuelle Anpassungen gedacht.

```bash
# Repository klonen
git clone https://github.com/hotzenplotz5/vdr-rectools.git
cd vdr-rectools

# Paket bauen & installieren
debuild -us -uc
# Ersetze * durch die aktuelle Versionsnummer
sudo dpkg -i ../vdr-rectools_*.deb
```

---

## ⚙️ Konfiguration

Datei: `/etc/vdr/conf.d/vdr-rectools.conf`

| Variable | Beschreibung | Standard |
| :--- | :--- | :--- |
| **AUTO_START_NIGHT** | Erlaubt den nächtlichen Automatik-Scan (1=An, 0=Aus) | `0` |
| **AUTO_TIMER** | Genereller Schalter für Timer-Aktionen | `0` |
| **IMPORT_DIR** | Pfad für MKV-Filme zum Import | `/srv/video/Filme` |
| **MAIL_NOTIFY** | E-Mail-Adresse für Statusberichte | (leer) |
| **AUTO_SUB_DOWNLOAD** | Automatischer Download von Untertiteln | `1` |
| **SUB_LANG** | Sprache für Untertitel (z.B. de, en) | `de` |
| **MIN_FREE_GB** | Mindestfreispeicher auf der Festplatte | `20` |
| **MAX_FILES** | Maximale Anzahl Dateien pro Durchlauf | `10` |
| **PAUSE_WORK** | Pause zwischen Arbeitsschritten (Sekunden) | `30` |
| **PAUSE_CHECK** | Pause zwischen Datei-Checks (Sekunden) | `2` |
| **SNAPSHOT_TIME** | Zeitstempel für generierte Vorschaubilder | `00:05:00` |

---

## 🕹 Bedienung

### Terminal-Befehle
* `vdr-rectools start` - Startet einen vollständigen Scan (Import & Cleanup) im Hintergrund.
* `vdr-rectools import` - Startet gezielt nur den MKV-Import-Prozess.
* `vdr-rectools repair` - Startet einen Reparatur-Lauf für alle Aufnahmen.
* `vdr-rectools status` - Zeigt PID, Laufzeit und die letzten Log-Zeilen an.
* `vdr-rectools stop` - Beendet laufende Hintergrundprozesse sauber.
* `vdr-rectools cron` - Simuliert den Timer-Aufruf (prüft `AUTO_START_NIGHT`).
* `vdr-rectools repair_single <Pfad>` - Repariert gezielt eine einzelne Aufnahme (Pfad zum .rec Ordner).

### Systemd-Timer (Automatik)
Der Timer ist standardmäßig aktiv und triggert den Scan (meist nachts). Er führt die Arbeit aber nur aus, wenn `AUTO_START_NIGHT=1` gesetzt ist.
```bash
sudo systemctl status vdr-rectools.timer
```

---

## 📈 Monitoring & Feedback

### Logging
Alle Vorgänge werden detailliert protokolliert. Dies ist die erste Anlaufstelle bei Problemen:
* **Pfad:** `/var/log/vdr-rectools.log`
* **Inhalt:** Start/Stop-Zeiten, FFmpeg-Ausgaben beim Re-Muxing, Import-Ergebnisse.

### E-Mail-Benachrichtigungen
Bei gesetzter `MAIL_NOTIFY` Adresse versendet das Skript nach jedem Lauf eine E-Mail mit:
* Zusammenfassung der importierten Filme und reparierten Aufnahmen.
* Warnungen bei zu wenig Festplattenplatz (`MIN_FREE_GB`).
* Detaillierten Fehlermeldungen, falls ein Import oder Re-Muxing fehlgeschlagen ist.

---

## 📺 VDR OSD-Integration
Die Befehle werden automatisch in das VDR-Menü (Befehle-Taste innerhalb einer Aufnahme) eingebunden:
* **Aufnahme reparieren (Rectools):** Startet Reparatur der aktuellen Aufnahme.
* **Werbung schneiden (Rectools):** Schneidet Aufnahme basierend auf VDR-Marken.
* **Platz sparen H.265 (Rectools):** Konvertiert die Aufnahme nach HEVC.
* **Plex/Kodi Sync (Rectools):** Triggert die Synchronisation für externe Player.

---

## 📋 Voraussetzungen
Das Paket installiert Abhängigkeiten wie `vdr`, `ffmpeg`, `mediainfo`, `subliminal` und `mailx` automatisch mit.

---

## 📄 Lizenz & Maintainer
GPL-3.0+ | Maintainer: **Holger Schvestka** <hotzenplotz5@gmx.de>
