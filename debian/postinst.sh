#!/bin/sh
set -e

# Debconf-Modul laden
. /usr/share/debconf/confmodule

CONF="/etc/vdr/conf.d/vdr-rectools.conf"
mkdir -p /etc/vdr/conf.d

# 1. FIX FÜR DAS CONFFILE-PROBLEM (Sicheres Update ohne Datenverlust!)
# Anstatt die Datei brutal zu ueberschreiben (was Benutzerdaten wie Telegram-Tokens loescht),
# fuegen wir nur neue, fehlende Parameter aus dem Update sanft unten an.
for EXT in ".dpkg-dist" ".dpkg-new"; do
    if [ -f "${CONF}${EXT}" ]; then
        grep -E '^[A-Z_]+=' "${CONF}${EXT}" | while read -r line; do
            key=$(echo "$line" | cut -d'=' -f1)
            if ! grep -q "^$key=" "$CONF"; then
                echo "$line" >> "$CONF"
            fi
        done
        rm -f "${CONF}${EXT}"
    fi
done

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

# Logfile für vdr-user schreibbar machen
touch /var/log/vdr-rectools.log
chown vdr:vdr /var/log/vdr-rectools.log
chmod 664 /var/log/vdr-rectools.log

# HTML Dashboard-Datei anlegen und global beschreibbar machen
if [ -d "/var/www/html" ]; then
    touch /var/www/html/rectools.html
    chown vdr:vdr /var/www/html/rectools.html
    chmod 666 /var/www/html/rectools.html

    # PHP-Handler für Bestätigungs-Buttons anlegen
    cat << 'EOFPHP' > /var/www/html/rectools_confirm.php
<?php
if (isset($_GET['action'])) {
    if ($_GET['action'] === 'import') {
        exec('nohup /usr/bin/vdr-rectools import </dev/null >/tmp/rectools_web.log 2>&1 &');
    } else {
        $prompt_file = '/srv/vdr/video/.vdr-rectools.prompt';
        if (file_exists($prompt_file)) {
            $content = trim(file_get_contents($prompt_file));
            $parts = explode('|', $content);
            if (isset($parts[0]) && $parts[0] === 'WAIT') {
                $action = $_GET['action'] === 'yes' ? 'YES' : 'NO';
                $new_content = $action . '|' . $parts[1] . '|' . (isset($parts[2]) ? $parts[2] : '') . "\n";
                $fp = fopen($prompt_file, 'w');
                if ($fp) { fwrite($fp, $new_content); fclose($fp); }
            }
        }
    }
}
header('Location: rectools.html');
exit;
?>
EOFPHP
    chown vdr:vdr /var/www/html/rectools_confirm.php
    chmod 666 /var/www/html/rectools_confirm.php
fi

db_stop
#DEBHELPER#
exit 0
