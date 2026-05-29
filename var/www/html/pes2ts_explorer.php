<?php
$config_file = '/etc/vdr/conf.d/vdr-rectools.conf';
$video_dir = '/srv/vdr/video';

if (file_exists($config_file)) {
    $lines = file($config_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        $line = trim($line);
        if (strpos($line, 'VIDEO_DIR=') === 0) {
            $val = substr($line, 10);
            $val = trim($val, "\"' \r\n");
            if (!empty($val)) {
                $video_dir = $val;
            }
        }
    }
}

$base_dir = realpath($video_dir);
if (!$base_dir || !is_dir($base_dir)) {
    die("VIDEO_DIR existiert nicht oder ist ungueltig.");
}

$req_dir = isset($_GET['dir']) ? (string)$_GET['dir'] : '';
$req_dir = trim($req_dir, '/\\');

$target_path = $req_dir === '' ? $base_dir : $base_dir . DIRECTORY_SEPARATOR . $req_dir;
$current_path = realpath($target_path);

// Security-Check: Verhindert Directory-Traversal (z.B. ../video2)
if ($current_path === false || ($current_path !== $base_dir && strpos($current_path, $base_dir . DIRECTORY_SEPARATOR) !== 0)) {
    $current_path = $base_dir;
}

$rel_path = ltrim(substr($current_path, strlen($base_dir)), DIRECTORY_SEPARATOR);

// VDR-Suite Helfer-Funktionen (API Vorbereitung)
function getRecordingDate($pathname) {
    if (preg_match('/^(\d{4})-(\d{2})-(\d{2})\.(\d{2})\.(\d{2})\./', basename($pathname), $m)) {
        return $m[3] . '.' . $m[2] . '.' . $m[1] . ' ' . $m[4] . ':' . $m[5];
    }
    $mtime = @filemtime($pathname);
    if ($mtime) {
        return date('d.m.Y H:i', $mtime);
    }
    return 'Unbekannt';
}

function getRecordingTitle($filename) {
    return str_replace('_', ' ', $filename);
}

$folders = [];
$recordings = [];
$counts = ['folders' => 0, 'total' => 0, 'pes' => 0, 'ts' => 0, 'unknown' => 0];

try {
    $iterator = new DirectoryIterator($current_path);
    foreach ($iterator as $fileinfo) {
        if ($fileinfo->isDot()) continue;
        
        if ($fileinfo->isDir()) {
            $filename = $fileinfo->getFilename();
            $pathname = $fileinfo->getRealPath();
            
            $is_rec = false;
            $rec_path = '';
            $rec_name = '';

            if (substr($filename, -4) === '.rec') {
                $is_rec = true;
                $rec_path = $pathname;
                $rec_name = $filename;
            } else {
                $rec_count = 0;
                $non_rec_dir_count = 0;
                $single_rec_path = '';
                
                try {
                    $sub_iterator = new DirectoryIterator($pathname);
                    foreach ($sub_iterator as $sub_fileinfo) {
                        if ($sub_fileinfo->isDot()) continue;
                        if ($sub_fileinfo->isDir()) {
                            if (substr($sub_fileinfo->getFilename(), -4) === '.rec') {
                                $rec_count++;
                                $single_rec_path = $sub_fileinfo->getRealPath();
                            } else {
                                $non_rec_dir_count++;
                                break;
                            }
                        }
                    }
                    if ($rec_count === 1 && $non_rec_dir_count === 0) {
                        $is_rec = true;
                        $rec_path = $single_rec_path;
                        $rec_name = $filename;
                    }
                } catch (Exception $e) {
                    // Ignorieren falls Berechtigungsfehler
                }
            }

            if ($is_rec) {
                $has_pes = false;
                $has_ts = false;
                
                if ($dh = @opendir($rec_path)) {
                    while (($item = readdir($dh)) !== false) {
                        if (preg_match('/^[0-9]{3}\.vdr$/', $item)) {
                            $has_pes = true;
                            break;
                        } elseif (preg_match('/^000.*\.ts$/', $item)) {
                            $has_ts = true;
                        }
                    }
                    closedir($dh);
                }
                
                if ($has_pes) {
                    $status = 'pes'; $sort = 1; $counts['pes']++;
                } elseif ($has_ts) {
                    $status = 'ts'; $sort = 2; $counts['ts']++;
                } else {
                    $status = 'unknown'; $sort = 3; $counts['unknown']++;
                }
                $counts['total']++;
                
                $recordings[] = [
                    'path' => $rec_path,
                    'name' => $rec_name,
                    'title' => getRecordingTitle($rec_name),
                    'date' => getRecordingDate($rec_path),
                    'status' => $status,
                    'sort' => $sort
                ];
            } else {
                $folders[] = [
                    'name' => $filename,
                    'rel_path' => $rel_path === '' ? $filename : $rel_path . '/' . $filename
                ];
                $counts['folders']++;
            }
        }
    }
} catch (Exception $e) {
    // Ignorieren falls Berechtigungsfehler
}

