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