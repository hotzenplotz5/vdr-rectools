<?php
$video_dir = '/srv/vdr/video';

// Schneller System-Aufruf fuer find: Sucht nach allen .vdr Dateien und liefert nur das uebergeordnete Verzeichnis
$cmd = "find " . escapeshellarg($video_dir) . " -type f -name '[0-9][0-9][0-9].vdr' -printf '%h\n' | sort -u 2>/dev/null";
$output = shell_exec($cmd);

$rec_folders = [];
if ($output) {
    $lines = explode("\n", trim($output));
    foreach ($lines as $line) {
        if (!empty($line) && is_dir($line)) {
            $rec_folders[] = $line;
        }
    }
}
?>
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>VDR-Rectools - PES Explorer</title>
    <style>
        body { background-color: #121212; color: #fff; font-family: Arial, sans-serif; padding: 20px; max-width: 900px; margin: 0 auto; }
        a.btn { display: inline-block; background: #00BCD4; color: white; padding: 8px 15px; text-decoration: none; border-radius: 4px; font-weight: bold; text-align: center; }
        a.btn:hover { filter: brightness(1.1); }
        a.btn.global { background: #FF9800; margin-bottom: 20px; display: block; width: fit-content; }
        a.btn.back { background: #555; margin-bottom: 20px; }
        ul { list-style: none; padding: 0; }
        li { background: rgba(255,255,255,0.05); margin-bottom: 10px; padding: 15px; border-radius: 5px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 15px; border: 1px solid rgba(255,255,255,0.1); }
        .path { word-break: break-all; color: #aaa; font-size: 0.9em; margin-top: 5px; }
        .title { font-size: 1.1em; font-weight: bold; color: #4CAF50; }
    </style>
</head>
<body>
    <h2>🔄 PES-Aufnahmen Explorer</h2>
    <p style="color: #ccc;">Hier werden alle veralteten VDR-Aufnahmen aufgelistet, die noch im alten PES-Format (*.vdr) vorliegen und in das moderne TS-Format migriert werden koennen.</p>
    
    <a href="rectools.html" class="btn back">🔙 Zurueck zum Dashboard</a>
    
    <?php if (count($rec_folders) > 0): ?>
        <a href="rectools_confirm.php?action=pes2ts" class="btn global" onclick="return confirm('Wirklich ALLE gefundenen Aufnahmen konvertieren? Das kann je nach Archivgroesse eine Weile dauern.');">⚡ Alle <?php echo count($rec_folders); ?> gefundenen konvertieren</a>
        
        <ul>
            <?php foreach ($rec_folders as $folder): 
                $title = basename(dirname($folder));
                $title = str_replace('_', ' ', $title);
                $rel_path = str_replace($video_dir . '/', '', $folder);
            ?>
                <li>
                    <div style="flex-grow: 1;">
                        <div class="title"><?php echo htmlspecialchars($title); ?></div>
                        <div class="path">📂 <?php echo htmlspecialchars($rel_path); ?></div>
                    </div>
                    <a href="rectools_confirm.php?action=pes2ts&path=<?php echo urlencode($folder); ?>" class="btn">Diese Aufnahme konvertieren</a>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php else: ?>
        <div style="background: rgba(76, 175, 80, 0.1); border: 1px solid #4CAF50; padding: 15px; border-radius: 5px; color: #4CAF50; font-weight: bold;">
            🎉 Hervorragend! Dein Archiv ist sauber. Es wurden keine alten PES-Aufnahmen mehr gefunden.
        </div>
    <?php endif; ?>
</body>
</html>