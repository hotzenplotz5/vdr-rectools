<?php
$conf_file = '/etc/vdr/conf.d/vdr-rectools.conf';
$import_dir = '/srv/vdr/import';
$language = 'de';
if (file_exists($conf_file)) {
    $lines = @file($conf_file) ?: [];
    foreach ($lines as $line) {
        if (preg_match('/^IMPORT_DIR=["\']?(.*?)["\']?$/', trim($line), $m)) $import_dir = $m[1];
        if (preg_match('/^LANGUAGE=["\']?(.*?)["\']?$/', trim($line), $m)) $language = $m[1];
    }
}

$lang_file = __DIR__ . "/lang/{$language}.json";
if (!file_exists($lang_file)) $lang_file = __DIR__ . "/lang/de.json";

$translations = [];
$debug_lang = "";
if (file_exists($lang_file)) {
    $json_content = (string)@file_get_contents($lang_file);
    $json_content = preg_replace('/^\xEF\xBB\xBF/', '', $json_content); // Unsichtbares Windows-BOM entfernen
    $decoded = json_decode($json_content, true);
    if (is_array($decoded)) $translations = $decoded;
    else $debug_lang = "JSON Error: " . json_last_error_msg();
} else {
    $debug_lang = "Datei fehlt: " . basename($lang_file);
}

function __($key, ...$args) {
    global $translations;
    $text = isset($translations[$key]) ? $translations[$key] : $key;
    return !empty($args) ? vsprintf($text, $args) : $text;
}

// Aktuelle Pfade auslesen (Standard: Quelle = Root, Ziel = Import_Dir)
$src = isset($_GET['src']) ? realpath($_GET['src']) : '/';
if (!$src || !is_dir($src)) $src = '/';

$dst = isset($_GET['dst']) ? realpath($_GET['dst']) : $import_dir;
if (!$dst || !is_dir($dst)) $dst = $import_dir;

$msg = $debug_lang ? "<div class='msg msg-err'>⚠️ Sprach-System Fehler: $debug_lang</div>" : '';

