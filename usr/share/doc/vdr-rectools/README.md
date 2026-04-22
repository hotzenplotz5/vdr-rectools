# 🎬 VDR-Rectools

**VDR-Rectools** (ehemals *vdr-reccleaner*) ist eine modulare, vollautomatisierte Bash-Suite für den Video Disk Recorder (VDR). Sie dient zur Verwaltung, Reparatur, Konvertierung und nahtlosen Integration von VDR-Aufnahmen in Media-Center wie Plex oder Kodi.

---

## ✨ Features

* **📥 Smart Import (MKV/MP4):** Importiert externe Videodateien schonend durch reines Remuxing (`-c copy`) in das VDR-eigene `.ts`-Format. Der VDR-Index wird automatisch neu generiert.
* **📝 Intelligente Metadaten:** Liest beim Import `.nfo`-Dateien (Titel, Plot) ein und schreibt sie direkt in die `info`-Datei des VDR für eine perfekte Darstellung von Anfang an.
* **📝 Plex & Kodi Integration:** Erstellt vollautomatisch saubere Symlinks (ohne die Dateien zu duplizieren) und generiert standardisierte `.nfo`-XML-Dateien für eine perfekte Erkennung in externen Media-Centern.
* **💬 Auto-Subtitles:** Sucht beim Importvorgang über OpenSubtitles/Subliminal automatisch nach passenden (deutschen) Untertiteln und legt sie als `.srt` direkt zur Aufnahme.
* **🛠️ Sichere Reparatur:** Repariert kaputte Timestamps oder defekte Header via `ffmpeg`. Inklusive Sicherheits-Checks: Die Originaldatei wird nur überschrieben, wenn die neue Datei mindestens 98 % der Ursprungsgröße besitzt und der MD5-Hash nach dem Verschieben exakt übereinstimmt.
* **🗜️ H.265 Shrink-Modus:** Komprimiert große Aufnahmen auf Knopfdruck in den platzsparenden HEVC-Codec (H.265).
* **🎬 TVScraper Integration:** Triggert nach dem Import optional einen sofortigen Metadaten-Scrape im VDR (tvscraper-Plugin).
* **📺 VDR OSD-Integration:** Klinkt sich automatisch in das `reccmds.conf` Befehlsmenü des VDR ein (inkl. Workaround für yaVDR-Ansible-Umgebungen).
* **✉️ Intelligentes Reporting:** Sendet Erfolgs- oder Fehlermeldungen per E-Mail. Kurze Logs werden direkt in die Mail geschrieben, bei über 50 Zeilen (z. B. `ffmpeg`-Dumps) wird das Log automatisch als `.txt`-Datei angehängt.
* **🧹 Auto-Cleanup:** Findet und löscht leere Aufnahmeordner im Video-Verzeichnis.

---

## 📦 Systemvoraussetzungen

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
Lade dir das aktuellste Release herunter und installiere es bequem via APT. Die Konfiguration (E-Mail, Auto-Subtitles) erfolgt interaktiv über Debconf-Dialoge während der Installation.

```bash
sudo apt install ./vdr-rectools_1.7.2_all.deb
sudo apt install ./vdr-rectools_1.7.4_all.deb
