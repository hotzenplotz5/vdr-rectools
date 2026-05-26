<?php
header('Content-Type: application/json');

$dir = '/tmp/vdr-rectools-jobs';

echo json_encode([
    'queue'   => count(glob("$dir/*.job") ?: []),
    'running' => count(glob("$dir/*.lock") ?: []),
    'done'    => count(glob("$dir/*.done") ?: [])
]);
?>