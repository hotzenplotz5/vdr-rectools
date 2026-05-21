#!/bin/bash
# ==============================================================================
# vdr-rectools - Control Script
# Maintainer: Holger Schvestka <hotzenplotz5@gmx.de>
# Lizenz: GPL-3.0+
# ==============================================================================

# 1. PID-Management
PID_FILE="/var/run/vdr-rectools.pid"

# Stellt sicher, dass das Skript nicht bereits läuft
is_running() {
    if [ -f "$PID_FILE" ]; then
        local PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null; then
            return 0 # Läuft
        fi
    fi
    
    # Fallback: Prüfe den Lock, falls das PID-File (z.B. durch Fehlstart) gelöscht wurde
    local V_DIR="/srv/vdr/video"
    [ -f "/etc/vdr/conf.d/vdr-rectools.conf" ] && . "/etc/vdr/conf.d/vdr-rectools.conf"
    [ -n "${VIDEO_DIR}" ] && V_DIR="${VIDEO_DIR}"
    local L_FILE="$V_DIR/.vdr-rectools.lock"
    if [ -f "$L_FILE" ]; then
        local L_PID=$(cat "$L_FILE" 2>/dev/null)
        if [ -n "$L_PID" ] && ps -p "$L_PID" > /dev/null 2>&1; then
            return 0 # Läuft
        fi
        
        # Fallback 2: Wer hält den File-Lock? (z.B. wenn die Lock-Datei durch 'stop' genullt wurde)
        if command -v fuser >/dev/null 2>&1; then
            if fuser "$L_FILE" >/dev/null 2>&1; then
                return 0
            fi
        fi
    fi
    
    # Fallback 3: Über pgrep (Skript oder verwaistes FFmpeg)
    if pgrep -f "vdr-rectools.*(start|import|repair|cron|repair_single|cut_single|shrink_single)" >/dev/null 2>&1; then return 0; fi
    if pgrep -f "ffmpeg.*/srv/vdr/tmp/staging" >/dev/null 2>&1; then return 0; fi
    
    return 1 # Läuft nicht
}

# 2. Funktionen laden
# Laden der Funktionen (wird nun auch für 'status' benötigt, um show_status aufzurufen)
if [[ "$1" != "stop" ]]; then
    if [ -f /usr/share/vdr-rectools/functions.sh ]; then
        source /usr/share/vdr-rectools/functions.sh
    else
        echo "FEHLER: /usr/share/vdr-rectools/functions.sh nicht gefunden!" >&2
        exit 1
    fi
fi

show_help() {
    cat << EOF
vdr-rectools - Suite zur Verwaltung von VDR-Aufnahmen

BENUTZUNG:
    vdr-rectools [BEFEHL]

BEFEHLE:
    start           Startet einen vollständigen Scan (Import & Cleanup) im Hintergrund.
    import          Startet nur den Import-Prozess für neue Videodateien.
    repair          Startet einen Reparatur-Lauf für alle Aufnahmen.
    repair_single   <Pfad> Repariert eine einzelne Aufnahme (Pfad zum .rec Ordner).
    status          Zeigt den Status laufender Prozesse an.
    diag            Zeigt System-Diagnoseinformationen an.
    stop            Beendet laufende Hintergrundprozesse sauber.
    cron            Simuliert den nächtlichen Timer-Aufruf.
    help, --help    Zeigt diese Hilfe an.

Weitere Informationen finden Sie in der Dokumentation unter /usr/share/doc/vdr-rectools/
EOF
}

show_diagnostics() {
    echo "--- vdr-rectools Diagnose ---"
    echo
    echo "FFmpeg Version:"
    ffmpeg -version | head -n 1
    echo
    echo "Verfügbare Hardwarebeschleuniger:"
    ffmpeg -hide_banner -hwaccels
    echo
    echo "Verfügbare relevante Encoder:"
    ffmpeg -hide_banner -encoders | grep -E 'h264_nvenc|hevc_nvenc|h264_vaapi|hevc_vaapi|h264_qsv|hevc_qsv|libx264|libx265'
    echo
    echo "Grafik-Hardware:"
    lspci | grep -E 'VGA|3D'
    echo
}

