<?php
function parseConfig($text) {
    $out = [];
    foreach (explode("\n", str_replace("\r\n", "\n", $text)) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') continue;
        if (preg_match('/^([A-Z0-9_]+)=(.*)$/', $line, $m)) {
            $key = trim($m[1]);
            if (!isset($out[$key])) {
                $out[$key] = trim(trim($m[2]), "\"'");
            }
        }
    }
    return $out;
}

function serializeConfig($config) {
    $out = "";
    foreach ($config as $k => $v) {
        $out .= $k . "=\"" . $v . "\"\n";
    }
    return $out;
}

function normalizeLanguage($lang) {
    if (!is_string($lang)) return 'de';
    if (!preg_match('/^[a-z]{2}(_[A-Z]{2})?$/', $lang)) {
        return 'de';
    }
    return $lang;
}

function write_job_status($job_id, $state, $progress = 0, $message = '') {
    $job_dir = '/tmp/vdr-rectools-jobs';
    $file = $job_dir . '/' . $job_id . '.status';
    $tmp  = $file . '.tmp';
    
    $data  = "state=" . $state . "\n";
    $data .= "progress=" . intval($progress) . "\n";
    $data .= "message=" . str_replace(["\n","\r"], "", $message) . "\n";
    $data .= "updated=" . time() . "\n";
    
    @file_put_contents($tmp, $data, LOCK_EX);
    @chmod($tmp, 0666);
    @rename($tmp, $file);
}

function read_job_status($job_id) {
    $file = '/tmp/vdr-rectools-jobs/' . $job_id . '.status';
    if (!file_exists($file)) return ['state' => 'unknown', 'progress' => 0, 'message' => '', 'updated' => 0];
    
    $data = parseConfig((string)@file_get_contents($file));
    return [
        'state'    => $data['state'] ?? 'unknown',
        'progress' => intval($data['progress'] ?? 0),
        'message'  => $data['message'] ?? '',
        'updated'  => intval($data['updated'] ?? 0)
    ];
}

function dispatch_job($action, $param = '') {
    $job_dir = '/tmp/vdr-rectools-jobs';
    if (!is_dir($job_dir)) {
        @mkdir($job_dir, 0777, true);
        @chmod($job_dir, 0777);
    }
    
    clearstatcache(true);
    $conf_file = '/etc/vdr/conf.d/vdr-rectools.conf';
    $configMap = file_exists($conf_file) ? parseConfig((string)@file_get_contents($conf_file)) : [];
    $sys_lang = normalizeLanguage($configMap['LANGUAGE'] ?? 'de');

    // Idempotency (Exactly-once execution): Dedupliziere identische Intents
    $idempotency_key = md5($action . '|' . $param . '|' . $sys_lang);
    $key_file = $job_dir . '/key_' . $idempotency_key;
    
    clearstatcache(true, $key_file);
    if (file_exists($key_file)) {
        // Enhancement 1 (Job TTL): "Haengende" Idempotency-Keys nach 10 Minuten verwerfen
        if (time() - filemtime($key_file) > 600) {
            @unlink($key_file);
        } else {
            $existing_job = trim((string)@file_get_contents($key_file));
            // Deduplizieren, wenn der Job noch in der Warteschlange ist oder gerade laeuft
            if (file_exists($job_dir . '/' . $existing_job . '.job') || file_exists($job_dir . '/' . $existing_job . '.lock')) {
                return $existing_job;
            }
        }
    }
    
    $job_id = 'job_' . uniqid('', true);
    $tmp_file = $job_dir . '/.tmp_' . $job_id;
    $job_file = $job_dir . '/' . $job_id . '.job';

    write_job_status($job_id, 'queued', 0, 'Wartet in der Queue');
    
    // Sicheres Key-Value Format mit strikten Quotes (Vorbeugung gegen '=' und Leerzeichen)
    $clean_action = str_replace(["\r", "\n", '"'], '', $action);
    $clean_param  = str_replace(["\r", "\n", '"'], '', $param);
    $payload  = "ACTION=\"" . $clean_action . "\"\n";
    $payload .= "PARAM=\"" . $clean_param . "\"\n";
    $payload .= "LANGUAGE=\"" . $sys_lang . "\"\n";
    $payload .= "IDEMPOTENCY_KEY=\"" . $idempotency_key . "\"\n";
    $payload .= "TIMESTAMP=\"" . time() . "\"\n";
    
    // Atomisches Schreiben: Erst Temp-Datei, dann Rename
    @file_put_contents($tmp_file, $payload);
    @chmod($tmp_file, 0666);
    @file_put_contents($key_file, $job_id, LOCK_EX); // Idempotency Key atomar absichern (LOCK_EX)
    @rename($tmp_file, $job_file);
    
    return $job_id;
}
?>