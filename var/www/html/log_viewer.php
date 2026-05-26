<?php
$conf_file = '/etc/vdr/conf.d/vdr-rectools.conf';
$language = 'de';
if (file_exists($conf_file)) {
    $lines = file($conf_file);
    foreach ($lines as $line) {
        if (preg_match('/^LANGUAGE=["\']?(.*?)["\']?$/', trim($line), $m)) $language = $m[1];
    }
}

$lang_file = __DIR__ . "/lang/{$language}.json";
if (!file_exists($lang_file)) $lang_file = __DIR__ . "/lang/de.json";
$translations = [];
if (file_exists($lang_file)) {
    $json_content = preg_replace('/^\xEF\xBB\xBF/', '', file_get_contents($lang_file));
    $decoded = json_decode($json_content, true);
    if (is_array($decoded)) $translations = $decoded;
}
function __($key, ...$args) {
    global $translations;
    $text = isset($translations[$key]) ? $translations[$key] : $key;
    return !empty($args) ? vsprintf($text, $args) : $text;
}

$log_file = '/var/log/vdr-rectools.log';
$log_content = file_exists($log_file) ? htmlspecialchars(file_get_contents($log_file)) : __('log_not_found');
?>
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= __('log_title') ?></title>
    <style>
        body { background-color: #121212; color: #e0e0e0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; }
        .container { max-width: 1000px; margin: 0 auto; background: rgba(30, 30, 30, 0.6); backdrop-filter: blur(15px); -webkit-backdrop-filter: blur(15px); padding: 25px; border-radius: 12px; box-shadow: 0 10px 30px rgba(0,0,0,0.8); border: 1px solid rgba(255,255,255,0.05); }
        h2 { border-bottom: 2px solid #333; padding-bottom: 15px; margin-top: 0; color: #fff; }
        .log-area { background: #000; color: #4CAF50; border: 1px solid #444; border-radius: 8px; padding: 15px; font-family: 'Consolas', 'Courier New', monospace; font-size: 13px; height: 65vh; overflow-y: auto; white-space: pre-wrap; word-wrap: break-word; line-height: 1.5;}
        .btn { display: inline-block; background: #555; color: white; padding: 10px 20px; text-decoration: none; border-radius: 6px; font-weight: bold; margin-top: 20px; box-shadow: 0 2px 5px rgba(0,0,0,0.3); }
        .btn:hover { background: #444; }
        .btn-refresh { background: #2196F3; margin-left: 10px; }
        .btn-refresh:hover { background: #1976D2; }
    </style>
    <script>
        // Automatisch ganz nach unten scrollen beim Laden
        window.onload = function() {
            var logArea = document.getElementById("log-area");
            logArea.scrollTop = logArea.scrollHeight;
        }
    </script>
</head>
<body>
    <div class="container">
        <h2><?= __('log_title') ?></h2>
        <div class="log-area" id="log-area"><?= $log_content ?></div>
        <div>
            <a href="rectools.html" class="btn"><?= __('btn_back') ?></a>
            <a href="log_viewer.php" class="btn btn-refresh"><?= __('log_btn_refresh') ?></a>
        </div>
    </div>
</body>
</html>