usort($folders, function($a, $b) {
    return strcasecmp($a['name'], $b['name']);
});
usort($recordings, function($a, $b) {
    if ($a['sort'] !== $b['sort']) return $a['sort'] - $b['sort'];
    return strcasecmp($a['name'], $b['name']);
});

// Breadcrumb Navigation
$parts = $rel_path === '' ? [] : explode('/', $rel_path);
$breadcrumb_html = '<a href="?dir=" style="color: #00BCD4; text-decoration: none; font-weight: bold;">Start</a>';
$accumulated = '';
foreach ($parts as $part) {
    $accumulated .= ($accumulated === '' ? '' : '/') . $part;
    $breadcrumb_html .= ' / <a href="?dir=' . rawurlencode($accumulated) . '" style="color: #00BCD4; text-decoration: none; font-weight: bold;">' . htmlspecialchars(str_replace('_', ' ', $part), ENT_QUOTES, 'UTF-8') . '</a>';
}
?>
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>VDR-Rectools - Aufnahmen Explorer</title>
    <style>
        body { background-color: #121212; color: #fff; font-family: Arial, sans-serif; padding: 20px; max-width: 1000px; margin: 0 auto; }
        a.btn { display: inline-block; background: #00BCD4; color: white; padding: 6px 12px; text-decoration: none; border-radius: 4px; font-weight: bold; text-align: center; font-size: 0.9em; }
        a.btn:hover { filter: brightness(1.1); }
        a.btn.back { background: #555; margin-bottom: 20px; }
        a.btn.shrink { background: #2196F3; }
        a.btn.repair { background: #FF9800; }
        a.btn.check  { background: #4CAF50; }
        a.btn.cut    { background: #9C27B0; }
        a.btn.convert{ background: #F44336; }
        .breadcrumb { margin-bottom: 20px; font-size: 1.1em; background: rgba(255,255,255,0.05); padding: 12px; border-radius: 5px; border: 1px solid rgba(255,255,255,0.1); }
        .breadcrumb a:hover { text-decoration: underline; }
        .stats { display: flex; gap: 15px; margin-bottom: 20px; background: rgba(255,255,255,0.05); padding: 15px; border-radius: 5px; border: 1px solid rgba(255,255,255,0.1); }
        .stat-box { flex: 1; text-align: center; }
        .stat-num { font-size: 1.5em; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; background: rgba(255,255,255,0.02); border-radius: 5px; overflow: hidden; }
        th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid rgba(255,255,255,0.1); }
        th { background: rgba(255,255,255,0.05); font-weight: bold; color: #ccc; }
        .status-pes { color: #FF9800; font-weight: bold; }
        .status-ts { color: #4CAF50; font-weight: bold; }
        .status-unknown { color: #9E9E9E; font-weight: bold; }
        .path { font-size: 0.85em; color: #888; margin-top: 4px; word-break: break-all; }
        .title { font-weight: bold; font-size: 1.1em; color: #e0e0e0; }
    </style>
</head>
<body>
    <h2>🔄 VDR-Aufnahmen Explorer</h2>
    <p style="color: #ccc;">Navigiere durch deine VDR-Aufnahmen. Aktionen wie Konvertieren, Reparieren oder Schrumpfen (H.265) koennen gezielt gestartet werden.</p>
    
    <div style="display: flex; justify-content: space-between; margin-bottom: 20px;">
        <a href="rectools.html" class="btn back" style="margin-bottom: 0;">🔙 Zurueck zum Dashboard</a>
        <?php if ($rel_path !== ''): ?>
            <?php 
                $up_dir = dirname($rel_path); 
                if ($up_dir === '.') $up_dir = '';
            ?>
            <a href="?dir=<?php echo rawurlencode($up_dir); ?>" class="btn back" style="margin-bottom: 0;">⬅️ .. (Eine Ebene hoch)</a>
        <?php endif; ?>
    </div>

    <div class="breadcrumb">
        📍 <?php echo $breadcrumb_html; ?>
    </div>
    
    <div class="stats">
        <div class="stat-box" style="color: #00BCD4;"><div class="stat-num"><?php echo $counts['folders']; ?></div>Ordner</div>
        <div class="stat-box"><div class="stat-num"><?php echo $counts['total']; ?></div>Gesamt</div>
        <div class="stat-box" style="color: #FF9800;"><div class="stat-num"><?php echo $counts['pes']; ?></div>PES</div>
        <div class="stat-box" style="color: #4CAF50;"><div class="stat-num"><?php echo $counts['ts']; ?></div>TS</div>
        <div class="stat-box" style="color: #9E9E9E;"><div class="stat-num"><?php echo $counts['unknown']; ?></div>Unbekannt</div>
    </div>
    
    <?php if (count($folders) > 0 || count($recordings) > 0): ?>
        <table>
            <thead>
                <tr>
                    <th>Name</th>
                    <th>Status</th>
                    <th>Aktion</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($folders as $folder): ?>
                    <tr>
                        <td>
                            <div class="title">
                                <a href="?dir=<?php echo rawurlencode($folder['rel_path']); ?>" style="color: #e0e0e0; text-decoration: none;">
                                    📁 <?php echo htmlspecialchars(str_replace('_', ' ', $folder['name']), ENT_QUOTES, 'UTF-8'); ?>
                                </a>
                            </div>
                        </td>
                        <td><span style="color: #bbb;">Ordner</span></td>
                        <td><a href="?dir=<?php echo rawurlencode($folder['rel_path']); ?>" class="btn">Öffnen</a></td>
                    </tr>
                <?php endforeach; ?>

                <?php foreach ($recordings as $rec): ?>
                    <?php $status = $rec['status']; ?>
                    <tr>
                        <td>
                            <div class="title"><?php echo htmlspecialchars($rec['title'], ENT_QUOTES, 'UTF-8'); ?></div>
                            <div style="font-size: 0.85em; color: #888; margin-top: 4px;">Aufgenommen: <?php echo htmlspecialchars($rec['date'], ENT_QUOTES, 'UTF-8'); ?></div>
                        </td>
                        <td>
                            <?php if ($status === 'pes'): ?>
                                <span class="status-pes">Alte PES-Aufnahme</span>
                            <?php elseif ($status === 'ts'): ?>
                                <span class="status-ts">TS-Aufnahme</span>
                            <?php else: ?>
                                <span class="status-unknown">Unbekannt</span>
                            <?php endif; ?>
                        </td>
                        <td>
                            <div style="display: flex; gap: 5px; flex-wrap: wrap;">
                                <a href="#" class="btn" style="background: #607D8B;" onclick="renameRecordingUI('<?php echo rawurlencode($rec['path']); ?>', '<?php echo htmlspecialchars(addslashes($rec['title']), ENT_QUOTES, 'UTF-8'); ?>'); return false;">Umbenennen</a>
                                <?php if ($status === 'pes'): ?>
                                    <a href="rectools_confirm.php?action=pes2ts&path=<?php echo rawurlencode($rec['path']); ?>" class="btn convert">PES&rarr;TS</a>
                                <?php elseif ($status === 'ts'): ?>
                                    <a href="rectools_confirm.php?action=shrink&path=<?php echo rawurlencode($rec['path']); ?>" class="btn shrink" onclick="return confirm('Diese Aufnahme in H.265 schrumpfen?');">Shrink</a>
                                    <a href="rectools_confirm.php?action=cut&path=<?php echo rawurlencode($rec['path']); ?>" class="btn cut" onclick="return confirm('Werbung aus dieser Aufnahme schneiden?');">Cut</a>
                                    <a href="rectools_confirm.php?action=repair&path=<?php echo rawurlencode($rec['path']); ?>" class="btn repair" onclick="return confirm('Diese Aufnahme wirklich tiefgreifend reparieren?');">Repair</a>
                                    <a href="rectools_confirm.php?action=check&path=<?php echo rawurlencode($rec['path']); ?>" class="btn check">Check</a>
                                <?php endif; ?>
                            </div>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    <?php else: ?>
        <div style="background: rgba(255, 255, 255, 0.05); padding: 15px; border-radius: 5px; text-align: center; color: #bbb;">
            Dieser Ordner ist leer oder enthaelt keine VDR-Aufnahmen.
        </div>
    <?php endif; ?>
<script>
function renameRecordingUI(path, currentName) {
    var n = prompt('Neuen Namen eingeben:', currentName);
    if (n && n.trim() !== '') {
        var safeName = encodeURIComponent(n.trim());
        window.location.href = 'rectools_confirm.php?action=rename&path=' + encodeURIComponent(path) + '&name=' + safeName;
    }
}
</script>
</body>
</html>