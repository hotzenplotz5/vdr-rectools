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

function dispatch_job($action, $param = '') {
    $job_dir = '/tmp/vdr-rectools-jobs';
    if (!is_dir($job_dir)) {
        @mkdir($job_dir, 0777, true);
        @chmod($job_dir, 0777);
    }
    
    $job_id = uniqid('', true);
    $tmp_file = $job_dir . '/.tmp_' . $job_id;
    $job_file = $job_dir . '/job_' . $job_id . '.job';
    
    // Sicheres Key-Value Format mit strikten Quotes (Vorbeugung gegen '=' und Leerzeichen)
    $clean_action = str_replace(["\r", "\n", '"'], '', $action);
    $clean_param  = str_replace(["\r", "\n", '"'], '', $param);
    $payload  = "ACTION=\"" . $clean_action . "\"\n";
    $payload .= "PARAM=\"" . $clean_param . "\"\n";
    $payload .= "TIMESTAMP=\"" . time() . "\"\n";
    
    // Atomisches Schreiben: Erst Temp-Datei, dann Rename
    @file_put_contents($tmp_file, $payload);
    @chmod($tmp_file, 0666);
    @rename($tmp_file, $job_file);
    
    // KEIN WARTEN MEHR (Fire & Forget)!
}
?>