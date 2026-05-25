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