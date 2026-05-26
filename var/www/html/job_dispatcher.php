<?php
function dispatch_job($action, $param = '') {
    $job_dir = '/tmp/vdr-rectools-jobs';
    if (!is_dir($job_dir)) {
        @mkdir($job_dir, 0777, true);
        @chmod($job_dir, 0777);
    }
    
    $job_id = uniqid();
    $job_file = $job_dir . '/job_' . $job_id . '.job';
    $done_file = $job_dir . '/job_' . $job_id . '.done';
    
    $data = $action . '|' . $param;
    @file_put_contents($job_file, $data);
    @chmod($job_file, 0666);
    
    // Warten auf Abschluss durch den Worker (max 5 Sekunden)
    $timeout = 50; 
    while (!file_exists($done_file) && $timeout > 0) {
        usleep(100000); // 100ms
        $timeout--;
    }
    @unlink($done_file);
}
?>