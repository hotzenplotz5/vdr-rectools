<?php
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Cache-Control: post-check=0, pre-check=0", false);
header("Pragma: no-cache");
header("Expires: 0");
$conf_file = '/etc/vdr/conf.d/vdr-rectools.conf';
$msg = '';
$save_success = false;
$save_error = false;

// 1. ZUERST die Konfiguration speichern, falls ein POST-Request vorliegt!
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['config_data'])) {
    $new_data = str_replace("\r\n", "\n", $_POST['config_data']);
    if (file_put_contents($conf_file, $new_data) !== false) {
        $new_lang = 'de';
        if (preg_match('/^LANGUAGE=["\']?(.*?)["\']?$/m', $new_data, $m)) { $new_lang = trim($m[1]); }
        // Dashboard-Update explizit als Bash-Hintergrundprozess (identisch zum Import-Button)
        exec('nohup /bin/bash -c "/usr/bin/vdr-rectools update-html ' . escapeshellarg($new_lang) . '" </dev/null >/dev/null 2>&1 &');
        $save_success = true;
    } else {
        $save_error = true;
    }
}

// Dateisystem-Cache leeren, um sicherzustellen, dass die gerade gespeicherte Konfiguration gelesen wird
clearstatcache();

// 2. DANN die (nun möglicherweise aktualisierte) Config auslesen
$language = 'de';
$current_conf = '';
if (file_exists($conf_file)) {
    $current_conf = (string)@file_get_contents($conf_file);
    if (preg_match('/^LANGUAGE=["\']?(.*?)["\']?$/m', $current_conf, $m)) { $language = trim($m[1]); }
}

// 3. DANN das richtige Wörterbuch basierend auf der aktuellen Sprache laden
$lang_file = __DIR__ . "/lang/{$language}.json";
if (!file_exists($lang_file)) $lang_file = __DIR__ . "/lang/de.json";
$translations = [];
if (file_exists($lang_file)) {
    $json_content = preg_replace('/^\xEF\xBB\xBF/', '', (string)@file_get_contents($lang_file));
    $decoded = json_decode($json_content, true);
    if (is_array($decoded)) $translations = $decoded;
}
function __($key, ...$args) {
    global $translations;
    $text = isset($translations[$key]) ? $translations[$key] : $key;
    return !empty($args) ? vsprintf($text, $args) : $text;
}

// 4. JETZT ERST die korrekten, uebersetzten Meldungen generieren
if ($save_success) {
    $msg = "<div style='color: #4CAF50; padding: 15px; background: rgba(76, 175, 80, 0.2); border: 1px solid #4CAF50; border-radius: 8px; margin-bottom: 20px; font-weight: bold;'>" . __('cfg_saved') . "</div>";
} elseif ($save_error) {
    $msg = "<div style='color: #F44336; padding: 15px; background: rgba(244, 67, 54, 0.2); border: 1px solid #F44336; border-radius: 8px; margin-bottom: 20px; font-weight: bold;'>" . __('cfg_err') . "</div>";
}
?>
<!DOCTYPE html>
<html lang="<?= htmlspecialchars($language) ?>">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= __('cfg_title') ?></title>
    <style>
        body { background-color: #121212; color: #e0e0e0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; }
        .container { max-width: 900px; margin: 0 auto; background: rgba(30, 30, 30, 0.6); backdrop-filter: blur(15px); -webkit-backdrop-filter: blur(15px); padding: 25px; border-radius: 12px; box-shadow: 0 10px 30px rgba(0,0,0,0.8); border: 1px solid rgba(255,255,255,0.05); }
        h2 { border-bottom: 2px solid #333; padding-bottom: 15px; margin-top: 0; color: #fff; }
        textarea { width: 100%; height: 500px; background: #000; color: #4CAF50; border: 1px solid #444; border-radius: 8px; padding: 15px; font-family: 'Consolas', 'Courier New', monospace; font-size: 14px; box-sizing: border-box; line-height: 1.4; resize: vertical; }
        .btn { display: inline-block; background: #2196F3; color: white; padding: 10px 20px; text-decoration: none; border-radius: 6px; font-weight: bold; border: none; cursor: pointer; font-size: 15px; margin-top: 20px; box-shadow: 0 2px 5px rgba(0,0,0,0.3); }
        .btn:hover { background: #1976D2; }
        .btn-back { background: #555; margin-right: 15px; text-decoration: none;}
        .btn-back:hover { background: #444; }
    </style>
</head>
<body>
    <div class="container">
        <h2><?= __('cfg_title') ?></h2>
        <?= $msg ?>
        <form method="POST">
            <textarea name="config_data" spellcheck="false"><?= htmlspecialchars($current_conf) ?></textarea>
            <div>
                <a href="rectools.html?t=<?= time() ?>" class="btn btn-back"><?= __('btn_back') ?></a>
                <button type="submit" class="btn"><?= __('cfg_btn_save') ?></button>
            </div>
        </form>
    </div>
</body>
</html>