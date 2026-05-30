#!/bin/bash
set -e

echo "=========================================================="
echo " 🎬 VDR-Rectools - Manuelle Installation"
echo "=========================================================="

# 1. Root-Check
if [ "$EUID" -ne 0 ]; then
    echo "FEHLER: Bitte als root ausführen (z. B. sudo ./install.sh)"
    exit 1
fi

# 2. Abhängigkeiten prüfen
echo "-> Prüfe Abhängigkeiten..."
MISSING=0
for cmd in bash php ffmpeg ffprobe vdr svdrpsend; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "   FEHLER: Abhängigkeit '$cmd' fehlt."
        MISSING=1
    fi
done

if [ $MISSING -eq 1 ]; then
    echo "FEHLER: Bitte installiere die fehlenden Abhängigkeiten, bevor du fortfährst."
    exit 1
fi
echo "   Alle Abhängigkeiten gefunden."

# 3. Dateien kopieren
echo "-> Kopiere Programmdateien..."
mkdir -p /usr/bin /usr/share/vdr-rectools/lang /var/www/html/lang /etc/vdr /tmp/vdr-rectools-jobs

cp usr/bin/vdr-rectools usr/bin/vdr-rectools-worker /usr/bin/
cp -r usr/share/vdr-rectools/* /usr/share/vdr-rectools/
cp -r var/www/html/* /var/www/html/

# 4. Rechte setzen
echo "-> Setze Berechtigungen..."
chmod +x /usr/bin/vdr-rectools /usr/bin/vdr-rectools-worker
chmod +x /usr/share/vdr-rectools/*.sh
chmod 777 /tmp/vdr-rectools-jobs

# 5. Konfiguration sichern/kopieren
echo "-> Prüfe Konfiguration..."
if [ ! -f /etc/vdr/vdr-rectools.conf ] && [ ! -f /etc/vdr/conf.d/vdr-rectools.conf ]; then
    echo "   Erstelle Standardkonfiguration unter /etc/vdr/vdr-rectools.conf"
    cp debian/vdr-rectools.conf /etc/vdr/vdr-rectools.conf
else
    echo "   Konfiguration existiert bereits, wird nicht überschrieben."
fi

# 6. Systemd-Einheiten für Worker (Job-Queue) anlegen
echo "-> Installiere Systemd-Dienste für den Worker..."
if [ -d /etc/systemd/system ]; then
    cat <<EOFW > /etc/systemd/system/vdr-rectools-worker.service
[Unit]
Description=VDR-Rectools Web-UI Worker
[Service]
Type=oneshot
ExecStart=/usr/bin/vdr-rectools-worker
EOFW

    cat <<EOFP > /etc/systemd/system/vdr-rectools-worker.path
[Unit]
Description=VDR-Rectools Job Queue Watcher
[Path]
PathModified=/tmp/vdr-rectools-jobs
MakeDirectory=yes
[Install]
WantedBy=multi-user.target
EOFP

    systemctl daemon-reload || true
    systemctl enable vdr-rectools-worker.path --now >/dev/null 2>&1 || true
fi

# 7. PHP-FPM neuladen
echo "-> Lade PHP-FPM neu (für OPcache)..."
if [ -d /run/systemd/system ]; then
    systemctl reload-or-restart 'php*-fpm.service' >/dev/null 2>&1 || true
fi

echo "=========================================================="
echo " INSTALLATION ABGESCHLOSSEN!"
echo "=========================================================="
echo "Nächste Schritte:"
echo "1. Konfiguration anpassen: nano /etc/vdr/vdr-rectools.conf"
echo "2. Web-Oberfläche aufrufen: http://<IP-DEINES-VDR>/rectools.html"
echo "3. Stelle sicher, dass dein VDR-Aufnahmeverzeichnis (/srv/vdr/video)"
echo "   die korrekten Rechte (chown -R vdr:vdr) besitzt."
echo "=========================================================="