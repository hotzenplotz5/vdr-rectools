<?php
require_once __DIR__ . '/job_dispatcher.php';

if (isset($_GET['action'])) {
    if ($_GET['action'] === 'import') {
        dispatch_job('import');
    } elseif ($_GET['action'] === 'stop') {
        dispatch_job('stop');
    } elseif ($_GET['action'] === 'restart_vdr') {
        dispatch_job('restart_vdr');
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
        // UI Update anfordern, damit der Prompt sofort verschwindet
        exec('/usr/bin/vdr-rectools update-html >/dev/null 2>&1');
    }
}

header('Location: rectools.html?t=' . time());
exit;
?>