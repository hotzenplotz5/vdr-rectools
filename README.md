# 🎬 vdr-rectools

**vdr-rectools** (ehemals *vdr-reccleaner*) ist eine modulare, vollautomatisierte Bash-Suite für den Video Disk Recorder (VDR). Sie dient zur Verwaltung, Reparatur, Konvertierung und nahtlosen Integration von VDR-Aufnahmen in Media-Center wie Plex oder Kodi.

---

## ✨ Features

* **📥 Smart Import:** Erkennt und verarbeitet diverse Videoformate (z.B. MKV, MP4, AVI, MOV) und Codecs (H.264, HEVC, MiniDV, Web-Formate) automatisch und wählt die optimale Import-Strategie (Remuxing oder Re-Encoding).
* **📝 Intelligente Metadaten:** Liest beim Import `.nfo`-Dateien (Titel, Plot) ein und schreibt sie direkt in die `info`-Datei des VDR für eine perfekte Darstellung.
* **🎬 TVScraper Integration:** Triggert nach dem Import optional einen Metadaten-Scrape im VDR (Modi: `immediate` oder `batch`).
* **🛠️ Smart Repair:** Repariert defekte Aufnahmen in einem zweistufigen Verfahren: Zuerst ein schneller Header-Fix, bei Bedarf gefolgt von einem kompletten Re-Encoding.
* **💬 Auto-Subtitles:** Sucht beim Import automatisch nach passenden Untertiteln und legt sie als `.srt` direkt zur Aufnahme.
* **🔄 PES zu TS Migration:** Findet veraltete VDR-Aufnahmen im PES-Format (`.vdr`), konvertiert sie nahtlos ins moderne TS-Format, passt Metadaten an und benennt die Aufnahmeordner VDR-konform um.
* **🔖 MKV-Kapitel Support:** Konvertiert eingebettete Kapitel-Metadaten aus MKV/MP4-Dateien beim Import vollautomatisch in VDR-Schnittmarken (`marks`), wodurch perfektes Navigieren per Fernbedienung möglich wird.
* **🗜️ H.265 Shrink-Modus:** Komprimiert große Aufnahmen auf Knopfdruck in den platzsparenden HEVC-Codec (H.265).
* **🔊 Night-Mode (Audio-Normalize):** Mischt 5.1/7.1 Tonspuren (DTS/TrueHD) auf TV-kompatibles Stereo herunter und normalisiert die Lautstärke (Night-Mode) vollautomatisch beim Import/Shrink.
* **✂️ Werbeschnitt (In-Place):** Schneidet Aufnahmen vollautomatisch und verlustfrei (`-c copy`) anhand der VDR-Schnittmarken. Die Originaldatei wird direkt überschrieben, um sofort Speicherplatz freizugeben.
* **📺 VDR OSD-Integration:** Klinkt sich automatisch in das `reccmds.conf` Befehlsmenü des VDR ein (inkl. Smart Downscaling).
* **✉️ Intelligentes Reporting:** Sendet Erfolgs- oder Fehlermeldungen per E-Mail.
* **📱 Push-Benachrichtigungen:** Optionaler Versand von Statusberichten via Telegram direkt aufs Smartphone.
* **🧹 Auto-Cleanup:** Findet und löscht leere Aufnahmeordner im Video-Verzeichnis.
* **📊 Live-Dashboard:** Ein interaktives, farbiges Konsolen-Dashboard (`vdr-rectools status`) mit Fortschrittsbalken, Echtzeit-Logs und Speicherplatz-Monitoring.
* **🌐 Web-Dashboard (HTML):** Optionale, auto-refreshende Web-Oberfläche für Browser zur Live-Überwachung inkl. Datei-Explorer und **VDR-Aufnahmen-Explorer**.
* **⚡ Event-Driven Architektur:** Komplett asynchrones Job-System (via `systemd.path`) für verzögerungsfreie Web-UIs, Status-Feedback in Echtzeit und 0% CPU-Overhead im Leerlauf.
* **🖥️ PC-Delegierung (Handbrake):** Filme, die einen Re-Encode benötigen, können für die bequeme externe Bearbeitung über eine Netzwerkfreigabe (Samba) markiert werden, ohne den VDR-Import zu blockieren.

---

## 🏗️ Architektur & Job-System
Die Web-Oberfläche kommuniziert über ein modernes, vollständig entkoppeltes **Event-Driven Job-System** mit dem Backend:
* **Zero-Polling:** Das Web-UI schreibt lediglich eine Job-Datei. Der Linux-Kernel (`systemd.path`) überwacht das Verzeichnis und triggert den Worker (`vdr-rectools-worker`) punktgenau als `oneshot`-Dienst.
* **Live-Status Feedback:** Der Worker schreibt aktive Status-Updates (`.status`), welche die Web-UI asynchron abfragt. Der Nutzer sieht in Echtzeit: *Wartet in Queue -> Arbeitet -> Fertig*.
* **Crash-Safe:** Atomare Dateioperationen und strenge Key-Value-Validierung garantieren, dass keine Jobs verloren gehen oder kaputte Daten verarbeitet werden.

