<?php
function dispatch_job($action, $param = '') {
    $job_dir = '/tmp/vdr-rectools-jobs';
    if (!is_dir($job_dir)) {
        @mkdir($job_dir, 0777, true);
        @chmod($job_dir, 0777);
    }
    
    $job_id = uniqid('', true);
    $tmp_file = $job_dir . '/.tmp_' . $job_id;
    $job_file = $job_dir . '/job_' . $job_id . '.job';
    
    // Sicheres reines Text-Format (Key=Value), ohne Bash-Quotes fuer den sicheren read-Loop
    $clean_action = str_replace(["\r", "\n"], "", $action);
    $clean_param = str_replace(["\r", "\n"], "", $param);
    $payload = "ACTION=" . $clean_action . "\n";
    $payload .= "PARAM=" . $clean_param . "\n";
    $payload .= "TIMESTAMP=" . time() . "\n";
    
    // Atomisches Schreiben: Erst Temp-Datei, dann Rename
    @file_put_contents($tmp_file, $payload);
    @chmod($tmp_file, 0666);
    @rename($tmp_file, $job_file);
    
    // KEIN WARTEN MEHR (Fire & Forget)!
}
?>