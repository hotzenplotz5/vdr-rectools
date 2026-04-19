# vdr-rectools (v1.7.3)

**vdr-rectools** ist eine leistungsstarke Media-Suite für den Video Disk Recorder (VDR). Es bietet eine automatisierte Lösung zum Reparieren, Schneiden, Konvertieren und Importieren von Aufnahmen sowie eine nahtlose Integration in das VDR-OSD und moderne Media-Server wie Plex oder Kodi.

---

## 🚀 Hauptfunktionen

* **MKV-to-VDR Import:** Verwandelt externe MKV-Dateien vollautomatisch in abspielbare VDR-Aufnahmen.
* **Reparatur-Modus:** Repariert defekte Aufnahmen (z.B. nach Stream-Fehlern) durch Re-Muxing via FFmpeg.
* **Werbung schneiden:** Wendet VDR-Schnittmarken direkt auf die Dateien an (verlustfrei).
* **H.265 Shrink:** Konvertiert Aufnahmen platzsparend nach HEVC (H.265).
* **Nacht-Modus:** Ein intelligenter Systemd-Timer führt Wartungsarbeiten nur dann aus, wenn du es in der Config erlaubst.
* **OSD-Befehle:** Alle Funktionen sind direkt über das VDR-Menü "Befehle" erreichbar.

---

## 📂 Der MKV-Import Workflow (Highlight)

Dies ist die Kernfunktion für die Integration externer Medien. Das Tool überwacht den in der Config definierten `IMPORT_DIR`.

### Was passiert beim Import?
Wenn du eine `.mkv` Datei in den Import-Ordner legst und `vdr-rectools import` startest (oder der Timer läuft):
1. **Validierung:** Das Tool prüft via `mediainfo`, ob die Datei valide Video-Streams enthält.
2. **Struktur-Erstellung:** Es wird ein VDR-konformer Aufnahme-Ordner erstellt (z.B. `Filmname/2026-04-19.10.00.1-0.rec`).
3. **Re-Muxing:** Die MKV wird ohne Qualitätsverlust (Stream-Copy) in eine `.ts` Datei umgewandelt.
4. **Metadaten-Generierung:** Es wird automatisch eine `info`-Datei generiert, damit der VDR Titel, Länge und technische Details im Menü anzeigt.
5. **Bereinigung:** Nach erfolgreichem Import wird die ursprüngliche MKV-Datei gelöscht (konfigurierbar), um Platz zu sparen.

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
| **IMPORT_DIR** | Pfad, in den MKV-Filme zum Import kopiert werden | `/srv/video/Filme` |
| **AUTO_START_NIGHT** | Erlaubt den nächtlichen Automatik-Scan (1=An, 0=Aus) | `0` |
| **AUTO_TIMER** | Genereller Schalter für Timer-Aktionen | `0` |
| **MAIL_NOTIFY** | E-Mail-Adresse für Statusberichte | (leer) |
| **MIN_FREE_GB** | Mindestfreispeicher auf der Festplatte | `20` |

---

## 🕹 Bedienung & Workflows

### Globale Steuerung
* `vdr-rectools import` - Startet gezielt den Scan des `IMPORT_DIR
