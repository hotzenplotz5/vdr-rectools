<?php
require_once __DIR__ . '/job_dispatcher.php';
header('Content-Type: application/json');

$id = preg_replace('/[^a-zA-Z0-9_.-]/', '', $_GET['id'] ?? '');
if (!$id) {
    echo json_encode(['state' => 'error', 'message' => 'No ID provided']);
    exit;
}
echo json_encode(read_job_status($id));
?>