interactive_status() {
    trap 'tput cnorm; exit' INT # Cursor bei Abbruch wiederherstellen
    tput civis # Cursor ausblenden
    local V_DIR="/srv/vdr/video"
    [ -f "/etc/vdr/conf.d/vdr-rectools.conf" ] && . "/etc/vdr/conf.d/vdr-rectools.conf"
    [ -n "${VIDEO_DIR}" ] && V_DIR="${VIDEO_DIR}"

    while true; do
        clear
        show_status
        
        local PROMPT_FILE="$V_DIR/.vdr-rectools.prompt"
        if [[ -f "$PROMPT_FILE" ]]; then
            # Sicherheitscheck: Falls der Hintergrundprozess abgestürzt ist, verwaisten Prompt löschen
            if ! is_running; then
                rm -f "$PROMPT_FILE" 2>/dev/null
                continue
            fi
            
            local STATUS=$(cut -d'|' -f1 "$PROMPT_FILE" 2>/dev/null)
            if [[ "$STATUS" == "WAIT" ]]; then
                local P_TITLE=$(cut -d'|' -f2 "$PROMPT_FILE" 2>/dev/null)
                local P_CODEC=$(cut -d'|' -f3 "$PROMPT_FILE" 2>/dev/null)
                echo -e "\n \033[1;31m========================================================\033[0m"
                echo -e " \033[1;33m⚠️  AKTION ERFORDERLICH:\033[0m"
                echo -e " Der Film '\033[1;37m$P_TITLE\033[0m' (Codec: $P_CODEC) muss re-encodiert werden."
                echo -e " Dies kann je nach CPU/Hardware mehrere Stunden dauern."
                echo -e " Möchten Sie den Re-Encode jetzt starten? [\033[1;32mJ\033[0m/\033[1;31mN\033[0m]"
                echo -e " \033[1;31m========================================================\033[0m"
                
                # Endlosschleife: Wartet auf Tastendruck ohne den Bildschirm neu zu zeichnen
                while true; do
                    read -s -n 1 key
                    if [[ "$key" == [jJyY] ]]; then
                        echo "YES|$P_TITLE|$P_CODEC" > "$PROMPT_FILE"
                        echo -e "\n \033[1;32mBestätigt! Starte Re-Encode...\033[0m"
                        sleep 1
                        break
                    elif [[ "$key" == [nN] ]]; then
                        echo "NO|$P_TITLE|$P_CODEC" > "$PROMPT_FILE"
                        echo -e "\n \033[1;31mAbgelehnt! Datei wird übersprungen.\033[0m"
                        sleep 1
                        break
                    elif [[ "$key" == [qQ] ]]; then
                        tput cnorm
                        exit 0
                    fi
                done
                continue
            fi
        fi

        echo -e "\n [ Auto-Refresh alle 2s | [Q] Beenden ]"
        read -t 2 -n 1 key
        [[ "$key" =~ (q|Q) ]] && break
    done
    tput cnorm # Cursor wieder einblenden
}

