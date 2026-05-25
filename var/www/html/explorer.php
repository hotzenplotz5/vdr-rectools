<?php
$conf_file = '/etc/vdr/conf.d/vdr-rectools.conf';
$import_dir = '/srv/vdr/import';
if (file_exists($conf_file)) {
    $lines = file($conf_file);
    foreach ($lines as $line) {
        if (preg_match('/^IMPORT_DIR=["\']?(.*?)["\']?$/', trim($line), $m)) $import_dir = $m[1];
    }
}

// Aktuelle Pfade auslesen (Standard: Quelle = Root, Ziel = Import_Dir)
$src = isset($_GET['src']) ? realpath($_GET['src']) : '/';
if (!$src || !is_dir($src)) $src = '/';

$dst = isset($_GET['dst']) ? realpath($_GET['dst']) : $import_dir;
if (!$dst || !is_dir($dst)) $dst = $import_dir;

$msg = '';

// Dateioperationen verarbeiten
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    if ($_POST['action'] === 'move' && isset($_POST['file'])) {
        $file = $_POST['file'];
        $filename = basename($file);
        $target = $dst . '/' . $filename;
        
        if (!file_exists($file)) {
            $msg = "<div class='msg msg-err'>❌ Quelldatei nicht gefunden!</div>";
        } elseif (file_exists($target)) {
            $msg = "<div class='msg msg-err'>❌ Datei '$filename' existiert im Ziel bereits!</div>";
        } else {
            // Verschieben (kann bei großen Dateien über Partitionsgrenzen hinweg dauern)
            if (@rename($file, $target)) {
                $msg = "<div class='msg msg-ok'>✅ '$filename' erfolgreich verschoben!</div>";
            } else {
                $msg = "<div class='msg msg-err'>❌ Fehler beim Verschieben (Fehlende Rechte?).</div>";
            }
        }
    } elseif ($_POST['action'] === 'mkdir' && !empty($_POST['dirname'])) {
        $newdir = $dst . '/' . basename($_POST['dirname']);
        if (!file_exists($newdir)) {
            if (@mkdir($newdir, 0775)) {
                $msg = "<div class='msg msg-ok'>✅ Ordner '" . basename($_POST['dirname']) . "' erstellt!</div>";
            } else {
                $msg = "<div class='msg msg-err'>❌ Fehler beim Erstellen des Ordners.</div>";
            }
        } else {
            $msg = "<div class='msg msg-err'>❌ Ordner existiert bereits!</div>";
        }
    } elseif ($_POST['action'] === 'upload' && isset($_FILES['upload_file'])) {
        $file_tmp = $_FILES['upload_file']['tmp_name'];
        $file_name = basename($_FILES['upload_file']['name']);
        if (is_uploaded_file($file_tmp)) {
            if (@move_uploaded_file($file_tmp, $dst . '/' . $file_name)) {
                $msg = "<div class='msg msg-ok'>✅ '$file_name' erfolgreich hochgeladen!</div>";
            } else {
                $msg = "<div class='msg msg-err'>❌ Fehler beim Speichern der hochgeladenen Datei im Zielordner.</div>";
            }
        } else {
            $msg = "<div class='msg msg-err'>❌ Upload fehlgeschlagen. (Datei zu groß oder abgebrochen?)</div>";
        }
    }
}

function get_dir_contents($dir) {
    $items = @scandir($dir);
    $dirs = []; $files = [];
    if ($items !== false) {
        foreach ($items as $item) {
            if ($item === '.') continue;
            $path = rtrim($dir, '/') . '/' . $item;
            if ($item === '..') {
                if ($dir !== '/') $dirs[] = ['name' => '⬅️ .. (Eine Ebene hoch)', 'path' => dirname($dir)];
                continue;
            }
            if (is_dir($path)) $dirs[] = ['name' => '📁 ' . $item, 'path' => $path];
            else $files[] = ['name' => '📄 ' . $item, 'path' => $path, 'raw_path' => $path];
        }
    }
    return ['dirs' => $dirs, 'files' => $files];
}

