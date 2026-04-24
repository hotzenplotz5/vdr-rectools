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
    return 1 # Läuft nicht
}

# 2. Funktionen laden
# Wir brauchen die Funktionen nur, wenn wir eine Aktion ausführen
if [[ "$1" != "status" && "$1" != "stop" ]]; then
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
    while true; do
        clear
        local PID=$(cat "$PID_FILE")
        local RUNTIME=$(ps -p "$PID" -o etime= | tr -d ' ')
        echo "vdr-rectools läuft (PID: $PID, Laufzeit: $RUNTIME)"
        echo "--- Letzte 15 Log-Einträge ---"
        tail -n 15 /var/log/vdr-rectools.log
        echo
        echo -e "\n[L] Live-Log aktualisieren | [Q] Beenden"
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
            echo $$ > "$PID_FILE"
            run_scan "normal"
            rm -f "$PID_FILE"
        ) &
        ;;

    import)
        if is_running; then
            echo "vdr-rectools läuft bereits."
            exit 1
        fi
        echo "Starte Import im Hintergrund..."
        (
            echo $$ > "$PID_FILE"
            run_scan "import"
            rm -f "$PID_FILE"
        ) &
        ;;

    repair)
        if is_running; then
            echo "vdr-rectools läuft bereits."
            exit 1
        fi
        echo "Starte Reparatur-Lauf im Hintergrund..."
        (
            echo $$ > "$PID_FILE"
            run_scan "repair"
            rm -f "$PID_FILE"
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
            echo $$ > "$PID_FILE"
            run_scan "normal"
            rm -f "$PID_FILE"
        else
            echo "[$(date +%T)] AUTO_START_NIGHT ist deaktiviert, keine Aktion." >> "$LOG_FILE"
        fi
        ;;

    status)
        if is_running; then
            interactive_status
        else
            echo "vdr-rectools läuft nicht."
        fi
        ;;

    diag)
        show_diagnostics
        exit 0
        ;;

    stop)
        if is_running; then
            PID=$(cat "$PID_FILE")
            echo "Stoppe vdr-rectools (PID: $PID)..."
            kill "$PID"
            sleep 2
            if is_running; then
                echo "Prozess reagiert nicht, sende KILL..."
                kill -9 "$PID"
            fi
            rm -f "$PID_FILE"
            echo "Gestoppt."
        else
            echo "vdr-rectools läuft nicht."
        fi
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
