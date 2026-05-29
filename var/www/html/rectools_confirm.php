<?php
require_once __DIR__ . '/job_dispatcher.php';

function load_video_dir() {
    $video_dir = '/srv/vdr/video';
    $config_file = '/etc/vdr/conf.d/vdr-rectools.conf';
    if (file_exists($config_file)) {
        $lines = file($config_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        foreach ($lines as $line) {
            $line = trim($line);
            if (strpos($line, 'VIDEO_DIR=') === 0) {
                $val = substr($line, 10);
                $val = trim($val, "\"' \r\n");
                if (!empty($val)) {
                    $video_dir = $val;
                }
            }
        }
    }
    return $video_dir;
}

$video_dir = load_video_dir();

// VDR-Suite Helfer-Funktion (API Vorbereitung)
function renameRecording($path, $name) {
    $name = trim(preg_replace('/[\/\\\]+/', '', $name)); // Keine Slashes
    $name = str_replace('..', '', $name); // Keine Pfadbestandteile
    $name = htmlspecialchars($name, ENT_QUOTES, 'UTF-8'); // HTML escapen
    if ($name !== '' && $path !== '') {
        dispatch_job('rename', $path . '|' . $name);
    }
}

function trashRecording($path) {
    if ($path !== '') {
        dispatch_job('trash', $path);
    }
}

if (isset($_GET['action'])) {
    $action_req = trim((string)$_GET['action']);
    if ($action_req === 'import') {
        dispatch_job('import');
    } elseif (in_array($action_req, ['pes2ts', 'shrink', 'repair', 'cut', 'check', 'rename', 'trash'], true)) {
        // Die Pfad-Validierung greift nun sicher und dynamisch fuer alle Einzel-Aktionen!
        $path = '';
        if (!empty($_GET['path'])) {
            $real = realpath($_GET['path']);
            $base = realpath($video_dir);
            if ($real && $base && ($real === $base || strpos($real, $base . '/') === 0) && is_dir($real)) {
                $path = $real;
            } else {
                exit('Zugriff verweigert oder ungueltiger Pfad.');
            }
        }
        if ($action_req === 'rename') {
            renameRecording($path, isset($_GET['name']) ? (string)$_GET['name'] : '');
        } elseif ($action_req === 'trash') {
            trashRecording($path);
        } else {
            dispatch_job($action_req, $path);
        }
    } elseif ($action_req === 'stop') {
        dispatch_job('stop');
    } elseif ($action_req === 'restart_vdr') {
        dispatch_job('restart_vdr');
    } else {
        $prompt_file = $video_dir . '/.vdr-rectools.prompt';
        if (file_exists($prompt_file)) {
            $content = trim(file_get_contents($prompt_file));
            $parts = explode('|', $content);
            if (isset($parts[0]) && $parts[0] === 'WAIT') {
                if ($action_req === 'yes') {
                    $action = 'YES';
                } elseif ($action_req === 'manual') {
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
        dispatch_job('update-html');
    }
}

header('Location: rectools.html?t=' . time());
exit;
?>