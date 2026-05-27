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

$real_video_dir = realpath($video_dir);
$recordings = [];
$counts = ['total' => 0, 'pes' => 0, 'ts' => 0, 'unknown' => 0];

if ($real_video_dir && is_dir($real_video_dir)) {
    try {
        $dir_iterator = new RecursiveDirectoryIterator($real_video_dir, RecursiveDirectoryIterator::SKIP_DOTS | RecursiveDirectoryIterator::UNIX_PATHS);
        $iterator = new RecursiveIteratorIterator($dir_iterator, RecursiveIteratorIterator::SELF_FIRST);
        
        foreach ($iterator as $file) {
            if ($file->isDir() && substr($file->getFilename(), -4) === '.rec') {
                $rec_path = $file->getRealPath();
                $rel_path = substr($rec_path, strlen($real_video_dir) + 1);
                
                $title = basename(dirname($rec_path));
                $title = str_replace('_', ' ', $title);
                
                $has_pes = false;
                $has_ts = false;
                
                if ($dh = @opendir($rec_path)) {
                    while (($item = readdir($dh)) !== false) {
                        if (preg_match('/^[0-9]{3}\.vdr$/', $item)) {
                            $has_pes = true;
                            break; // PES hat Prio, wir koennen die Schleife abbrechen
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
                    'rel_path' => $rel_path,
                    'title' => $title,
                    'status' => $status,
                    'sort' => $sort
                ];
            }
        }
    } catch (Exception $e) {
        // Ignorieren falls Berechtigungsfehler in tieferen Strukturen auftreten
    }
}

usort($recordings, function($a, $b) {
    if ($a['sort'] !== $b['sort']) return $a['sort'] - $b['sort'];
    return strcasecmp($a['title'], $b['title']);
});
?>
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>VDR-Rectools - PES Explorer</title>
    <style>
        body { background-color: #121212; color: #fff; font-family: Arial, sans-serif; padding: 20px; max-width: 1000px; margin: 0 auto; }
        a.btn { display: inline-block; background: #00BCD4; color: white; padding: 6px 12px; text-decoration: none; border-radius: 4px; font-weight: bold; text-align: center; font-size: 0.9em; }
        a.btn:hover { filter: brightness(1.1); }
        a.btn.global { background: #FF9800; margin-bottom: 20px; display: block; width: fit-content; }
        a.btn.back { background: #555; margin-bottom: 20px; }
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
    <h2>🔄 PES-Aufnahmen Explorer</h2>
    <p style="color: #ccc;">Hier werden alle VDR-Aufnahmen angezeigt. Alte PES-Aufnahmen k&ouml;nnen gezielt konvertiert werden.</p>
    
    <a href="rectools.html" class="btn back">🔙 Zurueck zum Dashboard</a>
    
    <div class="stats">
        <div class="stat-box"><div class="stat-num"><?php echo $counts['total']; ?></div>Gesamt</div>
        <div class="stat-box" style="color: #FF9800;"><div class="stat-num"><?php echo $counts['pes']; ?></div>PES</div>
        <div class="stat-box" style="color: #4CAF50;"><div class="stat-num"><?php echo $counts['ts']; ?></div>TS</div>
        <div class="stat-box" style="color: #9E9E9E;"><div class="stat-num"><?php echo $counts['unknown']; ?></div>Unbekannt</div>
    </div>
    
    <?php if ($counts['pes'] > 0): ?>
        <a href="rectools_confirm.php?action=pes2ts" class="btn global" onclick="return confirm('Wirklich ALLE gefundenen PES-Aufnahmen konvertieren? Das kann je nach Archivgroesse eine Weile dauern.');">⚡ Alle <?php echo $counts['pes']; ?> PES-Aufnahmen konvertieren</a>
    <?php endif; ?>
        
    <?php if (count($recordings) > 0): ?>
        <table>
            <thead>
                <tr>
                    <th>Titel & Pfad</th>
                    <th>Status</th>
                    <th>Aktion</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($recordings as $rec): ?>
                    <tr>
                        <td>
                            <div class="title"><?php echo htmlspecialchars($rec['title']); ?></div>
                            <div class="path">📂 <?php echo htmlspecialchars($rec['rel_path']); ?></div>
                        </td>
                        <td>
                            <?php if ($rec['status'] === 'pes'): ?>
                                <span class="status-pes">Alte PES-Aufnahme</span>
                            <?php elseif ($rec['status'] === 'ts'): ?>
                                <span class="status-ts">TS-Aufnahme</span>
                            <?php else: ?>
                                <span class="status-unknown">Unbekannt</span>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?php if ($rec['status'] === 'pes'): ?>
                                <a href="rectools_confirm.php?action=pes2ts&path=<?php echo rawurlencode($rec['path']); ?>" class="btn">Diese Aufnahme konvertieren</a>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    <?php else: ?>
        <div style="background: rgba(255, 255, 255, 0.05); padding: 15px; border-radius: 5px; text-align: center; color: #bbb;">
            Es wurden keine VDR-Aufnahmen (.rec) im Videoverzeichnis gefunden.
        </div>
    <?php endif; ?>
</body>
</html>