// Dateioperationen verarbeiten
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['download_file'])) {
        $file = $_POST['download_file'];
        if (file_exists($file) && is_file($file)) {
            while (ob_get_level()) ob_end_clean();
            header('Content-Description: File Transfer');
            header('Content-Type: application/octet-stream');
            header('Content-Disposition: attachment; filename="' . basename($file) . '"');
            header('Expires: 0');
            header('Cache-Control: must-revalidate');
            header('Pragma: public');
            header('Content-Length: ' . filesize($file));
            $handle = @fopen($file, 'rb');
            if ($handle) {
                while (!feof($handle) && connection_status() == 0) {
                    echo fread($handle, 1048576);
                    flush();
                }
                fclose($handle);
                exit;
            } else {
                $msg = "<div class='msg msg-err'>" . __('err_read_file') . "</div>";
            }
        } else {
            $msg = "<div class='msg msg-err'>" . __('err_file_not_found') . "</div>";
        }
    } elseif (empty($_POST) && empty($_FILES) && isset($_SERVER['CONTENT_LENGTH']) && $_SERVER['CONTENT_LENGTH'] > 0) {
        $msg = "<div class='msg msg-err'>" . __('err_upload_too_large') . "</div>";
    } elseif (isset($_POST['single_move'])) {
        $file = $_POST['single_move'];
        $filename = basename($file);
        $target = $dst . '/' . $filename;
        
        if (!file_exists($file)) {
            $msg = "<div class='msg msg-err'>" . __('err_src_not_found') . "</div>";
        } elseif (file_exists($target)) {
            $msg = "<div class='msg msg-err'>" . __('err_target_exists', $filename) . "</div>";
        } else {
            // Verschieben (kann bei großen Dateien über Partitionsgrenzen hinweg dauern)
            if (@rename($file, $target)) {
                $msg = "<div class='msg msg-ok'>" . __('ok_file_moved', $filename) . "</div>";
            } else {
                $msg = "<div class='msg msg-err'>" . __('err_move_failed') . "</div>";
            }
        }
    } elseif (isset($_POST['bulk_move']) && !empty($_POST['files'])) {
        $success = 0; $errors = 0;
        foreach ($_POST['files'] as $file) {
            $filename = basename($file);
            $target = $dst . '/' . $filename;
            if (file_exists($file) && !file_exists($target) && @rename($file, $target)) {
                $success++;
            } else {
                $errors++;
            }
        }
        if ($success > 0 && $errors === 0) {
            $msg = "<div class='msg msg-ok'>" . __('ok_bulk_move', $success) . "</div>";
        } elseif ($success > 0 && $errors > 0) {
            $msg = "<div class='msg msg-err'>" . __('warn_bulk_move', $success, $errors) . "</div>";
        } else {
            $msg = "<div class='msg msg-err'>" . __('err_bulk_move') . "</div>";
        }
    } elseif (isset($_POST['bulk_delete']) && !empty($_POST['files'])) {
        $success = 0; $errors = 0;
        foreach ($_POST['files'] as $file) {
            if (file_exists($file) && is_file($file)) {
                if (@unlink($file)) {
                    $success++;
                } else {
                    $errors++;
                }
            }
        }
        if ($success > 0 && $errors === 0) {
            $msg = "<div class='msg msg-ok'>" . __('ok_bulk_delete', $success) . "</div>";
        } elseif ($success > 0 && $errors > 0) {
            $msg = "<div class='msg msg-err'>" . __('warn_bulk_delete', $success, $errors) . "</div>";
        } else {
            $msg = "<div class='msg msg-err'>" . __('err_bulk_delete') . "</div>";
        }
    } elseif (isset($_POST['action']) && $_POST['action'] === 'mkdir' && !empty($_POST['dirname'])) {
        $newdir = $dst . '/' . basename($_POST['dirname']);
        if (!file_exists($newdir)) {
            if (@mkdir($newdir, 0775)) {
                $msg = "<div class='msg msg-ok'>" . __('ok_dir_created', basename($_POST['dirname'])) . "</div>";
            } else {
                $msg = "<div class='msg msg-err'>" . __('err_dir_create') . "</div>";
            }
        } else {
            $msg = "<div class='msg msg-err'>" . __('err_dir_exists') . "</div>";
        }
    } elseif (isset($_POST['action']) && $_POST['action'] === 'upload') {
        if (!isset($_FILES['upload_file'])) {
            $msg = "<div class='msg msg-err'>" . __('err_upload_no_file') . "</div>";
        } else {
            $success = 0; $errors = 0; $err_details = [];
            $files = $_FILES['upload_file'];
            $is_multi = is_array($files['name']);
            $count = $is_multi ? count($files['name']) : 1;
            for ($i = 0; $i < $count; $i++) {
                $file_tmp = $is_multi ? $files['tmp_name'][$i] : $files['tmp_name'];
                $file_name = basename($is_multi ? $files['name'][$i] : $files['name']);
                $error_code = $is_multi ? $files['error'][$i] : $files['error'];
                if ($error_code !== UPLOAD_ERR_OK) {
                    if ($error_code !== UPLOAD_ERR_NO_FILE) {
                        $errors++;
                        $err_details[] = "$file_name (Code: $error_code)";
                    }
                    continue;
                }
                if (is_uploaded_file($file_tmp)) {
                    if (@move_uploaded_file($file_tmp, $dst . '/' . $file_name)) {
                        $success++;
                    } else {
                        $errors++;
                        $e = error_get_last();
                        $err_details[] = "$file_name (" . ($e ? $e['message'] : 'Schreibfehler') . ")";
                    }
                } else {
                    $errors++;
                }
            }
            if ($success > 0 && $errors === 0) {
                $msg = "<div class='msg msg-ok'>" . __('ok_upload', $success) . "</div>";
            } elseif ($success > 0 && $errors > 0) {
                $msg = "<div class='msg msg-err'>" . __('warn_upload', $success, $errors, htmlspecialchars(implode(', ', $err_details))) . "</div>";
            } elseif ($errors > 0) {
                $msg = "<div class='msg msg-err'>" . __('err_upload', htmlspecialchars(implode(', ', $err_details))) . "</div>";
            }
        }
    } elseif (isset($_POST['delete_file'])) {
        $file = $_POST['delete_file'];
        if (file_exists($file) && is_file($file)) {
            if (@unlink($file)) {
                $msg = "<div class='msg msg-ok'>" . __('ok_file_deleted', basename($file)) . "</div>";
            } else {
                $msg = "<div class='msg msg-err'>" . __('err_delete_failed') . "</div>";
            }
        } else {
            $msg = "<div class='msg msg-err'>" . __('err_not_file') . "</div>";
        }
    } elseif (isset($_POST['delete_dir'])) {
        $dir = $_POST['delete_dir'];
        if (is_dir($dir)) {
            if (@rmdir($dir)) {
                $msg = "<div class='msg msg-ok'>" . __('ok_dir_deleted', basename($dir)) . "</div>";
            } else {
                $msg = "<div class='msg msg-err'>" . __('err_dir_delete_failed') . "</div>";
            }
        } else {
            $msg = "<div class='msg msg-err'>" . __('err_dir_not_found') . "</div>";
        }
        } elseif (isset($_POST['recover_file'])) {
            $file = $_POST['recover_file'];
            if (file_exists($file) && is_file($file)) {
                $clean = preg_replace('/\.(skipped|pc_encode|duplicate)\./', '.', $file);
                $clean = preg_replace('/\.(skipped|pc_encode|duplicate)$/', '', $clean);
                if (@rename($file, $clean)) {
                    $msg = "<div class='msg msg-ok'>" . __('ok_status_removed') . "</div>";
                } else {
                    $msg = "<div class='msg msg-err'>" . __('err_status_remove') . "</div>";
                }
            }
        } elseif (isset($_POST['manual_skipped'])) {
            $file = $_POST['manual_skipped'];
            if (file_exists($file) && is_file($file)) {
                $clean = preg_replace('/\.skipped\./', '.', $file);
                $clean = preg_replace('/\.skipped$/', '', $clean);
                $info = pathinfo($clean);
                $target = $info['dirname'] . '/' . $info['filename'] . '.pc_encode';
                if (isset($info['extension'])) {
                    $target .= '.' . $info['extension'];
                }
                if (@rename($file, $target)) {
                    $msg = "<div class='msg msg-ok'>" . __('ok_pc_delegate') . "</div>";
                } else {
                    $msg = "<div class='msg msg-err'>" . __('err_pc_delegate') . "</div>";
                }
            }
    }
    
    // HTML-Dashboard nach jeder Datei-Operation zwingend sofort neu rendern
    if (!isset($_POST['download_file'])) {
        @exec('/bin/bash /usr/bin/vdr-rectools update-html ' . escapeshellarg($language) . ' >/dev/null 2>&1');
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
                if ($dir !== '/') $dirs[] = ['name' => __('dir_up'), 'path' => dirname($dir)];
                continue;
            }
            if (is_dir($path)) $dirs[] = ['name' => '📁 ' . $item, 'path' => $path];
            else {
                $size = @filesize($path);
                $size_str = $size >= 1073741824 ? round($size / 1073741824, 2) . ' GB' : ($size >= 1048576 ? round($size / 1048576, 2) . ' MB' : round($size / 1024, 2) . ' KB');
                $files[] = ['name' => '📄 ' . $item, 'path' => $path, 'raw_path' => $path, 'size' => $size_str];
            }
        }
    }
    return ['dirs' => $dirs, 'files' => $files];
}

