# 🛠️ VDR-Rectools Installation

Dieses Dokument beschreibt die verschiedenen Wege, um **vdr-rectools** auf deinem System zu installieren und wieder zu entfernen.

---

## 1. Installationsmethoden

### Methode A: Debian-Paket (.deb) - **BEVORZUGT**

Für alle Debian- und Ubuntu-basierten Systeme (z.B. yaVDR, MLD) ist die Installation über das fertige `.deb`-Paket der empfohlene Weg. Das Paket kümmert sich automatisch um Abhängigkeiten, Systemd-Dienste, OSD-Menü-Integration und Updates.

```bash
# Heruntergeladenes Paket installieren
sudo apt install ./vdr-rectools_*.deb
```

---

## 2. Manuelle Installation (für Nicht-Debian Systeme)

Falls du eine andere Linux-Distribution nutzt oder keine Paketverwaltung verwenden möchtest, kannst du das beiliegende `install.sh` Skript als Community-Fallback nutzen.

Das Skript kopiert die Dateien, setzt die Rechte und richtet die notwendigen Systemd-Worker-Pfade ein, **ohne** dabei bestehende Konfigurationen zu überschreiben oder Daten zu löschen.

### Installation starten:
```bash
# Im geklonten Repository ausführen
chmod +x install.sh
sudo ./install.sh
```

### Benötigte Abhängigkeiten:
Stelle sicher, dass folgende Pakete vor der manuellen Installation auf deinem System vorhanden sind:
* `bash` (>= 4.0)
* `php` (php-fpm oder php-cgi für den Webserver)
* `ffmpeg` und `ffprobe`
* `vdr`
* `svdrpsend`

---

## 3. Wichtige Pfade & Konfiguration

Unabhängig von der Installationsmethode nutzt VDR-Rectools folgende Standard-Pfade:

* **Konfigurationsdatei:** `/etc/vdr/vdr-rectools.conf` oder `/etc/vdr/conf.d/vdr-rectools.conf`
* **CLI-Kommando:** `/usr/bin/vdr-rectools`
* **Web-UI:** `/var/www/html/rectools.html` und `/var/www/html/pes2ts_explorer.php`
* **Logfile:** `/var/log/vdr-rectools.log`
* **Job-Queue (Temporär):** `/tmp/vdr-rectools-jobs/`

---

## 4. Web-UI Aufruf & PHP Cache (OPcache)

Nach der Installation ist das Web-Dashboard und der Explorer unter folgender URL erreichbar:
👉 `http://<IP-DEINES-VDR>/rectools.html`

**Wichtiger Hinweis zu PHP-Updates:**
Solltest du PHP-Dateien im Verzeichnis `/var/www/html/` manuell aktualisieren, musst du zwingend den PHP-OPcache leeren, da ansonsten veralteter Code aus dem Arbeitsspeicher ausgeführt wird.
Führe dazu (je nach PHP-Version) einen Reload aus:
```bash
sudo systemctl reload-or-restart 'php*-fpm.service'
```
*(Die `install.sh` und das Debian-Paket machen dies bei Installationen automatisch).*

---

## 5. Rechtehinweise

VDR-Rectools agiert oft als der User `www-data` (vom Webserver) oder als der User, der die CLI-Befehle ausführt. Damit das reibungslos klappt, ist es absolut essenziell, dass dein Aufnahmeverzeichnis dem VDR-Benutzer gehört und Gruppen-Schreibrechte besitzt.

```bash
# Beispiel (Pfade ggf. anpassen)
sudo chown -R vdr:vdr /srv/vdr/video
sudo chmod -R 775 /srv/vdr/video
```