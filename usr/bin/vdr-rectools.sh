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
        if fuser "$L_FILE" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
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
                
                read -n 1 -t 2 key
                if [[ "$key" == [jJyY] ]]; then
                    echo "YES|$P_TITLE|$P_CODEC" > "$PROMPT_FILE"
                    echo -e "\n \033[1;32mBestätigt! Starte Re-Encode...\033[0m"
                    sleep 1
                    continue
                elif [[ "$key" == [nN] ]]; then
                    echo "NO|$P_TITLE|$P_CODEC" > "$PROMPT_FILE"
                    echo -e "\n \033[1;31mAbgelehnt! Datei wird übersprungen.\033[0m"
                    sleep 1
                    continue
                elif [[ "$key" == [qQ] ]]; then
                    break
                fi
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
        
        PID=""
        [ -f "$PID_FILE" ] && PID=$(cat "$PID_FILE" 2>/dev/null)
        
        local V_DIR="/srv/vdr/video"
        [ -f "/etc/vdr/conf.d/vdr-rectools.conf" ] && . "/etc/vdr/conf.d/vdr-rectools.conf"
        [ -n "${VIDEO_DIR}" ] && V_DIR="${VIDEO_DIR}"
        local L_FILE="$V_DIR/.vdr-rectools.lock"
        local P_PROMPT="$V_DIR/.vdr-rectools.prompt"
        local L_LOG="${LOG_FILE:-/var/log/vdr-rectools.log}"
        
        if [ -z "$PID" ] || ! ps -p "$PID" > /dev/null 2>&1; then
            [ -f "$L_FILE" ] && PID=$(cat "$L_FILE" 2>/dev/null)
            if [ -z "$PID" ] || ! ps -p "$PID" > /dev/null 2>&1; then
                PID=$(fuser "$L_FILE" 2>/dev/null | awk '{print $1}' | grep -o '[0-9]*' | head -n 1)
            fi
        fi
        
        # 1. Regulärer Kill-Tree
        if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
            get_descendants() {
                local parent=$1
                for child in $(pgrep -P "$parent" 2>/dev/null); do
                    get_descendants "$child"
                    echo "$child"
                done
            }
            ALL_PIDS=$(get_descendants "$PID")
            ALL_PIDS="$ALL_PIDS $PID"
            
            for p in $ALL_PIDS; do
                kill -15 "$p" 2>/dev/null
            done
            sleep 2
            for p in $ALL_PIDS; do
                if ps -p "$p" > /dev/null 2>&1; then
                    kill -9 "$p" 2>/dev/null
                fi
            done
        fi
        
        # 2. Ultimate Fallback: Fuser Kill (Tötet alles, was den Lock noch festhält)
        if fuser "$L_FILE" >/dev/null 2>&1; then
            echo "Erzwinge Stopp für hängende Locks (Fuser)..."
            fuser -k -15 "$L_FILE" >/dev/null 2>&1
            sleep 2
            fuser -k -9 "$L_FILE" >/dev/null 2>&1
        fi
        
        # 3. Aufräumen
        rm -f "$PID_FILE" "$P_PROMPT" "$V_DIR/.vdr-rectools.state" "$V_DIR/.vdr-rectools.duration" 2>/dev/null || true
        truncate -s 0 "$V_DIR/.vdr-rectools.lock" 2>/dev/null || true
        
        # 4. Log-Feedback für den User
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
