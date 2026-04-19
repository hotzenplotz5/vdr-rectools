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

| Variable | Beschreibung | Standard |
| :--- | :--- | :--- |
| **AUTO_START_NIGHT** | Erlaubt den nächtlichen Automatik-Scan (1=An, 0=Aus) | `0` |
| **AUTO_TIMER** | Genereller Schalter für Timer-Aktionen | `0` |
| **IMPORT_DIR** | Pfad zu neuen Filmen für den Import | `/srv/video/Filme` |
| **MAIL_NOTIFY** | E-Mail-Adresse für Statusberichte | (leer) |
| **AUTO_SUB_DOWNLOAD** | Automatischer Download von Untertiteln | `1` |
| **MIN_FREE_GB** | Mindestfreispeicher auf der Festplatte | `20` |

---

## 🕹 Bedienung & Workflows

### Einzelfall-Reparatur (Manuell)
Wenn eine spezifische Aufnahme defekt ist, kann diese gezielt repariert werden, ohne einen Voll-Scan zu starten:
```bash
# Syntax: vdr-rectools repair_single <Pfad_zur_Aufnahme>
vdr-rectools repair_single "/srv/vdr/video.00/Mein_Film/2026-04-19.10.00.1-0.rec"
```
*Das Skript erstellt ein Re-Mux der `.ts`-Dateien, korrigiert die Zeitstempel und stellt sicher, dass die Aufnahme wieder flüssig abspielbar ist.*

### Globale Steuerung
* `vdr-rectools start` - Vollständiger Scan (Import & Cleanup) im Hintergrund.
* `vdr-rectools status` - Zeigt an, ob ein Prozess läuft, die PID und die letzten Log-Zeilen.
* `vdr-rectools stop` - Bricht eine laufende Hintergrund-Verarbeitung sofort ab.

---

## 📈 Monitoring & Feedback

### Logging
Alle Aktionen werden detailliert protokolliert. Dies ist die erste Anlaufstelle bei Problemen:
* **Logfile:** `/var/log/vdr-rectools.log`
* **Echtzeit-Überwachung:** `tail -f /var/log/vdr-rectools.log`

### E-Mail-Benachrichtigungen
Falls `MAIL_NOTIFY` konfiguriert ist, versendet das System nach Abschluss eines automatischen Scans oder einer Reparatur eine Zusammenfassung. Diese enthält:
* **Status:** Erfolg oder Fehlermeldung des Prozesses.
* **Statistik:** Anzahl der importierten Filme und reparierten Aufnahmen.
* **Speicherplatz:** Aktueller Füllstand der Video-Partition.
* **Fehler-Details:** Falls FFmpeg oder andere Tools auf Probleme gestoßen sind.

---

## 🕹 VDR OSD-Integration
Nach der Installation finden sich im VDR-Menü unter "Befehle" (innerhalb einer Aufnahme) folgende Optionen:
* **Aufnahme reparieren (Rectools):** Startet `repair_single` für die aktuelle Aufnahme.
* **Werbung schneiden (Rectools):** Schneidet die Aufnahme basierend auf gesetzten Marken.
* **Platz sparen H.265 (Rectools):** Konvertiert die aktuelle Aufnahme nach HEVC.

---

## 📄 Lizenz & Maintainer
GPL-3.0+  
Maintainer: **Holger Schvestka** <hotzenplotz5@gmx.de>