# 3. Haupt-Logik (Case-Statement)
case "$1" in
    start)
        if is_running; then
            echo "vdr-rectools läuft bereits."
            exit 1
        fi
        echo "Starte vdr-rectools im Hintergrund..."
        (
            run_scan "normal"
        ) &
        ;;

    import)
        if is_running; then
            echo "vdr-rectools läuft bereits."
            exit 1
        fi
        echo "Starte Import im Hintergrund..."
        (
            run_scan "import"
        ) &
        ;;

    repair)
        if is_running; then
            echo "vdr-rectools läuft bereits."
            exit 1
        fi
        echo "Starte Reparatur-Lauf im Hintergrund..."
        (
            run_scan "repair"
        ) &
        ;;
        
    repair_single)
        shift
        process_folder "$1" "repair"
        chown -R vdr:vdr "$1"
        /usr/bin/svdrpsend UPDT >/dev/null 2>&1 || true
        ;;

    check_single)
        shift
        process_folder "$1" "check"
        ;;
        
    sync_single)
        shift
        process_folder "$1" "normal"
        chown -R vdr:vdr "$1"
        /usr/bin/svdrpsend UPDT >/dev/null 2>&1 || true
        ;;

    shrink_single)
        shift
        process_folder "$1" "shrink"
        chown -R vdr:vdr "$1"
        /usr/bin/svdrpsend UPDT >/dev/null 2>&1 || true
        ;;

    cut_single)
        shift
        process_folder "$1" "cut"
        chown -R vdr:vdr "$1"
        /usr/bin/svdrpsend UPDT >/dev/null 2>&1 || true
        ;;

    cron)
        # Wird vom Systemd-Timer aufgerufen
        if [[ "$AUTO_START_NIGHT" -eq 1 ]]; then
            if is_running; then
                echo "Nächtlicher Lauf übersprungen, Prozess läuft bereits." >> "$LOG_FILE"
                exit 1
            fi
            echo "[$(date +%T)] Nächtlicher Lauf gestartet..." >> "$LOG_FILE"
            run_scan "normal"
        else
            echo "[$(date +%T)] AUTO_START_NIGHT ist deaktiviert, keine Aktion." >> "$LOG_FILE"
        fi
        ;;

    status)
        interactive_status
        ;;

    diag)
        show_diagnostics
        exit 0
        ;;

    stop)
        echo "Stoppe vdr-rectools und alle Kindprozesse..."
        
        local V_DIR="/srv/vdr/video"
        [ -f "/etc/vdr/conf.d/vdr-rectools.conf" ] && . "/etc/vdr/conf.d/vdr-rectools.conf"
        [ -n "${VIDEO_DIR}" ] && V_DIR="${VIDEO_DIR}"
        local L_FILE="$V_DIR/.vdr-rectools.lock"
        local P_PROMPT="$V_DIR/.vdr-rectools.prompt"
        local L_LOG="${LOG_FILE:-/var/log/vdr-rectools.log}"
        
        # 1. Alle potenziellen PIDs sammeln
        ALL_PIDS=""
        [ -f "$PID_FILE" ] && ALL_PIDS="$ALL_PIDS $(cat "$PID_FILE" 2>/dev/null)"
        [ -f "$L_FILE" ] && ALL_PIDS="$ALL_PIDS $(cat "$L_FILE" 2>/dev/null)"
        
        SCRIPT_PIDS=$(pgrep -f "vdr-rectools.*(start|import|repair|cron|repair_single|cut_single|shrink_single)" 2>/dev/null)
        ALL_PIDS="$ALL_PIDS $SCRIPT_PIDS"
        
        if command -v fuser >/dev/null 2>&1; then
            FUSER_PIDS=$(fuser "$L_FILE" 2>/dev/null | grep -o '[0-9]\+')
            ALL_PIDS="$ALL_PIDS $FUSER_PIDS"
        fi
        
        ALL_PIDS=$(echo "$ALL_PIDS" | tr ' ' '\n' | awk 'NF' | sort -u)
        
        # 2. Kill-Tree aufbauen
        if [ -n "$ALL_PIDS" ]; then
            get_descendants() {
                local parent=$1
                for child in $(pgrep -P "$parent" 2>/dev/null); do
                    get_descendants "$child"
                    echo "$child"
                done
            }
            FULL_TREE=""
            for p in $ALL_PIDS; do
                if ps -p "$p" > /dev/null 2>&1; then
                    FULL_TREE="$FULL_TREE $p $(get_descendants "$p")"
                fi
            done
            FULL_TREE=$(echo "$FULL_TREE" | tr ' ' '\n' | awk 'NF' | sort -u)
            
            if [ -n "$FULL_TREE" ]; then
                for p in $FULL_TREE; do
                    kill -15 "$p" 2>/dev/null
                done
                sleep 2
                for p in $FULL_TREE; do
                    if ps -p "$p" > /dev/null 2>&1; then
                        kill -9 "$p" 2>/dev/null
                    fi
                done
            fi
        fi
        
        # 3. Hardcore-Fallback: Verwaiste FFmpeg-Prozesse explizit abschießen
        if pgrep -f "(ffmpeg|ffprobe).*/srv/vdr/tmp/staging" >/dev/null 2>&1; then
            echo "Erzwinge Stopp für verwaiste FFmpeg-Prozesse..."
            pkill -9 -f "(ffmpeg|ffprobe).*/srv/vdr/tmp/staging" 2>/dev/null || true
        fi
        
        # 4. Aufräumen
        rm -f "$PID_FILE" "$P_PROMPT" "$V_DIR/.vdr-rectools.state" "$V_DIR/.vdr-rectools.duration" 2>/dev/null || true
        truncate -s 0 "$V_DIR/.vdr-rectools.lock" 2>/dev/null || true
        
        # 5. Log-Feedback für den User
        echo "[$(date +%T)] INFO: vdr-rectools wurde manuell gestoppt (Abbruch)." >> "$L_LOG"
        
        echo "Erfolgreich gestoppt."
        ;;

    help|--help|-h)
        show_help
        exit 0
        ;;

    *)
        echo "Unbekannter Befehl: $1" >&2
        show_help
        exit 1
        ;;
esac

exit 0