$src_contents = get_dir_contents($src);
$dst_contents = get_dir_contents($dst);
?>
<!DOCTYPE html>
<html lang="<?= htmlspecialchars($language) ?>">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= __('title_explorer') ?></title>
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
        <h2><?= __('title_explorer') ?></h2>
        <?= $msg ?>
        
        <div class="split-view">
            <!-- LINKE SEITE (Quelle) -->
            <div class="pane">
                <h3><?= __('header_source') ?></h3>
                
                <div style="background: rgba(33, 150, 243, 0.1); border: 1px solid #2196F3; padding: 15px; border-radius: 8px; margin-bottom: 15px;">
                    <h4 style="margin-top:0; color:#2196F3; margin-bottom: 10px;"><?= __('header_upload') ?></h4>
                    <form id="uploadForm" method="POST" enctype="multipart/form-data" style="display:flex; flex-wrap: wrap; gap:10px; align-items: center;">
                        <input type="hidden" name="action" value="upload">
                        <input type="file" id="uploadFile" name="upload_file[]" multiple required style="color:#fff; flex-grow: 1;">
                        <button type="submit" id="uploadBtn" class="btn btn-move" style="margin:0; padding: 8px 15px; font-size: 14px;"><?= __('btn_upload') ?></button>
                    </form>
                    <div id="progressContainer" style="display:none; margin-top: 15px; background: #333; border-radius: 5px; width: 100%; height: 25px; overflow: hidden; box-shadow: inset 0 1px 3px rgba(0,0,0,0.5);">
                        <div id="progressBar" style="background: #2196F3; width: 0%; height: 100%; text-align: center; color: white; line-height: 25px; font-size: 14px; font-weight: bold; white-space: nowrap;">0%</div>
                    </div>
                    <div style="color:#aaa; font-size: 0.85em; margin-top: 8px;"><?= __('desc_upload') ?></div>
                </div>
                
                <div class="path-bar"><?= htmlspecialchars($src) ?></div>
                <div class="list">
                <?php if (!empty($src_contents['files'])): ?>
                <form method="POST" style="margin: 0;">
                    <div style="background: rgba(20, 20, 20, 0.95); padding: 12px 10px; border-radius: 6px; margin-bottom: 15px; display: flex; justify-content: space-between; align-items: center; position: sticky; top: -10px; z-index: 10; border-bottom: 1px solid #444; box-shadow: 0 4px 6px rgba(0,0,0,0.5);">
                        <label style="cursor: pointer;"><input type="checkbox" id="selectAllChk" onclick="document.querySelectorAll('.file-chk').forEach(c => c.checked = this.checked); if(typeof updateSelectionStorage === 'function') updateSelectionStorage();"> <strong><?= __('lbl_select_all') ?></strong></label>
                        <div>
                            <button type="submit" name="bulk_delete" value="1" class="btn btn-move" style="margin: 0; background: #F44336; color: white;" onclick="return confirm('<?= __('confirm_bulk_delete') ?>');"><?= __('btn_bulk_delete') ?></button>
                            <button type="submit" name="bulk_move" value="1" class="btn btn-move" style="margin: 0; background: #FF9800; color: #000;" onclick="return confirm('<?= __('confirm_bulk_move') ?>');"><?= __('btn_bulk_move') ?></button>
                        </div>
                    </div>
                <?php endif; ?>

                    <?php foreach ($src_contents['dirs'] as $d): ?>
                        <div class="item" style="display: flex; justify-content: space-between; align-items: center;">
                            <a href="?src=<?= urlencode($d['path']) ?>&dst=<?= urlencode($dst) ?>" style="flex-grow: 1;"><strong><?= htmlspecialchars($d['name']) ?></strong></a>
                        </div>
                    <?php endforeach; ?>
                
                    <?php foreach ($src_contents['files'] as $f): ?>
                        <div class="item">
                        <label style="display: flex; align-items: center; cursor: pointer; flex-grow: 1; overflow: hidden;">
                            <input type="checkbox" name="files[]" value="<?= htmlspecialchars($f['raw_path']) ?>" class="file-chk" style="margin-right: 10px;" onchange="if(typeof updateSelectionStorage === 'function') updateSelectionStorage();">
                            <span style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                                <?= htmlspecialchars($f['name']) ?> <span style="color: #666; font-size: 0.85em; margin-left: 5px;">(<?= $f['size'] ?>)</span>
                            </span>
                        </label>
                        <?php if (preg_match('/\.(skipped|pc_encode|duplicate)(\.|$)/i', $f['name'])): ?>
                            <button type="submit" name="recover_file" value="<?= htmlspecialchars($f['raw_path']) ?>" class="btn btn-move" style="background: #2196F3; color: white;" title="<?= __('title_recover') ?>"><?= __('btn_recover') ?></button>
                        <?php endif; ?>
                        <?php if (strpos($f['name'], '.skipped') !== false): ?>
                            <button type="submit" name="manual_skipped" value="<?= htmlspecialchars($f['raw_path']) ?>" class="btn btn-move" style="background: #9C27B0; color: white;" title="<?= __('title_delegate') ?>" onclick="return confirm('<?= __('confirm_delegate') ?>');"><?= __('btn_delegate') ?></button>
                        <?php endif; ?>
                        <button type="submit" name="download_file" value="<?= htmlspecialchars($f['raw_path']) ?>" class="btn btn-move" style="background: #4CAF50; color: white;" formtarget="_blank" title="<?= __('title_download') ?>"><?= __('btn_download') ?></button>
                        <button type="submit" name="delete_file" value="<?= htmlspecialchars($f['raw_path']) ?>" class="btn btn-move" style="background: #F44336; color: white;" onclick="return confirm('<?= __('confirm_delete_file') ?>');"><?= __('btn_delete') ?></button>
                        <button type="submit" name="single_move" value="<?= htmlspecialchars($f['raw_path']) ?>" class="btn btn-move" onclick="return confirm('<?= __('confirm_single_move') ?>');"><?= __('btn_single_move') ?></button>
                        </div>
                    <?php endforeach; ?>
                <?php if (!empty($src_contents['files'])): ?>
                </form>
                <?php endif; ?>
                </div>
            </div>
            
            <!-- RECHTE SEITE (Ziel) -->
            <div class="pane">
                <h3><?= __('header_target') ?></h3>
                <div class="path-bar"><?= htmlspecialchars($dst) ?></div>
                <div class="list">
                    <?php foreach ($dst_contents['dirs'] as $d): ?>
                        <div class="item" style="display: flex; justify-content: space-between; align-items: center;">
                            <a href="?src=<?= urlencode($src) ?>&dst=<?= urlencode($d['path']) ?>" style="flex-grow: 1;"><strong><?= htmlspecialchars($d['name']) ?></strong></a>
                            <?php if ($d['name'] !== __('dir_up')): ?>
                            <form method="POST" style="margin: 0;">
                                <button type="submit" name="delete_dir" value="<?= htmlspecialchars($d['path']) ?>" class="btn btn-move" style="background: #F44336; color: white; padding: 2px 8px;" onclick="return confirm('<?= __('confirm_delete_dir') ?>');"><?= __('btn_delete') ?></button>
                            </form>
                            <?php endif; ?>
                        </div>
                    <?php endforeach; ?>
                    <?php foreach ($dst_contents['files'] as $f): ?>
                        <div class="item" style="color: #888; display: flex; justify-content: space-between; align-items: center;">
                            <span style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"><?= htmlspecialchars($f['name']) ?> <span style="color: #555; font-size: 0.85em; margin-left: 5px;">(<?= $f['size'] ?>)</span></span>
                            <form method="POST" style="margin: 0;">
                                <?php if (preg_match('/\.(skipped|pc_encode|duplicate)(\.|$)/i', $f['name'])): ?>
                                    <button type="submit" name="recover_file" value="<?= htmlspecialchars($f['raw_path']) ?>" class="btn btn-move" style="background: #2196F3; color: white; padding: 2px 8px;" title="<?= __('title_recover') ?>"><?= __('btn_recover_text') ?></button>
                                <?php endif; ?>
                                <?php if (strpos($f['name'], '.skipped') !== false): ?>
                                    <button type="submit" name="manual_skipped" value="<?= htmlspecialchars($f['raw_path']) ?>" class="btn btn-move" style="background: #9C27B0; color: white; padding: 2px 8px;" title="<?= __('title_delegate') ?>" onclick="return confirm('<?= __('confirm_delegate') ?>');"><?= __('btn_delegate_text') ?></button>
                                <?php endif; ?>
                                <button type="submit" name="download_file" value="<?= htmlspecialchars($f['raw_path']) ?>" class="btn btn-move" style="background: #4CAF50; color: white; padding: 2px 8px;" formtarget="_blank" title="<?= __('title_download') ?>"><?= __('btn_download') ?></button>
                                <button type="submit" name="delete_file" value="<?= htmlspecialchars($f['raw_path']) ?>" class="btn btn-move" style="background: #F44336; color: white; padding: 2px 8px;" onclick="return confirm('<?= __('confirm_delete_file_dst') ?>');"><?= __('btn_delete') ?></button>
                            </form>
                        </div>
                    <?php endforeach; ?>
                </div>
                <form method="POST" class="mkdir-form">
                    <input type="hidden" name="action" value="mkdir">
                    <input type="text" name="dirname" placeholder="<?= __('placeholder_new_dir') ?>" required>
                    <button type="submit" class="btn" style="margin-top: 0;"><?= __('btn_mkdir') ?></button>
                </form>
            </div>
        </div>
        
        <a href="rectools.html?t=<?= time() ?>" class="btn btn-back"><?= __('btn_back') ?></a>
    </div>
    <script>
        const EXPLORER_STORAGE_KEY = 'vdr_rectools_explorer_selection';

        function updateSelectionStorage() {
            var checked = [];
            document.querySelectorAll('.file-chk:checked').forEach(function(c) {
                checked.push(c.value);
            });
            sessionStorage.setItem(EXPLORER_STORAGE_KEY, JSON.stringify(checked));
        }

        document.addEventListener("DOMContentLoaded", function() {
            // Checkbox-Status wiederherstellen (beim Navigieren durch Ordner)
            try {
                var saved = JSON.parse(sessionStorage.getItem(EXPLORER_STORAGE_KEY) || '[]');
                document.querySelectorAll('.file-chk').forEach(function(c) {
                    if (saved.indexOf(c.value) !== -1) {
                        c.checked = true;
                    }
                });
                
                // "Alle auswählen" Haken wiederherstellen, falls alle Einzeldateien markiert sind
                var allBoxes = document.querySelectorAll('.file-chk');
                if (allBoxes.length > 0 && document.querySelectorAll('.file-chk:checked').length === allBoxes.length) {
                    var selectAll = document.getElementById('selectAllChk');
                    if (selectAll) selectAll.checked = true;
                }
            } catch(e) {}

            var uploadForm = document.getElementById('uploadForm');
            if (uploadForm) {
                uploadForm.addEventListener('submit', function(e) {
                    e.preventDefault(); // Verhindert das normale Neuladen der Seite
                    var fileInput = document.getElementById('uploadFile');
                    if(fileInput.files.length === 0) return;

                    document.getElementById('uploadBtn').innerText = '<?= __('upload_wait') ?>';
                    document.getElementById('uploadBtn').style.background = '#555';
                    document.getElementById('uploadBtn').style.cursor = 'not-allowed';
                    document.getElementById('uploadBtn').disabled = true;
                    
                    var pContainer = document.getElementById('progressContainer');
                    var pBar = document.getElementById('progressBar');
                    pContainer.style.display = 'block';
                    
                    var formData = new FormData(uploadForm);
                    var xhr = new XMLHttpRequest();
                    
                    xhr.open('POST', window.location.href, true);
                    xhr.upload.onprogress = function(e) {
                        if (e.lengthComputable) {
                            var percent = Math.round((e.loaded / e.total) * 100);
                            var upload_text = '<?= __('upload_running', 'PERCENT_PLACEHOLDER') ?>';
                            pBar.style.width = percent + '%';
                            pBar.innerHTML = upload_text.replace('PERCENT_PLACEHOLDER', percent);
                        }
                    };
                    xhr.onload = function() { document.open(); document.write(xhr.responseText); document.close(); };
                    xhr.onerror = function() { alert('<?= __('upload_network_err') ?>'); window.location.reload(); };
                    xhr.send(formData);
                });
            }
        });
    </script>
</body>
</html>