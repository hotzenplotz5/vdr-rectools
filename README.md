# vdr-rectools (v1.7.3)

**vdr-rectools** ist eine leistungsstarke Media-Suite für den Video Disk Recorder (VDR). Es bietet eine automatisierte Lösung zum Reparieren, Schneiden, Konvertieren und Importieren von Aufnahmen sowie eine nahtlose Integration in das VDR-OSD und moderne Media-Server wie Plex oder Kodi.

---

## 🚀 Hauptfunktionen

* **Automatischer Import:** Überwacht Verzeichnisse und importiert externe Aufnahmen in die VDR-Struktur.
* **Reparatur-Modus:** Repariert defekte Aufnahmen (z.B. nach Stream-Fehlern) durch Re-Muxing via FFmpeg.
* **Werbung schneiden:** Wendet VDR-Schnittmarken direkt auf die Dateien an (verlustfrei).
* **H.265 Shrink:** Konvertiert Aufnahmen platzsparend nach HEVC (H.265).
* **Nacht-Modus:** Ein intelligenter Systemd-Timer führt Wartungsarbeiten nur dann aus, wenn du es in der Config erlaubst.
* **Debconf-Integration:** Einfache Konfiguration der wichtigsten Parameter während der Installation.
* **OSD-Befehle:** Alle Funktionen sind direkt über das VDR-Menü "Befehle" erreichbar (via systemd-drop-in).

---

## 🛠 Installation

Da das Projekt als natives Debian-Paket strukturiert ist, kann es einfach gebaut und installiert werden:

```bash
# Repository klonen
git clone [https://github.com/hotzenplotz5/vdr-rectools.git](https://github.com/hotzenplotz5/vdr-rectools.git)
cd vdr-rectools

# Paket bauen
debuild -us -uc

# Installieren
sudo dpkg -i ../vdr-rectools_1.7.3_all.deb
```

---

## ⚙️ Konfiguration

Die zentrale Konfiguration befindet sich unter:  
`/etc/vdr/conf.d/vdr-rectools.conf`

Die Datei wird bei der Installation automatisch erstellt oder bei Upgrades um neue Variablen ergänzt.

| Variable | Beschreibung | Standard |
| :--- | :--- | :--- |
| **AUTO_START_NIGHT** | Erlaubt den nächtlichen Automatik-Scan (1=An, 0=Aus) | `0` |
| **AUTO_TIMER** | Genereller Schalter für Timer-Aktionen | `0` |
| **IMPORT_DIR** | Pfad zu neuen Filmen für den Import | `/srv/video/Filme` |
| **MAIL_NOTIFY** | E-Mail-Adresse für Statusberichte | (leer) |
| **AUTO_SUB_DOWNLOAD** | Automatischer Download von Untertiteln | `1` |
| **SUB_LANG** | Sprache für Untertitel (z.B. de, en) | `de` |
| **MIN_FREE_GB** | Mindestfreispeicher auf der Festplatte | `20` |
| **MAX_FILES** | Maximale Anzahl zu verarbeitender Dateien pro Lauf | `10` |
| **PAUSE_WORK** | Pause zwischen Arbeitsschritten in Sekunden | `30` |
| **SNAPSHOT_TIME** | Zeitstempel für generierte Vorschaubilder | `00:05:00` |

---

## 🕹 Bedienung

### Manuelle Steuerung via Terminal
Das Tool kann jederzeit manuell gestartet werden:

* `vdr-rectools start` - Startet einen sofortigen Scan im Hintergrund.
* `vdr-rectools status` - Zeigt den aktuellen Status und die letzten Log-Einträge.
* `vdr-rectools stop` - Beendet laufende Hintergrundprozesse sauber.
* `vdr-rectools cron` - Simuliert den Timer-Aufruf (beachtet `AUTO_START_NIGHT`).

### Systemd-Timer (Automatik)
Der Timer ist standardmäßig aktiv, führt den Job aber nur aus, wenn die Konfiguration es zulässt:
```bash
sudo systemctl status vdr-rectools.timer
```

### VDR OSD-Integration
Nach der Installation finden sich im VDR-Menü unter "Befehle" bei den Aufnahmen neue Punkte:
* **Aufnahme reparieren (Rectools)**
* **Werbung schneiden (Rectools)**
* **Platz sparen H.265 (Rectools)**
* **Plex/Kodi Sync (Rectools)**

---

## 📋 Voraussetzungen
Das Paket installiert folgende Abhängigkeiten automatisch mit:
* `vdr`, `ffmpeg`, `bash (>= 4.0)`, `coreutils`, `findutils`
* `debconf`, `mediainfo`, `subliminal` (für Untertitel)
* `bsd-mailx | mailx` (für Benachrichtigungen)

---

## 📄 Lizenz & Maintainer
GPL-3.0+  
Maintainer: **Holger Schvestka** <hotzenplotz5@gmx.de>
