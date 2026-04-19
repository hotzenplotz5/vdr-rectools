# vdr-rectools (v1.7.3)

**vdr-rectools** ist eine leistungsstarke Media-Suite für den Video Disk Recorder (VDR). Es bietet eine automatisierte Lösung zum Reparieren, Schneiden, Konvertieren und Importieren von Aufnahmen sowie eine nahtlose Integration in das VDR-OSD und moderne Media-Server wie Plex oder Kodi.

---

## 🚀 Hauptfunktionen

* **MKV-to-VDR Import:** Verwandelt externe MKV-Dateien vollautomatisch in abspielbare VDR-Aufnahmen inklusive Metadaten.
* **Reparatur-Modus:** Repariert defekte Aufnahmen (z.B. nach Stream-Fehlern) durch Re-Muxing via FFmpeg.
* **Werbung schneiden:** Wendet VDR-Schnittmarken direkt auf die Dateien an (verlustfrei).
* **H.265 Shrink:** Konvertiert Aufnahmen platzsparend nach HEVC (H.265).
* **Nacht-Modus:** Ein intelligenter Systemd-Timer führt Wartungsarbeiten nur dann aus, wenn du es in der Konfiguration erlaubst.
* **OSD-Integration:** Alle Funktionen sind direkt über das VDR-Menü "Befehle" erreichbar.

---

## 📂 Der MKV-Import Workflow (Detail)

Dies ist die Kernfunktion für die Integration externer Medien. Das Tool überwacht den in der Config definierten `IMPORT_DIR`.

### Was passiert beim Import?
Wenn du eine `.mkv` Datei in den Import-Ordner legst und `vdr-rectools import` startest:
1. **Validierung:** Das Tool prüft via `mediainfo`, ob die Datei valide Video-Streams enthält.
2. **Struktur-Erstellung:** Es wird ein VDR-konformer Aufnahme-Ordner erstellt (z.B. `Filmname/2026-04-19.10.00.1-0.rec`).
3. **Re-Muxing:** Die MKV wird ohne Qualitätsverlust (Stream-Copy) in eine `.ts` Datei umgewandelt. Dabei werden inkompatible Container-Formate sauber für den VDR aufbereitet.
4. **Metadaten-Generierung:** Es wird automatisch eine `info`-Datei generiert, damit der VDR Titel, Länge und technische Details im Menü anzeigt.
5. **Bereinigung:** Nach erfolgreichem Import wird die ursprüngliche MKV-Datei gelöscht (konfigurierbar), um Platz zu sparen.

---

## 🛠 Installation

```bash
# Repository klonen
git clone [https://github.com/hotzenplotz5/vdr-rectools.git](https://github.com/hotzenplotz5/vdr-rectools.git)
cd vdr-rectools

# Paket bauen & installieren
debuild -us -uc
sudo dpkg -i ../vdr-rectools_1.7.3_all.deb
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
