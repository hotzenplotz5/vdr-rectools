<?php
if (isset($_GET['action'])) {
    if ($_GET['action'] === 'import') {
        exec('nohup /usr/bin/vdr-rectools import </dev/null >/tmp/rectools_web.log 2>&1 &');
    } elseif ($_GET['action'] === 'stop') {
        exec('nohup /usr/bin/vdr-rectools stop </dev/null >/tmp/rectools_web.log 2>&1 &');
    } elseif ($_GET['action'] === 'restart_vdr') {
        exec('nohup sudo /bin/systemctl --no-block restart vdr.service </dev/null >/dev/null 2>&1 &');
    } else {
        $prompt_file = '/srv/vdr/video/.vdr-rectools.prompt';
        if (file_exists($prompt_file)) {
            $content = trim(file_get_contents($prompt_file));
            $parts = explode('|', $content);
            if (isset($parts[0]) && $parts[0] === 'WAIT') {
                if ($_GET['action'] === 'yes') {
                    $action = 'YES';
                } elseif ($_GET['action'] === 'manual') {
                    $action = 'MANUAL';
                } else {
                    $action = 'NO';
                }
                $new_content = $action . '|' . $parts[1] . '|' . (isset($parts[2]) ? $parts[2] : '') . "\n";
                $fp = fopen($prompt_file, 'w');
                if ($fp) { fwrite($fp, $new_content); fclose($fp); }
            }
        }
    }
}
    usleep(750000); // 0.75 Sekunden warten, damit das Bash-Skript Zeit hat, das Dashboard neu zu zeichnen
header('Location: rectools.html?t=' . time());
exit;
?>