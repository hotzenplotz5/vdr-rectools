#!/bin/sh
set -e

# Debconf-Modul laden
. /usr/share/debconf/confmodule

CONF="/etc/vdr/conf.d/vdr-rectools.conf"
TEMPLATE="/usr/share/vdr-rectools/vdr-rectools.conf"
mkdir -p /etc/vdr/conf.d

# 1. ABSOLUT SICHERES CONFIG-MANAGEMENT
# Da Debian conffiles u.U. beim Entpacken (Unpack) ueberschreibt, nutzen wir nun ein Template.
# Wir kopieren das Template nur, wenn die Config noch gar nicht existiert.
if [ ! -f "$CONF" ]; then
    cp "$TEMPLATE" "$CONF" 2>/dev/null || true
elif [ -f "$TEMPLATE" ]; then
    # Smart-Merge: Existiert sie bereits, fuegen wir nur neue, fehlende Parameter sanft unten an.
    grep -E '^[A-Z_]+=' "$TEMPLATE" | while read -r line; do
        key=$(echo "$line" | cut -d'=' -f1)
        if ! grep -q "^$key=" "$CONF"; then
            echo "$line" >> "$CONF"
        fi
    done
fi

# 2. Debconf-Werte auslesen
db_get vdr-rectools/mail
MAIL_VAL="$RET"
db_get vdr-rectools/timer
[ "$RET" = "true" ] && TIMER_VAL=1 || TIMER_VAL=0
db_get vdr-rectools/subtitles
[ "$RET" = "true" ] && SUB_VAL=1 || SUB_VAL=0

# Werte sicher in der Datei aktualisieren
# Nur ausführen, wenn die Konfigurationsdatei existiert (Standard bei conffiles)
if [ -f "$CONF" ]; then
    sed -i "s|^MAIL_NOTIFY=.*|MAIL_NOTIFY=\"$MAIL_VAL\"|" "$CONF"
    sed -i "s|^AUTO_TIMER=.*|AUTO_TIMER=$TIMER_VAL|" "$CONF"
    sed -i "s|^AUTO_SUB_DOWNLOAD=.*|AUTO_SUB_DOWNLOAD=$SUB_VAL|" "$CONF"
fi

# 3. Systemd-Teil und Cleanup alter Hacks
if [ -d /run/systemd/system ]; then
    # Alten Workaround restlos entfernen
    rm -f /etc/systemd/system/vdr.service.d/99-rectools-menu.conf
    systemctl daemon-reload
    systemctl enable vdr-rectools.timer || true
    systemctl start vdr-rectools.timer || true
    systemctl enable vdr-rectools-web.service || true
    systemctl start vdr-rectools-web.service || true
fi

# 4. RECHTE UND ARBEITSVERZEICHNISSE (FIX FÜR USER VDR)
# ACHTUNG: NIEMALS chown -R auf das komplette /srv/vdr/video.00 Verzeichnis!
mkdir -p /srv/vdr/tmp/staging /srv/vdr/repaired_files /srv/vdr/video.00
chown -R vdr:vdr /srv/vdr/tmp/staging /srv/vdr/repaired_files
chmod -R 775 /srv/vdr/tmp/staging /srv/vdr/repaired_files
chown vdr:vdr /srv/vdr/video.00
chmod 775 /srv/vdr/video.00

# Konfigurationsdatei für den VDR-Webserver (PHP) beschreibbar machen,
# damit der Web-Editor im Dashboard Änderungen speichern darf.
if [ -f "$CONF" ]; then
    chown vdr:vdr "$CONF"
    chmod 664 "$CONF"
fi

# Logfile für vdr-user schreibbar machen
touch /var/log/vdr-rectools.log
chown vdr:vdr /var/log/vdr-rectools.log
chmod 664 /var/log/vdr-rectools.log

# HTML Dashboard-Datei anlegen und global beschreibbar machen
if [ -d "/var/www/html" ]; then
    touch /var/www/html/rectools.html
    chown vdr:vdr /var/www/html/rectools.html
    chmod 666 /var/www/html/rectools.html
    
    # PHP-Dateien dem Webserver-Nutzer (vdr) zuweisen
    chown vdr:vdr /var/www/html/*.php 2>/dev/null || true
    chmod 644 /var/www/html/*.php 2>/dev/null || true
fi

db_stop
#DEBHELPER#
exit 0