$src_contents = get_dir_contents($src);
$dst_contents = get_dir_contents($dst);
?>
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>📁 VDR-Rectools Explorer</title>
    <style>
        body { background-color: #121212; color: #e0e0e0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: rgba(30, 30, 30, 0.6); backdrop-filter: blur(15px); -webkit-backdrop-filter: blur(15px); padding: 25px; border-radius: 12px; box-shadow: 0 10px 30px rgba(0,0,0,0.8); border: 1px solid rgba(255,255,255,0.05); }
        h2 { border-bottom: 2px solid #333; padding-bottom: 15px; margin-top: 0; color: #fff; }
        .msg { padding: 12px; border-radius: 6px; margin-bottom: 20px; font-weight: bold; }
        .msg-ok { background: rgba(76, 175, 80, 0.2); border: 1px solid #4CAF50; color: #4CAF50; }
        .msg-err { background: rgba(244, 67, 54, 0.2); border: 1px solid #F44336; color: #F44336; }
        .split-view { display: flex; gap: 20px; margin-bottom: 20px; }
        .pane { flex: 1; background: rgba(0, 0, 0, 0.4); border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; padding: 15px; display: flex; flex-direction: column; }
        .pane h3 { margin-top: 0; color: #2196F3; font-size: 1.1em; border-bottom: 1px solid #444; padding-bottom: 8px; }
        .path-bar { background: #000; padding: 8px 12px; border-radius: 4px; font-family: monospace; color: #aaa; margin-bottom: 15px; overflow-x: auto; white-space: nowrap; }
        .list { flex-grow: 1; height: 50vh; overflow-y: auto; background: #111; border-radius: 6px; padding: 10px; border: 1px solid #333; }
        .item { display: flex; justify-content: space-between; align-items: center; padding: 8px; border-bottom: 1px solid #222; transition: background 0.2s; }
        .item:hover { background: #2a2a2a; }
        .item a { color: #e0e0e0; text-decoration: none; flex-grow: 1; display: block; }
        .item a:hover { color: #2196F3; }
        .btn { display: inline-block; background: #555; color: white; padding: 10px 20px; text-decoration: none; border-radius: 6px; font-weight: bold; border: none; cursor: pointer; font-size: 14px; box-shadow: 0 2px 5px rgba(0,0,0,0.3); }
        .btn:hover { background: #444; }
        .btn-move { background: #9C27B0; padding: 4px 10px; font-size: 12px; margin-left: 10px; }
        .btn-move:hover { background: #7B1FA2; }
        .btn-back { background: #333; margin-right: 15px; }
        .btn-back:hover { background: #222; }
        .mkdir-form { display: flex; gap: 10px; margin-top: 15px; }
        .mkdir-form input { flex-grow: 1; padding: 8px; border-radius: 4px; border: 1px solid #444; background: #000; color: #fff; }
    </style>
</head>
<body>
    <div class="container">
        <h2>📁 VDR-Rectools Explorer</h2>
        <?= $msg ?>
        
        <div class="split-view">
            <!-- LINKE SEITE (Quelle) -->
            <div class="pane">
                <h3>🔍 Quelle (Auswählen & Verschieben)</h3>
                
                <div style="background: rgba(33, 150, 243, 0.1); border: 1px solid #2196F3; padding: 15px; border-radius: 8px; margin-bottom: 15px;">
                    <h4 style="margin-top:0; color:#2196F3; margin-bottom: 10px;">📤 Von Deinem PC hochladen</h4>
                    <form method="POST" enctype="multipart/form-data" style="display:flex; flex-wrap: wrap; gap:10px; align-items: center;">
                        <input type="hidden" name="action" value="upload">
                        <input type="file" name="upload_file" required style="color:#fff; flex-grow: 1;">
                        <button type="submit" class="btn btn-move" style="margin:0; padding: 8px 15px; font-size: 14px;">🚀 Hochladen</button>
                    </form>
                    <div style="color:#aaa; font-size: 0.85em; margin-top: 8px;">Lädt eine Datei von diesem Computer direkt in den Zielordner (Rechts) hoch.</div>
                </div>
                
                <div class="path-bar"><?= htmlspecialchars($src) ?></div>
                <div class="list">
                    <?php foreach ($src_contents['dirs'] as $d): ?>
                        <div class="item"><a href="?src=<?= urlencode($d['path']) ?>&dst=<?= urlencode($dst) ?>"><strong><?= htmlspecialchars($d['name']) ?></strong></a></div>
                    <?php endforeach; ?>
                    <?php foreach ($src_contents['files'] as $f): ?>
                        <div class="item">
                            <span style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"><?= htmlspecialchars($f['name']) ?></span>
                            <form method="POST" style="margin: 0;">
                                <input type="hidden" name="action" value="move">
                                <input type="hidden" name="file" value="<?= htmlspecialchars($f['raw_path']) ?>">
                                <button type="submit" class="btn btn-move" onclick="return confirm('Datei nach Rechts verschieben? (Dauert je nach Groesse kurz)');">➡️ Rüber</button>
                            </form>
                        </div>
                    <?php endforeach; ?>
                </div>
            </div>
            
            <!-- RECHTE SEITE (Ziel) -->
            <div class="pane">
                <h3>🎯 Ziel (IMPORT_DIR)</h3>
                <div class="path-bar"><?= htmlspecialchars($dst) ?></div>
                <div class="list">
                    <?php foreach ($dst_contents['dirs'] as $d): ?>
                        <div class="item"><a href="?src=<?= urlencode($src) ?>&dst=<?= urlencode($d['path']) ?>"><strong><?= htmlspecialchars($d['name']) ?></strong></a></div>
                    <?php endforeach; ?>
                    <?php foreach ($dst_contents['files'] as $f): ?>
                        <div class="item" style="color: #888;"><?= htmlspecialchars($f['name']) ?></div>
                    <?php endforeach; ?>
                </div>
                <form method="POST" class="mkdir-form">
                    <input type="hidden" name="action" value="mkdir">
                    <input type="text" name="dirname" placeholder="Neuer Ordnername..." required>
                    <button type="submit" class="btn" style="margin-top: 0;">Ordner erstellen</button>
                </form>
            </div>
        </div>
        
        <a href="rectools.html" class="btn btn-back">⬅️ Zurück zum Dashboard</a>
    </div>
</body>
</html>