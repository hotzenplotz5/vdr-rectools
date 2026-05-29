<?php
$id = preg_replace('/[^a-zA-Z0-9_.-]/', '', $_GET['id'] ?? '');
$return = isset($_GET['return']) ? (string)$_GET['return'] : '';

if ($return !== '' && !preg_match('/^(rectools\.html|pes2ts_explorer\.php|config\.php)(\?.*)?$/', $return)) {
    $return = 'rectools.html';
}

if (!$id) {
    header('Location: ' . ($return ?: 'rectools.html'));
    exit;
}

// Sprache für UI via Config laden
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

$language = 'de';
require_once __DIR__ . '/job_dispatcher.php';
clearstatcache(true);
if ($config_file !== '') {
    $configMap = parseConfig((string)@file_get_contents($config_file));
    $language = normalizeLanguage($configMap['LANGUAGE'] ?? 'de');
}
?>
<!DOCTYPE html>
<html lang="<?php echo htmlspecialchars($language, ENT_QUOTES, 'UTF-8'); ?>">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bitte warten...</title>
    <style>
        body { background-color: #121212; color: #e0e0e0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
        .box { background: rgba(30,30,30,0.8); padding: 30px; border-radius: 12px; text-align: center; border: 1px solid rgba(255,255,255,0.1); box-shadow: 0 10px 30px rgba(0,0,0,0.8); max-width: 500px; width: 100%; }
        .spinner { border: 4px solid rgba(255,255,255,0.1); border-top: 4px solid #00BCD4; border-radius: 50%; width: 50px; height: 50px; animation: spin 1s linear infinite; margin: 0 auto 20px; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        .btn { display: inline-block; background: #555; color: white; padding: 10px 20px; text-decoration: none; border-radius: 6px; font-weight: bold; margin-top: 20px; cursor: pointer; }
        .btn:hover { background: #444; }
        .error { color: #F44336; margin-top: 15px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="box">
        <div class="spinner" id="spinner"></div>
        <h3 id="status-title" style="margin-top: 0;">Aktion wird ausgeführt...</h3>
        <div id="status-msg" style="color:#aaa;">Wartet auf Worker...</div>
        <a href="<?php echo htmlspecialchars($return, ENT_QUOTES, 'UTF-8'); ?>" class="btn" id="back-btn" style="display:none;">Zurück</a>
    </div>
    <script>
        const jobId = <?php echo json_encode($id); ?>;
        const returnUrl = <?php echo json_encode($return ?: 'rectools.html'); ?>;
        
        const timer = setInterval(async () => {
            try {
                const res = await fetch('job_status.php?id=' + jobId);
                const data = await res.json();
                
                if (data.state === 'running' || data.state === 'queued') {
                    document.getElementById('status-msg').innerText = data.message || 'Arbeitet...';
                } else if (data.state === 'done') {
                    clearInterval(timer);
                    document.getElementById('status-title').innerText = 'Abgeschlossen!';
                    document.getElementById('status-title').style.color = '#4CAF50';
                    document.getElementById('status-msg').innerText = data.message || 'Aktion erfolgreich.';
                    document.getElementById('spinner').style.display = 'none';
                    const separator = returnUrl.indexOf('?') !== -1 ? '&' : '?';
                    window.location.href = returnUrl + separator + 't=' + Date.now();
                } else if (data.state === 'error') {
                    clearInterval(timer);
                    document.getElementById('status-title').innerText = 'Fehler aufgetreten';
                    document.getElementById('status-title').style.color = '#F44336';
                    document.getElementById('status-msg').innerText = data.message || 'Die Aktion ist fehlgeschlagen.';
                    document.getElementById('status-msg').className = 'error';
                    document.getElementById('spinner').style.display = 'none';
                    document.getElementById('back-btn').style.display = 'inline-block';
                }
            } catch (e) {}
        }, 500);
    </script>
</body>
</html>