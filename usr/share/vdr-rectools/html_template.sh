#!/bin/bash
# ==============================================================================
# vdr-rectools - HTML Dashboard Template
# ==============================================================================

render_dashboard_html() {
    local OUT_FILE="$1"
    cat <<EOF > "$OUT_FILE"
<!DOCTYPE html>
<html lang="${LANGUAGE:-de}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${TXT_DASH_TITLE:-🎬 VDR-Rectools Dashboard}</title>
    <style>
        body { $BODY_CSS color: #e0e0e0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; }
        .container { max-width: 800px; margin: 0 auto; background: rgba(30, 30, 30, 0.6); backdrop-filter: blur(15px); -webkit-backdrop-filter: blur(15px); padding: 20px; border-radius: 10px; box-shadow: 0 10px 30px rgba(0,0,0,0.8); border: 1px solid rgba(255,255,255,0.05); }
        h2 { border-bottom: 2px solid #333; padding-bottom: 10px; margin-top: 0; color: #fff; }
        .status-box { background: rgba(0, 0, 0, 0.4); padding: 15px; border-radius: 8px; margin-bottom: 20px; font-size: 1.1em; border: 1px solid rgba(255,255,255,0.1); }
        .log-box { background: rgba(0, 0, 0, 0.6); padding: 15px; border-radius: 8px; font-family: 'Consolas', 'Courier New', monospace; font-size: 0.9em; height: 220px; overflow-y: auto; white-space: nowrap; line-height: 1.5; border: 1px solid rgba(255,255,255,0.1); }
        .footer { margin-top: 20px; font-size: 0.8em; color: #666; text-align: right; }
    </style>
</head>
<body>
    <div class="container">
        <h2>${TXT_DASH_TITLE:-🎬 VDR-Rectools - Live Dashboard}</h2>
        <div class="status-box">
            <strong>${TXT_DASH_STATUS:-Status:}</strong> $STATUS_TEXT
            $ACTION_HTML
            $PROGRESS_HTML
            $PROMPT_HTML
            $SKIPPED_HTML
            $PC_ENCODE_HTML
            $SESSION_HTML
        </div>
        <div class="status-box" style="font-size: 0.95em;">
            <strong>${TXT_DASH_DISK:-💾 Festplatte:}</strong> $DISK_HTML
        </div>
        <h3 style="color: #bbb; font-size: 1.1em; margin-bottom: 10px;">${TXT_DASH_LOG_TITLE:-📋 Letzte Log-Aktivitäten}</h3>
        <div class="log-box">$LOG_HTML</div>
        <div class="footer">${TXT_DASH_FOOTER:-Auto-Refresh (5s) | Letzte Aktualisierung:} $(date +"%d.%m.%Y %H:%M:%S")</div>
    </div>
    <script>
        setTimeout(function() {
            window.location.replace(window.location.pathname + '?t=' + new Date().getTime());
        }, 5000);
    </script>
</body>
</html>
EOF
}