---

## � Der Import-Workflow im Detail

Der Import ist das Herzstück von `vdr-rectools`. Das Skript durchsucht das `IMPORT_DIR` nach gängigen Videodateien wie `.mkv`, `.mp4`, `.avi`, `.mov` oder `.ts`.
Wenn eine Datei gefunden wird, passiert Folgendes im Hintergrund:

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

### Variante A: Installation über das yaVDR PPA / fertiges `.deb` Paket (Empfohlen)
Für Nutzer von yaVDR wird das Paket in der Regel über die offiziellen yaVDR-PPAs bereitgestellt (z.B. durch seahawk1986).
Alternativ kannst du dir das aktuellste Release von der GitHub Releases Seite herunterladen.

```bash
# Installation des manuell heruntergeladenen Pakets:
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
| **VDR_HOOK_DIR** | Pfad zum VDR Shutdown-Hooks Verzeichnis | `/etc/vdr/shutdown-hooks` |
| **MAIL_NOTIFY** | E-Mail-Adresse für Statusberichte | (leer) |
| **TELEGRAM_BOT_TOKEN** | API-Token für deinen Telegram-Bot | (leer) |
| **TELEGRAM_CHAT_ID** | Deine persönliche Telegram Chat-ID | (leer) |
| **AUTO_SUB_DOWNLOAD** | Automatischer Download von Untertiteln | `1` |
| **SUB_LANG** | Sprache für Untertitel (z.B. de, en) | `de` |
| **AUDIO_NORMALIZE** | Audio-Downmix (Stereo) & Dialog-Normalisierung (1=An, 0=Aus) | `0` |
| **AUTO_ENCODE_IMPORT** | Automatisches Re-Encoding beim Import (1=An, 0=Aus) | `1` |
| **ASK_BEFORE_ENCODE** | Nachfrage per Dashboard/Mail vor einem Re-Encode (1=An, 0=Aus) | `1` |
| **HTML_DASHBOARD** | Exportiert den Live-Status als HTML-Seite (1=An, 0=Aus) | `0` |
| **HTML_PATH** | Speicherpfad für das Web-Dashboard | `/var/www/html/rectools.html` |
| **LANGUAGE** | Sprache für das Web-Dashboard (`de`, `en`, `es`, `fr`, `it`, `pl`, `pt`) | `de` |
| **CRF_H264_DEFAULT** | CRF-Wert für H.264 (niedriger=besser) | `23` |
| **PRESET_H264_DEFAULT** | Preset für H.264 (z.B. `medium`, `fast`) | `medium` |
| **CRF_H265_DEFAULT** | CRF-Wert für H.265 (niedriger=besser) | `23` |
| **PRESET_H265_DEFAULT** | Preset für H.265 (z.B. `medium`, `fast`) | `medium` |
| **HW_ACCEL** | Hardwarebeschleunigung (`none`, `nvenc`, `vaapi`, `qsv`) | `none` |
| **SHRINK_MAX_RES** | Maximale Auflösung (Höhe) für Shrink. `0`=deaktiviert | `0` |
| **CRF_H264_FALLBACK** | CRF-Wert für Fallback-Encoding | `23` |
| **PRESET_H264_FALLBACK**| Preset für Fallback-Encoding | `fast` |
| **MIN_COMPRESSION_RATIO_H264** | Max. Dateigröße in % des Originals für H.264-Encodes | `70` |
| **MIN_COMPRESSION_RATIO_H265** | Max. Dateigröße in % des Originals für H.265-Encodes | `50` |
| **MIN_COMPRESSION_RATIO_H264_FALLBACK** | Max. Dateigröße in % des Originals für H.264-Fallback | `70` |
| **MIN_FREE_GB** | Mindestfreispeicher auf der Festplatte | `20` |
| **MAX_FILESIZE_GB** | Überspringt Importe ab dieser Dateigröße in GB (`0`=Aus) | `0` |
| **MAX_FILES** | Maximale Anzahl Dateien pro Durchlauf | `10` |
| **PAUSE_WORK** | Pause zwischen Arbeitsschritten (Sekunden) | `30` |
| **PAUSE_CHECK** | Pause zwischen Datei-Checks (Sekunden) | `2` |
| **SNAPSHOT_TIME** | Zeitstempel für generierte Vorschaubilder | `00:05:00` |
| **USE_TVSCRAPER** | Triggert tvscraper nach dem Import (1=An, 0=Aus) | `0` |
| **TVSCRAPER_MODE** | TVScraper Ausführungs-Modus (`immediate`, `batch`) | `batch` |

---

## 🕹 Bedienung

### Terminal-Befehle
* `vdr-rectools start` - Startet einen vollständigen Scan (Import & Cleanup) im Hintergrund.
* `vdr-rectools import` - Startet gezielt nur den MKV-Import-Prozess.
* `vdr-rectools repair` - Startet einen Reparatur-Lauf für alle Aufnahmen.
* `vdr-rectools status` - Zeigt PID, Laufzeit und die letzten Log-Zeilen an.
* `vdr-rectools osd-status` - Zeigt einen OSD-optimierten Status (für das VDR-Menü) an.
* `vdr-rectools diag` - Zeigt System-Diagnoseinformationen (Hardwarebeschleuniger, Encoder) an.
* `vdr-rectools confirm` - Bestätigt oder verwirft einen ausstehenden Re-Encode (inkl. Wiederherstellung).
* `vdr-rectools osd-confirm <yes|no>` - Bestätigt oder verwirft einen ausstehenden Re-Encode via OSD.
* `vdr-rectools stop` - Beendet laufende Hintergrundprozesse sauber.
* `vdr-rectools cron` - Simuliert den Timer-Aufruf (prüft `AUTO_START_NIGHT`).
* `vdr-rectools check_single <Pfad>` - Prüft gezielt eine einzelne Aufnahme auf Integrität.
* `vdr-rectools repair_single <Pfad>` - Repariert gezielt eine einzelne Aufnahme (Pfad zum .rec Ordner).
* `vdr-rectools cut_single <Pfad>` - Schneidet Werbung gezielt für eine Aufnahme anhand der Schnittmarken.
* `vdr-rectools shrink_single <Pfad>` - Komprimiert gezielt eine einzelne Aufnahme nach H.265.
* `vdr-rectools pes2ts` - Sucht rekursiv nach alten PES-Aufnahmen (`.vdr`) und konvertiert sie in das moderne TS-Format (`.ts`).
* `vdr-rectools pes2ts_single <Pfad>` - Konvertiert gezielt eine einzelne PES-Aufnahme in das TS-Format.

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

### Telegram-Benachrichtigungen
Neben E-Mails kann das Skript auch Push-Nachrichten an einen Telegram-Bot senden. 
Trage dazu einfach den `TELEGRAM_BOT_TOKEN` und deine `TELEGRAM_CHAT_ID` in der Konfiguration ein.
Das Skript meldet sich dann bei erfolgreichen Importen oder Fehlern direkt auf deinem Smartphone.

---

## 📺 VDR OSD-Integration
Die Befehle werden automatisch in das VDR-Menü (Befehle-Taste innerhalb einer Aufnahme) eingebunden:
* **Integrität prüfen (Rectools):** Prüft die aktuelle Aufnahme auf Stream-Fehler.
* **Aufnahme reparieren (Rectools):** Startet die Reparatur der aktuellen Aufnahme.
* **Werbung schneiden (Rectools):** Schneidet die Aufnahme basierend auf VDR-Marken.
* **Platz sparen H.265 (Rectools):** Konvertiert die Aufnahme nach HEVC.
* **PES zu TS konvertieren (Rectools):** Wandelt eine alte PES-Aufnahme in das TS-Format um.

### Globales OSD-Menü (`commands.conf`)
Du kannst ein eigenes Untermenü in der globalen `commands.conf` (z.B. `/var/lib/vdr/commands.conf` oder `/etc/vdr/commands.conf`) anlegen, um den Status direkt am Fernseher zu prüfen und globale Importe zu starten. Die Menüstruktur sieht dann so aus:

*   **VDR-Rectools** (Menütitel)
    *   **Status anzeigen:** `/usr/bin/vdr-rectools osd-status`
    *   **Import starten (im Hintergrund):** `/usr/bin/vdr-rectools import > /dev/null 2>&1 &`
    *   **PES zu TS Konvertierung starten:** `/usr/bin/vdr-rectools pes2ts > /dev/null 2>&1 &`
    *   **---** (Trennlinie)
    *   **Re-Encode ausstehend?** (Untermenü)
        *   **JA, Re-Encode jetzt starten:** `/usr/bin/vdr-rectools osd-confirm yes`
        *   **NEIN, überspringen & ignorieren:** `/usr/bin/vdr-rectools osd-confirm no`
        *   **Am PC (Handbrake) bearbeiten:** `/usr/bin/vdr-rectools osd-confirm manual`

---

## 📋 Voraussetzungen
Das Paket installiert Abhängigkeiten wie `vdr`, `ffmpeg`, `mediainfo`, `subliminal` und `mailx` automatisch mit.

---

## 📄 Lizenz & Maintainer
GPL-3.0+ | Maintainer: **Holger Schvestka** <hotzenplotz5@gmx.de>
