<?php
require_once __DIR__ . '/job_dispatcher.php';

function load_video_dir() {
    $video_dir = '/srv/vdr/video';
    $config_candidates = [
        '/etc/vdr/vdr-rectools.conf',
        '/etc/vdr/conf.d/vdr-rectools.conf'
    ];
    $config_file = '';
    foreach ($config_candidates as $cand) {
        if (file_exists($cand)) {
            $config_file = $cand;
            break;
        }
    }
    if ($config_file !== '') {
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
    if ($name !== '' && $path !== '') {
        return dispatch_job('rename', $path . '|' . $name);
    }
    return null;
}

function moveRecording($path, $target) {
    // Alle strikten Pfad- und Sicherheitsprüfungen finden ausschließlich im Backend statt
    $target = trim(preg_replace('/[\r\n]+/', '', (string)$target));
    if ($target !== '' && $path !== '') {
        return dispatch_job('move', $path . '|' . $target);
    }
    return null;
}

function trashRecording($path) {
    if ($path !== '') {
        return dispatch_job('trash', $path);
    }
    return null;
}

function waitForJobDone($job_id, $timeoutSeconds = 5) {
    $job_id = preg_replace('/[^a-zA-Z0-9_.-]/', '', (string)$job_id);
    if ($job_id === '') return;

    $status_file = '/tmp/vdr-rectools-jobs/' . $job_id . '.status';
    $end = microtime(true) + $timeoutSeconds;

    while (microtime(true) < $end) {
        clearstatcache(true, $status_file);
        if (file_exists($status_file)) {
            $data = parseConfig((string)@file_get_contents($status_file));
            $state = $data['state'] ?? '';
            if ($state === 'done' || $state === 'error') {
                return;
            }
        }
        usleep(100000);
    }
}

$job_id = null;

if (isset($_GET['action'])) {
    $action_req = trim((string)$_GET['action']);
    if ($action_req === 'import') {
        $job_id = dispatch_job('import');
    } elseif (in_array($action_req, ['pes2ts', 'shrink', 'repair', 'cut', 'check', 'rename', 'trash', 'move'], true)) {
        // Die Pfad-Validierung greift nun sicher und dynamisch fuer alle Einzel-Aktionen!
        $path = '';
        if (!empty($_GET['path'])) {
            $videoRoot = realpath($video_dir);
            $realPath  = realpath($_GET['path']);
            
            error_log("RECTOOLS MOVE path=" . $_GET['path'] . " real=" . $realPath . " root=" . $videoRoot);

            if (
                $realPath === false ||
                $videoRoot === false ||
                ($realPath !== $videoRoot && strpos($realPath, $videoRoot . DIRECTORY_SEPARATOR) !== 0) ||
                !is_dir($realPath)
            ) {
                exit('Zugriff verweigert oder ungueltiger Pfad.');
            }
            $path = $realPath;
        }
        if ($action_req === 'rename') {
            $job_id = renameRecording($path, isset($_GET['name']) ? (string)$_GET['name'] : '');
            if ($job_id) {
                waitForJobDone($job_id, 2);
            }
        } elseif ($action_req === 'move') {
            $job_id = moveRecording($path, isset($_GET['target']) ? (string)$_GET['target'] : '');
            if ($job_id) {
                waitForJobDone($job_id, 2);
            }
        } elseif ($action_req === 'trash') {
            $job_id = trashRecording($path);
        } else {
            $job_id = dispatch_job($action_req, $path);
        }
    } elseif ($action_req === 'stop') {
        $job_id = dispatch_job('stop');
    } elseif ($action_req === 'restart_vdr') {
        $job_id = dispatch_job('restart_vdr');
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
        $job_id = dispatch_job('update-html');
    }
}

$return = isset($_GET['return']) ? (string)$_GET['return'] : '';
if ($return !== '' && preg_match('/^(rectools\.html|pes2ts_explorer\.php|config\.php)(\?.*)?$/', $return)) {
    $sep = (strpos($return, '?') !== false) ? '&' : '?';
    header('Location: ' . $return . $sep . 't=' . time());
} else {
    header('Location: rectools.html?t=' . time());
}
exit;
?>