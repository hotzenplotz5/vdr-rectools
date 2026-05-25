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

    # PHP-Handler für Bestätigungs-Buttons anlegen
    cat << 'EOFPHP' > /var/www/html/rectools_confirm.php
<?php
if (isset($_GET['action'])) {
    if ($_GET['action'] === 'import') {
        exec('nohup /usr/bin/vdr-rectools import </dev/null >/tmp/rectools_web.log 2>&1 &');
    } elseif ($_GET['action'] === 'stop') {
        exec('nohup /usr/bin/vdr-rectools stop </dev/null >/tmp/rectools_web.log 2>&1 &');
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

    # PHP-Router für Passwortschutz (Basic Auth) anlegen
    cat << 'EOFPHP' > /var/www/html/router.php
<?php
$config_file = '/etc/vdr/conf.d/vdr-rectools.conf';
$user = 'admin';
$pass = 'vdr123';
if (file_exists($config_file)) {
    $lines = file($config_file);
    foreach ($lines as $line) {
        if (preg_match('/^WEB_USER=["\']?(.*?)["\']?$/', trim($line), $m)) $user = $m[1];
        if (preg_match('/^WEB_PASS=["\']?(.*?)["\']?$/', trim($line), $m)) $pass = $m[1];
    }
}
if (!isset($_SERVER['PHP_AUTH_USER']) || $_SERVER['PHP_AUTH_USER'] !== $user || $_SERVER['PHP_AUTH_PW'] !== $pass) {
    header('WWW-Authenticate: Basic realm="VDR-Rectools Dashboard"');
    header('HTTP/1.0 401 Unauthorized');
    echo 'Zugriff verweigert! Bitte Zugangsdaten eingeben.';
    exit;
}
return false; // Authentifizierung erfolgreich, reiche Anfrage an den Webserver weiter
?>
EOFPHP
    chown vdr:vdr /var/www/html/router.php
    chmod 666 /var/www/html/router.php

    # PHP-Konfigurationseditor anlegen
    cat << 'EOFPHP' > /var/www/html/config.php
<?php
$conf_file = '/etc/vdr/conf.d/vdr-rectools.conf';
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['config_data'])) {
    $new_data = str_replace("\r\n", "\n", $_POST['config_data']);
    if (file_put_contents($conf_file, $new_data) !== false) {
        $msg = "<div style='color: #4CAF50; padding: 15px; background: rgba(76, 175, 80, 0.2); border: 1px solid #4CAF50; border-radius: 8px; margin-bottom: 20px; font-weight: bold;'>✅ Konfiguration erfolgreich gespeichert!</div>";
    } else {
        $msg = "<div style='color: #F44336; padding: 15px; background: rgba(244, 67, 54, 0.2); border: 1px solid #F44336; border-radius: 8px; margin-bottom: 20px; font-weight: bold;'>❌ Fehler beim Speichern! (Keine Schreibrechte?)</div>";
    }
}
$current_conf = file_exists($conf_file) ? file_get_contents($conf_file) : '';
?>
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>⚙️ VDR-Rectools Konfiguration</title>
    <style>
        body { background-color: #121212; color: #e0e0e0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; }
        .container { max-width: 900px; margin: 0 auto; background: rgba(30, 30, 30, 0.6); backdrop-filter: blur(15px); -webkit-backdrop-filter: blur(15px); padding: 25px; border-radius: 12px; box-shadow: 0 10px 30px rgba(0,0,0,0.8); border: 1px solid rgba(255,255,255,0.05); }
        h2 { border-bottom: 2px solid #333; padding-bottom: 15px; margin-top: 0; color: #fff; }
        textarea { width: 100%; height: 500px; background: #000; color: #4CAF50; border: 1px solid #444; border-radius: 8px; padding: 15px; font-family: 'Consolas', 'Courier New', monospace; font-size: 14px; box-sizing: border-box; line-height: 1.4; resize: vertical; }
        .btn { display: inline-block; background: #2196F3; color: white; padding: 10px 20px; text-decoration: none; border-radius: 6px; font-weight: bold; border: none; cursor: pointer; font-size: 15px; margin-top: 20px; box-shadow: 0 2px 5px rgba(0,0,0,0.3); }
        .btn:hover { background: #1976D2; }
        .btn-back { background: #555; margin-right: 15px; }
        .btn-back:hover { background: #444; }
    </style>
</head>
<body>
    <div class="container">
        <h2>⚙️ Einstellungen (vdr-rectools.conf)</h2>
        <?= $msg ?>
        <form method="POST">
            <textarea name="config_data" spellcheck="false"><?= htmlspecialchars($current_conf) ?></textarea>
            <div>
                <a href="rectools.html" class="btn btn-back">⬅️ Zurück zum Dashboard</a>
                <button type="submit" class="btn">💾 Konfiguration speichern</button>
            </div>
        </form>
    </div>
</body>
</html>
EOFPHP
    chown vdr:vdr /var/www/html/config.php
    chmod 666 /var/www/html/config.php
fi

db_stop
#DEBHELPER#
exit 0
