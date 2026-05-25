#!/bin/bash
# ==============================================================================
# vdr-rectools - Core Functions
# ==============================================================================

# 1. HARDCODED DEFAULTS
VIDEO_DIR="/srv/vdr/video"
IMPORT_DIR="/srv/vdr/import"
REPAIR_STAGING="/srv/vdr/tmp/staging"
SNAPSHOT_TIME="00:05:00"
CRF_H264_DEFAULT=23
PRESET_H264_DEFAULT="medium" # Preset for H.264 encoding (e.g., medium, fast, slow)
CRF_H265_DEFAULT=23 # CRF for H.265 encoding
PRESET_H265_DEFAULT="medium" # Preset for H.265 encoding
CRF_H264_FALLBACK=23 # CRF for H.264 fallback encoding
PRESET_H264_FALLBACK="fast" # Preset for H.264 fallback encoding
HW_ACCEL="none" # Hardwarebeschleunigung: none, nvenc, vaapi, qsv
MAIL_NOTIFY=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
AUTO_SUB_DOWNLOAD=1
AUDIO_NORMALIZE=0 # Neu: Audio-Downmix und Normalisierung auf Stereo (Night-Mode)
ASK_BEFORE_ENCODE=1 # Neu: Fragt per Status-Dashboard nach, bevor re-encodiert wird
HTML_DASHBOARD=0
HTML_PATH="/var/www/html/rectools.html"
MIN_COMPRESSION_RATIO_H264=70 # Max 70% of original size for H264 encodes
MIN_COMPRESSION_RATIO_H265=50 # Max 50% of original size for H265 encodes
MIN_COMPRESSION_RATIO_H264_FALLBACK=70 # Max 70% of original size for H264 fallback encodes
MIN_FREE_GB=50
MAX_FILESIZE_GB=0 # 0 = deaktiviert. Überspringt Importe, die größer als X GB sind.
MAX_FILES=5
LOG_FILE="/var/log/vdr-rectools.log"
# Lock-File im VDR-Video-Verzeichnis, damit sowohl 'root' als auch 'vdr' (OSD) konfliktfrei Schreibrechte haben
LOCK_FILE="$VIDEO_DIR/.vdr-rectools.lock"
STATE_FILE="$VIDEO_DIR/.vdr-rectools.state"
DURATION_FILE="$VIDEO_DIR/.vdr-rectools.duration"
SESSION_FILE="$VIDEO_DIR/.vdr-rectools.session"
USE_TVSCRAPER=0
TVSCRAPER_MODE="batch"

# 2. CONFIG EINLESEN
CONFIG_FILE="/etc/vdr/conf.d/vdr-rectools.conf"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# 3. MEDIA TOOLS LADEN
if [ -f /usr/share/vdr-rectools/media_tools.sh ]; then
    source /usr/share/vdr-rectools/media_tools.sh
else
    echo "[$(date +%T)] FEHLER: media_tools.sh nicht gefunden!" >> "$LOG_FILE"
    exit 1
fi

send_mail() {
    local BODY="$1"
    local SUBJECT="$2"

    # --- Telegram Push ---
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        local TG_BODY=$(echo -e "$BODY") # \n in echte Zeilenumbrüche umwandeln
        local TG_MESSAGE="🎬 VDR-Rectools: $SUBJECT"$'\n\n'"$TG_BODY"
        if ! curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            --data-urlencode text="$TG_MESSAGE" > /dev/null 2>&1; then
            echo "[$(date +%T)] WARNUNG: Telegram-Versand für Betreff '$SUBJECT' fehlgeschlagen." >> "$LOG_FILE"
        fi
    fi

    # --- VDR OSD Notification (Popup auf dem TV) ---
    # Bereinige den Betreff für das OSD (keine zu langen Texte oder Sonderzeichen)
    local OSD_MSG=$(echo "$SUBJECT" | tr -d '"\r\n' | cut -c 1-80)
    /usr/bin/svdrpsend MESG "Rectools: $OSD_MSG" > /dev/null 2>&1 || true

    # --- E-Mail ---
    [[ -z "$MAIL_NOTIFY" ]] && return
    # Body wird mit 'fold' umgebrochen, um "501 line too long" Fehler zu vermeiden.
    local WRAPPED_BODY=$(echo -e "$BODY\n\nWeitere Details finden Sie in der Log-Datei: $LOG_FILE" | fold -s -w 78)
    if ! echo "$WRAPPED_BODY" | mail -s "VDR-Rectools: $SUBJECT" "$MAIL_NOTIFY" 2>> "$LOG_FILE"; then
        echo "[$(date +%T)] WARNUNG: Mail-Versand für Betreff '$SUBJECT' ist fehlgeschlagen." >> "$LOG_FILE"
    fi
}

# --- NEU: Verhindert, dass das Skript mehrfach gleichzeitig läuft ---
ensure_single_instance() {
    # Verhindert Absturz des Locks, falls das VDR-Verzeichnis nach einem Neustart noch nicht gemountet ist
    mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || true
    local P_FILE="/var/run/vdr-rectools.pid"

    # Custom PID-basiertes Locking (verhindert unzerstörbare Locks durch FD-Leaks)
    if [[ -f "$LOCK_FILE" ]]; then
        local L_PID=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$L_PID" ]] && kill -0 "$L_PID" 2>/dev/null; then
            if ps -p "$L_PID" -o comm= 2>/dev/null | grep -q -E "bash|sh|vdr-rectools|ffmpeg"; then
                echo "[$(date +%T)] INFO: vdr-rectools arbeitet bereits im Hintergrund. Breche diesen Lauf ab, um Konflikte zu vermeiden." >> "$LOG_FILE"
                exit 0
            fi
        fi
    fi
    
    echo $BASHPID > "$LOCK_FILE" 2>/dev/null || true
    chmod 666 "$LOCK_FILE" 2>/dev/null || true
    echo $BASHPID > "$P_FILE" 2>/dev/null || true

    # VDR Shutdown-Hook automatisch anlegen (verhindert Herunterfahren während der Arbeit)
    local HOOK_DIR="${VDR_HOOK_DIR:-/etc/vdr/shutdown-hooks}"
    local HOOK_FILE="$HOOK_DIR/S90.vdr-rectools"
    if [[ -d "$HOOK_DIR" && ! -f "$HOOK_FILE" ]]; then
        echo "#!/bin/sh" > "$HOOK_FILE"
        echo "/usr/bin/vdr-rectools check_running" >> "$HOOK_FILE"
        chmod +x "$HOOK_FILE" 2>/dev/null || true
    fi

    # Status initialisieren
    if [[ ! -f "$STATE_FILE" ]]; then
        touch "$STATE_FILE" 2>/dev/null || true
        chmod 666 "$STATE_FILE" 2>/dev/null || true
    fi
    echo "Initialisiere..." > "$STATE_FILE"

    if [[ ! -f "$DURATION_FILE" ]]; then
        touch "$DURATION_FILE" 2>/dev/null || true
        chmod 666 "$DURATION_FILE" 2>/dev/null || true
    fi
    
    > "$SESSION_FILE" 2>/dev/null || true
    chmod 666 "$SESSION_FILE" 2>/dev/null || true
    
    # --- HTML Dashboard Auto-Updater ---
    HTML_UPDATER_PID=""
    if [[ "${HTML_DASHBOARD:-0}" -eq 1 && -n "$HTML_PATH" ]]; then
        mkdir -p "$(dirname "$HTML_PATH")" 2>/dev/null || true
        (
            while [[ -f "$LOCK_FILE" ]]; do
                export_html_status 2>/dev/null
                sleep 5
            done
        ) &
        HTML_UPDATER_PID=$!
    fi

    # Sperre und HTML-Updater nach Beendigung sauber aufräumen, damit das HTML am Ende auf INAKTIV springt
    trap 'truncate -s 0 "$LOCK_FILE" 2>/dev/null; rm -f "$STATE_FILE" "$DURATION_FILE" "$VIDEO_DIR/.vdr-rectools.prompt" "$P_FILE" "$(dirname "${HTML_PATH:-/var/www/html/rectools.html}")/dashboard_bg.jpg" 2>/dev/null; [[ -n "$HTML_UPDATER_PID" ]] && kill "$HTML_UPDATER_PID" 2>/dev/null; [[ "${HTML_DASHBOARD:-0}" -eq 1 ]] && export_html_status 2>/dev/null; exit 0' EXIT INT TERM
}

set_state() {
    echo "$1" > "$STATE_FILE" 2>/dev/null || true
    > "$DURATION_FILE" 2>/dev/null || true # Fortschrittsbalken für neue Aktion zurücksetzen (behält Rechte)
}

# --- NEU: Snapshot als Hintergrundbild für das Dashboard generieren ---
set_dashboard_bg() {
    [[ "${HTML_DASHBOARD:-0}" -ne 1 ]] && return
    local SRC="$1"
    local BG_IMG="$(dirname "${HTML_PATH:-/var/www/html/rectools.html}")/dashboard_bg.jpg"
    if [[ -f "$SRC" ]]; then
        (
            ffmpeg -hide_banner -y -ss "${SNAPSHOT_TIME:-00:05:00}" -i "$SRC" -frames:v 1 -q:v 5 -vf scale=1280:-2 "$BG_IMG" </dev/null >/dev/null 2>&1 || \
            ffmpeg -hide_banner -y -i "$SRC" -frames:v 1 -q:v 5 -vf scale=1280:-2 "$BG_IMG" </dev/null >/dev/null 2>&1
            chmod 666 "$BG_IMG" 2>/dev/null || true
        ) &
    else
        rm -f "$BG_IMG" 2>/dev/null
    fi
}

# Hilfsfunktion: Filtert bekannte, harmlose FFmpeg-Warnungen aus dem Log (z.B. Matroska BlockAdditions)
filter_ffmpeg_log() {
    # awk mit RS='[\r\n]+' verhindert, dass awk oder tr den Stream block-puffern. FFmpeg-Fortschritt ist sofort im Log.
    awk -v RS='[\r\n]+' 'NF==0{next} /Unexpected BlockAdditions/{skip=1; next} /Last message repeated/{if(skip) next} {skip=0; print; fflush()}'
}

# --- NEU: STUFE 1 (Schneller Fix) ---
sanitize_stream() {
    local FILE="$1"
    local tmp_file="${FILE}.san"
    echo "[$(date +%T)] Sanitize: Header-Fix fuer $FILE" >> "$LOG_FILE"
    ffmpeg -y -hide_banner -i "$FILE" -c copy -map 0 -f mpegts -fflags +genpts+igndts -avoid_negative_ts make_zero -max_muxing_queue_size 4000 "$tmp_file" </dev/null >/dev/null 2>&1
    if [[ $? -eq 0 && -f "$tmp_file" ]]; then
        mv "$tmp_file" "$FILE"
        return 0
    fi
    return 1
}

# --- NEU: STUFE 2 (Deep Repair - Nuclear Option) ---
recode_stream() {
    local FILE="$1"
    local tmp_file="${FILE}.recode.ts"
    echo "[$(date +%T)] Deep-Repair: Full Recode (Force Sync) gestartet fuer $FILE" >> "$LOG_FILE"
    local DURATION=$(get_duration "$FILE")
    echo "$DURATION" > "$DURATION_FILE" 2>/dev/null
    local FFMPEG_HW_OPTS=""
    local H264_ENC="libx264"
    case "$HW_ACCEL" in
        nvenc) FFMPEG_HW_OPTS="-hwaccel cuda -hwaccel_output_format cuda"; H264_ENC="h264_nvenc" ;;
        vaapi) FFMPEG_HW_OPTS="-hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128"; H264_ENC="h264_vaapi" ;;
        qsv) FFMPEG_HW_OPTS="-hwaccel qsv -hwaccel_output_format qsv"; H264_ENC="h264_qsv" ;;
    esac
    if [[ "$HW_ACCEL" != "none" ]]; then
        echo "[$(date +%T)] Deep-Repair mit Hardwarebeschleunigung ($H264_ENC) gestartet." >> "$LOG_FILE"
    fi

    # DER RICHTIGE AUFRUF (NUCLEAR):
    # Wir nutzen hier die Fallback-Parameter, da es ein Reparatur-Versuch ist.
    ffmpeg -y -hide_banner $FFMPEG_HW_OPTS -i "$FILE" -map 0:v? -map 0:a? -map 0:s? -fflags +genpts+igndts -avoid_negative_ts make_zero -max_muxing_queue_size 4000 \
        -c:v "$H264_ENC" -preset "${PRESET_H264_FALLBACK}" -crf "${CRF_H264_FALLBACK}" \
        -vsync cfr -r 25 \
        -c:a aac -b:a 192k \
        -c:s copy \
        -f mpegts "$tmp_file" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE" # Log ffmpeg output for deep repair

    local FF_STATUS=${PIPESTATUS[0]}
    
    # Automatischer Fallback auf Software-Decoding/Encoding, falls Hardware-Beschleunigung fehlschlägt
    if [[ $FF_STATUS -ne 0 && "$HW_ACCEL" != "none" ]]; then
        echo "[$(date +%T)] WARNUNG: Hardware-beschleunigtes Deep-Repair fehlgeschlagen. Fallback auf Software (CPU)..." >> "$LOG_FILE"
        ffmpeg -y -hide_banner -i "$FILE" -map 0:v? -map 0:a? -map 0:s? -fflags +genpts+igndts -avoid_negative_ts make_zero -max_muxing_queue_size 4000 \
            -c:v libx264 -preset "${PRESET_H264_FALLBACK}" -crf "${CRF_H264_FALLBACK}" \
            -vsync cfr -r 25 \
            -c:a aac -b:a 192k \
            -c:s copy \
            -f mpegts "$tmp_file" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
        FF_STATUS=${PIPESTATUS[0]}
    fi

    if [[ $FF_STATUS -eq 0 && -f "$tmp_file" ]]; then
        mv "$tmp_file" "$FILE"
        echo "[$(date +%T)] Deep-Repair erfolgreich" >> "$LOG_FILE"
        return 0
    fi
    return 1
}
smart_repair() {
    local TARGET="$1"
    sanitize_stream "$TARGET"
    local duration=$(get_duration "$TARGET")
    if [[ -n "$duration" && "$duration" =~ ^[0-9]+$ && "$duration" -lt 300 ]]; then
        echo "[$(date +%T)] Dauer kritisch kurz ($duration s). Starte Deep-Repair..." >> "$LOG_FILE"
        recode_stream "$TARGET"
    elif [[ -z "$duration" || ! "$duration" =~ ^[0-9]+$ ]]; then
        echo "[$(date +%T)] INFO: Dauer konnte nicht ermittelt werden (typisch fuer TS). Ueberspringe Deep-Repair." >> "$LOG_FILE"
    fi
}

# QA Check: Stream-Integrität
check_stream() {
    local FILE="$1"
    echo "[$(date +%T)] Starte Integritäts-Prüfung für: $FILE" >> "$LOG_FILE"
    
    # Führt ffmpeg aus und fängt alle Ausgaben (stdout und stderr) ab.
    # -v error zeigt nur kritische Fehler an.
    local FFERRORS
    FFERRORS=$(ffmpeg -v error -i "$FILE" -f null - 2>&1 | filter_ffmpeg_log)
    
    if [[ -n "$FFERRORS" ]]; then
        echo "[$(date +%T)] FEHLER gefunden in $FILE:" >> "$LOG_FILE"
        echo "$FFERRORS" >> "$LOG_FILE"
        echo "$FFERRORS" # Fehler an aufrufende Funktion zur Weiterverarbeitung ausgeben
        return 1 # Signalisiert Fehler
    fi
    echo "[$(date +%T)] Prüfung für $FILE erfolgreich. Keine Fehler gefunden." >> "$LOG_FILE"
    return 0 # Keine Fehler
}

# QA Check: Dateigröße
check_size() {
    local INPUT_FILE="$1"
    local OUTPUT_FILE="$2"
    local EXPECTED_RATIO_PERCENT="$3" # e.g., 70 for 70% of original size
    local ACTION_TYPE="$4" # e.g., "Import-Encode", "Shrink", "Import-Remux"

    local INPUT_SIZE=$(stat -c %s "$INPUT_FILE" 2>/dev/null || echo 0)
    local OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo 0)

    if [[ "$INPUT_SIZE" -eq 0 || "$OUTPUT_SIZE" -eq 0 ]]; then
        echo "[$(date +%T)] WARNUNG: $ACTION_TYPE - Dateigröße konnte nicht ermittelt werden für $INPUT_FILE oder $OUTPUT_FILE." >> "$LOG_FILE"
        return 0 # Kann nicht prüfen, also kein Fehler
    fi

    local ACTUAL_RATIO_PERCENT=$(( OUTPUT_SIZE * 100 / INPUT_SIZE ))

    if [[ "$ACTION_TYPE" == "Import-Remux" ]]; then
        # For remuxing from MKV to TS, a size increase due to container overhead is normal.
        # We allow up to 10% increase. More than that is suspicious.
        if [[ "$ACTUAL_RATIO_PERCENT" -gt 110 ]]; then
            echo "[$(date +%T)] WARNUNG: $ACTION_TYPE - Ausgabedatei ist über 10% größer als Eingabedatei ($((OUTPUT_SIZE/1024/1024))MB vs $((INPUT_SIZE/1024/1024))MB) für $OUTPUT_FILE." >> "$LOG_FILE"
            return 1 # Verdächtig
        fi
    else # For "Import-Encode" or "Shrink"
        # Check if output is larger than input
        if [[ "$OUTPUT_SIZE" -gt "$INPUT_SIZE" ]]; then
            echo "[$(date +%T)] WARNUNG: $ACTION_TYPE - Ausgabedatei ($((OUTPUT_SIZE/1024/1024))MB) ist größer als Eingabedatei ($((INPUT_SIZE/1024/1024))MB) für $OUTPUT_FILE." >> "$LOG_FILE"
            return 1 # Verdächtig
        fi

        # Check against expected compression ratio
        if [[ "$ACTUAL_RATIO_PERCENT" -gt "$EXPECTED_RATIO_PERCENT" ]]; then
            echo "[$(date +%T)] WARNUNG: $ACTION_TYPE - Kompressionsrate verdächtig für $OUTPUT_FILE. Erwartet max. ${EXPECTED_RATIO_PERCENT}%, aber ist ${ACTUAL_RATIO_PERCENT}%." >> "$LOG_FILE"
            return 1 # Verdächtig
        fi
    fi

    echo "[$(date +%T)] $ACTION_TYPE - Dateigrößenprüfung erfolgreich: Input $((INPUT_SIZE/1024/1024))MB, Output $((OUTPUT_SIZE/1024/1024))MB (${ACTUAL_RATIO_PERCENT}%)." >> "$LOG_FILE"
    return 0
}

# Hilfsfunktion: Dauer eines Videos ermitteln
get_duration() {
    local FILE="$1"
    local dur
    dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$FILE" 2>/dev/null | cut -d. -f1)
    if [[ -z "$dur" || "$dur" == "N/A" ]]; then
        dur=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$FILE" 2>/dev/null | cut -d. -f1 | head -n 1)
    fi
    echo "$dur"
}

check_disk_space() {
    [[ ! -d "$VIDEO_DIR" ]] && return 1
    local FREE_KB=$(df -Pk "$VIDEO_DIR" | awk 'NR==2 {print $4}')
    [[ -z "$FREE_KB" || ! "$FREE_KB" =~ ^[0-9]+$ ]] && return 1
    local FREE_GB=$((FREE_KB / 1024 / 1024))
    [[ "$FREE_GB" -lt "$MIN_FREE_GB" ]] && return 1
    return 0
}

process_folder() {
    local REC_DIR="$1"
    local MODE="$2"
    [[ ! -d "$REC_DIR" ]] && return 1
    cd "$REC_DIR" || return 1
    local FILM_TITLE=$(grep "^T " info 2>/dev/null | head -n 1 | cut -c3- | tr -d '\r' | sed 's/[\\/:"*?<>|]/_/g')
    [[ -z "$FILM_TITLE" ]] && FILM_TITLE=$(basename "$(dirname "$REC_DIR")")
    local CLEAN_NAME=$(echo "$FILM_TITLE" | sed 's/_/ /g')

    if [[ "$MODE" == "repair" || "$MODE" == "cut" || "$MODE" == "shrink" || "$MODE" == "check" ]]; then
        echo "[$(date +%T)] Starte $MODE fuer: $CLEAN_NAME" >> "$LOG_FILE"

        # Status für das Dashboard übersetzen
        local MODE_DE="$MODE"
        case "$MODE" in
            repair) MODE_DE="Repariere" ;;
            cut) MODE_DE="Schneide Werbung" ;;
            shrink) MODE_DE="Schrumpfe (H.265)" ;;
            check) MODE_DE="Prüfe Integrität" ;;
        esac
        set_state "$MODE_DE: $CLEAN_NAME"
        local FIRST_FILE=$(ls 000*.ts 2>/dev/null | head -n 1)
        [[ -n "$FIRST_FILE" ]] && set_dashboard_bg "$FIRST_FILE"

        local STAGING_REC="$REPAIR_STAGING/${MODE}_${FILM_TITLE}_${RANDOM}_$$"
        mkdir -p "$STAGING_REC"
        case "$MODE" in
            repair)
                cat 000*.ts > "$STAGING_REC/joined.ts"
                smart_repair "$STAGING_REC/joined.ts"
                mv "$STAGING_REC/joined.ts" "$STAGING_REC/00001.ts"
                ;;
            cut)
                cat 000*.ts > "$STAGING_REC/joined.ts"
                # Schnittmarken in den Staging-Ordner kopieren
                [[ -f marks ]] && cp marks "$STAGING_REC/"
                
                if apply_vdr_marks "$STAGING_REC/joined.ts"; then
                    mv "$STAGING_REC/joined.ts" "$STAGING_REC/00001.ts"
                    rm -f marks # Alte Marken entfernen, da der Schnitt fest eingebacken wurde
                else
                    echo "[$(date +%T)] FEHLER: Werbeschnitt abgebrochen. Originale Aufnahmen bleiben erhalten." >> "$LOG_FILE"
                fi
                ;;
            shrink)
                cat 000*.ts > "$STAGING_REC/joined.ts"
                local FFMPEG_HW_OPTS=""
                local H265_ENC="libx265"
                case "$HW_ACCEL" in
                    nvenc) FFMPEG_HW_OPTS="-hwaccel cuda -hwaccel_output_format cuda"; H265_ENC="hevc_nvenc" ;;
                    vaapi) FFMPEG_HW_OPTS="-hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128"; H265_ENC="hevc_vaapi" ;;
                    qsv) FFMPEG_HW_OPTS="-hwaccel qsv -hwaccel_output_format qsv"; H265_ENC="hevc_qsv" ;;
                esac
                if [[ "$HW_ACCEL" != "none" ]]; then
                    echo "[$(date +%T)] Shrink mit Hardwarebeschleunigung ($H265_ENC) gestartet." >> "$LOG_FILE"
                fi
                
                # --- Downscaling-Pruefung ---
                local VF_OPT=""
                if [[ "${SHRINK_MAX_RES:-0}" -gt 0 ]]; then
                    local RES_H=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$STAGING_REC/joined.ts" 2>/dev/null | head -n 1)
                    if [[ -n "$RES_H" && "$RES_H" =~ ^[0-9]+$ && "$RES_H" -gt "${SHRINK_MAX_RES}" ]]; then
                        echo "[$(date +%T)] INFO: Videoaufloesung ($RES_H) ist groesser als Limit (${SHRINK_MAX_RES}). Aktiviere Downscaling..." >> "$LOG_FILE"
                        VF_OPT="-vf scale=-2:${SHRINK_MAX_RES}"
                    fi
                fi

                local AUDIO_OPTS="-c:a copy"
                if [[ "${AUDIO_NORMALIZE:-0}" -eq 1 ]]; then
                    AUDIO_OPTS="-c:a aac -b:a 192k -ac 2 -af loudnorm"
                    echo "[$(date +%T)] INFO: Audio-Normalisierung (Night-Mode) für Shrink aktiviert." >> "$LOG_FILE"
                fi

                local DURATION=$(get_duration "$STAGING_REC/joined.ts")
                echo "$DURATION" > "$DURATION_FILE" 2>/dev/null
                ffmpeg -y -hide_banner $FFMPEG_HW_OPTS -i "$STAGING_REC/joined.ts" -map 0:v? -map 0:a? -map 0:s? $VF_OPT -c:v "$H265_ENC" -preset "${PRESET_H265_DEFAULT}" -crf "${CRF_H265_DEFAULT}" $AUDIO_OPTS -c:s copy -f mpegts -max_muxing_queue_size 4000 "$STAGING_REC/00001.ts" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
                local FF_STATUS=${PIPESTATUS[0]}
                
                if [[ $FF_STATUS -ne 0 && "$HW_ACCEL" != "none" ]]; then
                    echo "[$(date +%T)] WARNUNG: Hardware-beschleunigtes Shrinken fehlgeschlagen. Fallback auf Software (CPU)..." >> "$LOG_FILE"
                    ffmpeg -y -hide_banner -i "$STAGING_REC/joined.ts" -map 0:v? -map 0:a? -map 0:s? $VF_OPT -c:v libx265 -preset "${PRESET_H265_DEFAULT}" -crf "${CRF_H265_DEFAULT}" $AUDIO_OPTS -c:s copy -f mpegts -max_muxing_queue_size 4000 "$STAGING_REC/00001.ts" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
                    FF_STATUS=${PIPESTATUS[0]}
                fi
                
                if [[ $FF_STATUS -ne 0 ]]; then
                    echo "[$(date +%T)] FEHLER: Shrink-Encoding fehlgeschlagen (Status $FF_STATUS)." >> "$LOG_FILE"
                    rm -f "$STAGING_REC/00001.ts" # Verhindert den Austausch
                elif ! check_size "$STAGING_REC/joined.ts" "$STAGING_REC/00001.ts" "${MIN_COMPRESSION_RATIO_H265:-50}" "Shrink"; then
                    echo "[$(date +%T)] FEHLER: Shrink-Ergebnis verdächtig. Abbruch." >> "$LOG_FILE"
                    rm -f "$STAGING_REC/00001.ts"
                fi
                ;;
            check)
                local CHECK_ERRORS
                echo "[$(date +%T)] Starte Stream-Check via Pipe..." >> "$LOG_FILE"
                CHECK_ERRORS=$(cat 000*.ts | ffmpeg -v error -i pipe:0 -f null - 2>&1 | filter_ffmpeg_log)
                if [[ -z "$CHECK_ERRORS" ]]; then
                    send_mail "Die Aufnahme '$CLEAN_NAME' ist fehlerfrei." "Prüfung erfolgreich"
                else
                    local MAIL_BODY="In der Aufnahme '$CLEAN_NAME' wurden Fehler gefunden.\n\nFehlerdetails:\n$CHECK_ERRORS"
                    send_mail "$MAIL_BODY" "Prüfung fehlgeschlagen: $CLEAN_NAME"
                fi
                return
                ;;
        esac
        if [ -f "$STAGING_REC/00001.ts" ]; then
            cp info "$STAGING_REC/" 2>/dev/null
            /usr/bin/vdr --genindex="$STAGING_REC" >/dev/null 2>&1

            if [[ ! -f "$STAGING_REC/index" && "$MODE" == "repair" ]]; then
                echo "[$(date +%T)] VDR Index konnte nicht generiert werden! Erzwinge Deep-Repair (Re-Encode)..." >> "$LOG_FILE"
                recode_stream "$STAGING_REC/00001.ts"
                /usr/bin/vdr --genindex="$STAGING_REC" >/dev/null 2>&1
            fi

            if [ -f "$STAGING_REC/index" ]; then
                rm -f 000*.ts index 2>/dev/null # Löscht KEINE marks (Lesezeichen/Schnittmarken) mehr!
                mv "$STAGING_REC/00001.ts" .
                mv "$STAGING_REC/index" .
                # Dateirechte für den VDR wiederherstellen, sonst drohen "Permission denied" Fehler im OSD
                chown vdr:vdr 00001.ts index 2>/dev/null || true
                # VDR-Cache zwingend leeren! Sonst zeigt das OSD falsche Längen nach dem Schnitt/Shrink an
                touch "$VIDEO_DIR/.update" 2>/dev/null || true
                rm -rf "$STAGING_REC"
                echo "[$(date +%T)] $MODE erfolgreich abgeschlossen" >> "$LOG_FILE"
            else
                echo "[$(date +%T)] FEHLER: $MODE fehlgeschlagen, Index konnte final nicht erstellt werden." >> "$LOG_FILE"
                rm -rf "$STAGING_REC"
            fi
        else
            # Wenn 00001.ts nach den Vorgängen nicht mehr existiert, gab es einen Abbruch.
            if [ -d "$STAGING_REC" ]; then
                echo "[$(date +%T)] INFO: $MODE fehlgeschlagen. Räume temporären Staging-Ordner auf." >> "$LOG_FILE"
                rm -rf "$STAGING_REC"
            fi
        fi
    fi

    local NEW_VDR_FILE="00001.ts"
    local PLEX_LINK="$CLEAN_NAME.ts"
    if [[ -f "$NEW_VDR_FILE" ]]; then
        [[ ! -L "$PLEX_LINK" ]] && ln -sf "$NEW_VDR_FILE" "$PLEX_LINK"
        if [[ -f "00001.srt" && ! -f "${PLEX_LINK%.ts}.srt" ]]; then
            ln -sf "00001.srt" "${PLEX_LINK%.ts}.srt"
        elif [[ ! -f "${PLEX_LINK%.ts}.srt" && ! -f ".subtitles_checked" ]]; then
            extract_subtitles "$NEW_VDR_FILE"
            touch ".subtitles_checked" # Verhindert ewige I/O-Schleifen in künftigen Scans
        fi
        extract_images "$NEW_VDR_FILE"
        local NFO_FILE="${PLEX_LINK%.ts}.nfo"
        if [[ ! -f "$NFO_FILE" && -f "info" ]]; then
            local NFO_TITLE=$(grep "^T " info | head -n 1 | cut -c3- | tr -d '\r' | sed 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g')
            local NFO_DESC=$(grep "^D " info | cut -c3- | tr -d '\r' | sed 's/|/\n/g; s/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g')
            
            # Plex/Kodi-Sabotage verhindern: NFO nur generieren, wenn echter Text (z.B. EPG) vorhanden ist
            if [[ ! "$NFO_DESC" =~ ^Importiert\ am\  ]]; then
                echo -e "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<movie>\n  <title>${NFO_TITLE}</title>\n  <plot>${NFO_DESC}</plot>\n</movie>" > "$NFO_FILE"
            fi
        fi
        # Dateirechte für alle vom Skript generierten Hilfsdateien sicherstellen
        [[ -f "$NFO_FILE" ]] && chown vdr:vdr "$NFO_FILE" 2>/dev/null || true
        chown vdr:vdr "${PLEX_LINK%.ts}.srt" ".subtitles_checked" 2>/dev/null || true
        chown -h vdr:vdr "$PLEX_LINK" 2>/dev/null || true
    fi
}

# --- NEU: Bestätigung für Re-Encodes einholen ---
confirm_encoding() {
    local TITLE="$1"
    local CODEC="$2"
    local SRC_FILE="$3"
    
    if [[ "${ASK_BEFORE_ENCODE:-1}" -eq 0 ]]; then
        return 0 # Automatisches Durchwinken ohne Nachfrage
    fi
    
    local PROMPT_FILE="$VIDEO_DIR/.vdr-rectools.prompt"
    echo "WAIT|$TITLE|$CODEC" > "$PROMPT_FILE"
    chmod 666 "$PROMPT_FILE" 2>/dev/null || true # Erlaubt Usern, J oder N via Dashboard zu drücken
    
    # E-Mail/Telegram senden
    local MAIL_BODY="Der Film '$TITLE' (Codec: $CODEC) muss komplett re-encodiert werden. Dies kann abhaengig von der Hardware mehrere Stunden dauern.\n\nBitte loggen Sie sich per Konsole ein und starten Sie:\n\nvdr-rectools confirm\n\n... um den Vorgang zu bestaetigen oder abzulehnen."
    send_mail "$MAIL_BODY" "Aktion erforderlich: Re-Encode fuer $TITLE"
    
    echo "[$(date +%T)] Warte auf Nutzerbestätigung für Re-Encode von '$TITLE'..." >> "$LOG_FILE"
    set_state "Warte auf Bestätigung (Re-Encode): $TITLE"
    
    while [[ -f "$PROMPT_FILE" ]]; do
        local STATUS=$(cut -d'|' -f1 "$PROMPT_FILE" 2>/dev/null)
        if [[ "$STATUS" == "YES" ]]; then
            rm -f "$PROMPT_FILE"
            echo "[$(date +%T)] Nutzer hat Re-Encode für '$TITLE' bestätigt." >> "$LOG_FILE"
            set_state "Importiere: $TITLE"
                # Fortschrittsbalken-Bug Fix: set_state hat das DURATION_FILE genullt. Wir stellen es wieder her.
                local DUR=$(get_duration "$SRC_FILE")
                echo "$DUR" > "$DURATION_FILE" 2>/dev/null
            return 0
        elif [[ "$STATUS" == "NO" ]]; then
            rm -f "$PROMPT_FILE"
            echo "[$(date +%T)] Nutzer hat Re-Encode für '$TITLE' abgelehnt. Datei wird übersprungen (.skipped)." >> "$LOG_FILE"
            mv -f "$SRC_FILE" "${SRC_FILE}.skipped" 2>/dev/null
            return 1
        fi
        sleep 2
    done
    return 1 # Fallback, falls Datei (z.B. durch 'stop') gelöscht wird
}

# --- NEU: Bestätigung via VDR OSD (Fernbedienung) ---
handle_osd_confirm() {
    local ANSWER="$1"
    local PROMPT_FILE="$VIDEO_DIR/.vdr-rectools.prompt"
    
    if [[ ! -f "$PROMPT_FILE" ]]; then
        echo "-> Aktuell kein ausstehender Re-Encode."
        return 1
    fi
    
    local STATUS=$(cut -d'|' -f1 "$PROMPT_FILE" 2>/dev/null)
    local P_TITLE=$(cut -d'|' -f2 "$PROMPT_FILE" 2>/dev/null)
    
    if [[ "$STATUS" != "WAIT" ]]; then
        echo "-> Diese Anfrage wurde bereits bearbeitet."
        return 1
    fi
    
    if [[ "$ANSWER" == "yes" ]]; then
        sed -i 's/^WAIT/YES/' "$PROMPT_FILE"
        echo "-> Re-Encode fuer '$P_TITLE' GESTARTET."
        /usr/bin/svdrpsend MESG "Rectools: Re-Encode gestartet" >/dev/null 2>&1 || true
    elif [[ "$ANSWER" == "no" ]]; then
        sed -i 's/^WAIT/NO/' "$PROMPT_FILE"
        echo "-> Re-Encode fuer '$P_TITLE' ABGELEHNT."
        /usr/bin/svdrpsend MESG "Rectools: Import uebersprungen" >/dev/null 2>&1 || true
    fi
}

process_import() {
    local SOURCE_FILE="$1"
    local MODE="$2"

    local FILENAME=$(basename "$SOURCE_FILE")
    local NFO_SOURCE="${SOURCE_FILE%.*}.nfo"
    local META_TITLE=""
    local META_DESC=""

    if [[ -f "$NFO_SOURCE" ]]; then
        echo "[$(date +%T)] Metadaten-Datei gefunden: $NFO_SOURCE" >> "$LOG_FILE"
        # awk liest über mehrzeilige XML-Tags hinweg, was z.B. für TinyMediaManager NFOs zwingend nötig ist
        META_TITLE=$(awk -v RS='</title>' '/<title>/{gsub(/.*<title>/, ""); print; exit}' "$NFO_SOURCE" 2>/dev/null | tr -d '\r\n' | sed 's/^[ \t]*//;s/[ \t]*$//')
        META_DESC=$(awk -v RS='</plot>' '/<plot>/{gsub(/.*<plot>/, ""); print; exit}' "$NFO_SOURCE" 2>/dev/null | tr -d '\r' | awk 'NF{gsub(/^[ \t]+/,""); gsub(/[ \t]+$/,""); print}' | paste -sd '|' -)
    fi

    local PRETTY_TITLE="${META_TITLE:-${FILENAME%.*}}"
    local CLEAN_NAME=$(echo "$PRETTY_TITLE" | sed 's/[\\/:"*?<>|]/_/g')

    local REL_PATH=$(dirname "${SOURCE_FILE#$IMPORT_DIR/}")
    local TARGET_SUBDIR=""
    [[ "$REL_PATH" != "." ]] && TARGET_SUBDIR="$REL_PATH/"

    # --- Dubletten-Check ---
    local MOVIE_FOLDER="$VIDEO_DIR/${TARGET_SUBDIR}$CLEAN_NAME"
    if find "$MOVIE_FOLDER" -maxdepth 1 -type d -name "*.rec" 2>/dev/null | grep -q "."; then
        echo "[$(date +%T)] WARNUNG: '$PRETTY_TITLE' existiert bereits im VDR. Import wird übersprungen." >> "$LOG_FILE"
        mv -f "$SOURCE_FILE" "${SOURCE_FILE}.duplicate" 2>/dev/null
        [[ -f "$NFO_SOURCE" ]] && mv -f "$NFO_SOURCE" "${NFO_SOURCE}.duplicate" 2>/dev/null
        return 0
    fi

    # --- Datei-Größen-Limit ---
    if [[ "${MAX_FILESIZE_GB:-0}" -gt 0 ]]; then
        local F_SIZE_BYTES=$(stat -c %s "$SOURCE_FILE" 2>/dev/null || echo 0)
        local F_SIZE_GB=$((F_SIZE_BYTES / 1073741824))
        if [[ "$F_SIZE_GB" -ge "$MAX_FILESIZE_GB" ]]; then
            echo "[$(date +%T)] WARNUNG: '$PRETTY_TITLE' ist zu groß ($F_SIZE_GB GB, Limit: $MAX_FILESIZE_GB GB). Überspringe Import (.skipped)." >> "$LOG_FILE"
            mv -f "$SOURCE_FILE" "${SOURCE_FILE}.skipped" 2>/dev/null
            return 0
        fi
    fi
    local VCODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$SOURCE_FILE" 2>/dev/null | head -n 1 | tr -d '\r\n')

    [[ "$MODE" == "dryrun" ]] && { echo "[DRY-RUN] Import $FILENAME -> $TARGET_SUBDIR"; return 0; }
    check_disk_space || { echo "[$(date +%T)] FEHLER: Zu wenig Speicherplatz" >> "$LOG_FILE"; return 1; }
    local DATE_STR=$(date +"%Y-%m-%d.%H.%M.1-0.rec")
    local STAGING_REC="$REPAIR_STAGING/import_${CLEAN_NAME}_${RANDOM}_$$"
    local FINAL_DEST="$VIDEO_DIR/${TARGET_SUBDIR}$CLEAN_NAME/$DATE_STR"
    mkdir -p "$STAGING_REC"

    echo "[$(date +%T)] Import-Analyse für $FILENAME. Erkannter Codec: ${VCODEC:-unbekannt}" >> "$LOG_FILE"
    set_dashboard_bg "$SOURCE_FILE"
    set_state "Importiere: $PRETTY_TITLE"
    local DURATION=$(get_duration "$SOURCE_FILE")
    echo "$DURATION" > "$DURATION_FILE" 2>/dev/null

    # --- Intelligente Import-Weiche ---
    local ENCODING_PERFORMED=0
    local EXPECTED_RATIO=100 # Default for remuxing, 100% of original size
    local ACTION_TYPE_LOG="Import-Remux"
    local FFMPEG_HW_OPTS=""
    local H264_ENC="libx264"
    local H265_ENC="libx265"
    local FF_STATUS=0
    
    local AUDIO_OPTS="-c:a aac -b:a 192k"
    if [[ "${AUDIO_NORMALIZE:-0}" -eq 1 ]]; then
        AUDIO_OPTS="-c:a aac -b:a 192k -ac 2 -af loudnorm"
        echo "[$(date +%T)] INFO: Audio-Normalisierung (Night-Mode) für Import aktiviert." >> "$LOG_FILE"
    fi

    # --- Hardwarebeschleunigung ---
    case "$HW_ACCEL" in
        nvenc)
            FFMPEG_HW_OPTS="-hwaccel cuda -hwaccel_output_format cuda"
            H264_ENC="h264_nvenc"
            H265_ENC="hevc_nvenc"
            echo "[$(date +%T)] Hardwarebeschleunigung: Nvidia NVENC aktiviert." >> "$LOG_FILE"
            ;;
        vaapi)
            FFMPEG_HW_OPTS="-hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128"
            H264_ENC="h264_vaapi"
            H265_ENC="hevc_vaapi"
            echo "[$(date +%T)] Hardwarebeschleunigung: VA-API aktiviert." >> "$LOG_FILE"
            ;;
        qsv)
            FFMPEG_HW_OPTS="-hwaccel qsv -hwaccel_output_format qsv"
            H264_ENC="h264_qsv"
            H265_ENC="hevc_qsv"
            echo "[$(date +%T)] Hardwarebeschleunigung: Intel QSV aktiviert." >> "$LOG_FILE"
            ;;
    esac

    if [[ "$VCODEC" == "dvvideo" ]]; then
        confirm_encoding "$PRETTY_TITLE" "$VCODEC" "$SOURCE_FILE" || { rm -rf "$STAGING_REC"; return 1; }
        echo "[$(date +%T)] Aktion: MiniDV-Stream erkannt. Starte Re-Encode mit Deinterlacing nach H.264..." >> "$LOG_FILE"
        ffmpeg -y -hide_banner $FFMPEG_HW_OPTS -i "$SOURCE_FILE" -map 0:v? -map 0:a? -vf yadif -c:v "$H264_ENC" -preset "${PRESET_H264_DEFAULT}" -crf "${CRF_H264_DEFAULT}" $AUDIO_OPTS -f mpegts -max_muxing_queue_size 4000 "$STAGING_REC/joined.ts" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
        FF_STATUS=${PIPESTATUS[0]}
        
        if [[ $FF_STATUS -ne 0 && "$HW_ACCEL" != "none" ]]; then
            echo "[$(date +%T)] WARNUNG: Hardware-Encoding fehlgeschlagen. Fallback auf Software (CPU)..." >> "$LOG_FILE"
            ffmpeg -y -hide_banner -i "$SOURCE_FILE" -map 0:v? -map 0:a? -vf yadif -c:v libx264 -preset "${PRESET_H264_DEFAULT}" -crf "${CRF_H264_DEFAULT}" $AUDIO_OPTS -f mpegts -max_muxing_queue_size 4000 "$STAGING_REC/joined.ts" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
            FF_STATUS=${PIPESTATUS[0]}
        fi
        
        ENCODING_PERFORMED=1
        EXPECTED_RATIO="${MIN_COMPRESSION_RATIO_H264:-70}" # Example: expect max 70% of original size
        ACTION_TYPE_LOG="Import-Encode (DV)"
    elif [[ "$VCODEC" =~ ^(vp8|vp9|av1)$ ]]; then
        confirm_encoding "$PRETTY_TITLE" "$VCODEC" "$SOURCE_FILE" || { rm -rf "$STAGING_REC"; return 1; }
        echo "[$(date +%T)] Aktion: Web-Format ($VCODEC) erkannt. Starte Re-Encode nach H.265 (HEVC)..." >> "$LOG_FILE"
        ffmpeg -y -hide_banner $FFMPEG_HW_OPTS -i "$SOURCE_FILE" -map 0:v? -map 0:a? -c:v "$H265_ENC" -preset "${PRESET_H265_DEFAULT}" -crf "${CRF_H265_DEFAULT}" $AUDIO_OPTS -f mpegts -max_muxing_queue_size 4000 "$STAGING_REC/joined.ts" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
        FF_STATUS=${PIPESTATUS[0]}
        
        if [[ $FF_STATUS -ne 0 && "$HW_ACCEL" != "none" ]]; then
            echo "[$(date +%T)] WARNUNG: Hardware-Encoding fehlgeschlagen (evtl. fehlende Decoder-Unterstützung für $VCODEC). Fallback auf Software (CPU)..." >> "$LOG_FILE"
            ffmpeg -y -hide_banner -i "$SOURCE_FILE" -map 0:v? -map 0:a? -c:v libx265 -preset "${PRESET_H265_DEFAULT}" -crf "${CRF_H265_DEFAULT}" $AUDIO_OPTS -f mpegts -max_muxing_queue_size 4000 "$STAGING_REC/joined.ts" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
            FF_STATUS=${PIPESTATUS[0]}
        fi
        
        ENCODING_PERFORMED=1
        EXPECTED_RATIO="${MIN_COMPRESSION_RATIO_H265:-50}" # Example: expect max 50% of original size
        ACTION_TYPE_LOG="Import-Encode (Web)"
    elif [[ "$VCODEC" == "mpeg4" ]]; then
        confirm_encoding "$PRETTY_TITLE" "$VCODEC" "$SOURCE_FILE" || { rm -rf "$STAGING_REC"; return 1; }
        echo "[$(date +%T)] Aktion: Legacy-Format (mpeg4) erkannt. Starte Re-Encode nach H.264..." >> "$LOG_FILE"
        ffmpeg -y -hide_banner $FFMPEG_HW_OPTS -i "$SOURCE_FILE" -map 0:v? -map 0:a? -c:v "$H264_ENC" -preset "${PRESET_H264_DEFAULT}" -crf "${CRF_H264_DEFAULT}" $AUDIO_OPTS -f mpegts -max_muxing_queue_size 4000 "$STAGING_REC/joined.ts" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
        FF_STATUS=${PIPESTATUS[0]}
        
        if [[ $FF_STATUS -ne 0 && "$HW_ACCEL" != "none" ]]; then
            echo "[$(date +%T)] WARNUNG: Hardware-Encoding fehlgeschlagen. Fallback auf Software (CPU)..." >> "$LOG_FILE"
            ffmpeg -y -hide_banner -i "$SOURCE_FILE" -map 0:v? -map 0:a? -c:v libx264 -preset "${PRESET_H264_DEFAULT}" -crf "${CRF_H264_DEFAULT}" $AUDIO_OPTS -f mpegts -max_muxing_queue_size 4000 "$STAGING_REC/joined.ts" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
            FF_STATUS=${PIPESTATUS[0]}
        fi
        
        ENCODING_PERFORMED=1
        EXPECTED_RATIO="${MIN_COMPRESSION_RATIO_H264:-70}"
        ACTION_TYPE_LOG="Import-Encode (MPEG4)"
    elif [[ "$VCODEC" =~ ^(h264|mpeg2video)$ ]]; then
        echo "[$(date +%T)] Aktion: VDR-kompatibler Stream ($VCODEC). Starte schnelles Remuxing..." >> "$LOG_FILE"
        local AUDIO_PARAMS=$(get_audio_map "$SOURCE_FILE")
        # Kein FFMPEG_HW_OPTS hier, da wir den Stream nicht dekodieren, sondern nur kopieren (-c copy)!
        ffmpeg -y -hide_banner -i "$SOURCE_FILE" $AUDIO_PARAMS -copyts -fflags +genpts+igndts -f mpegts -max_muxing_queue_size 4000 "$STAGING_REC/joined.ts" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
        FF_STATUS=${PIPESTATUS[0]}
    else
        confirm_encoding "$PRETTY_TITLE" "${VCODEC:-unbekannt}" "$SOURCE_FILE" || { rm -rf "$STAGING_REC"; return 1; }
        echo "[$(date +%T)] Aktion: Unbekannter/Anderer Codec (${VCODEC:-unbekannt}). Fallback auf H.264 Re-Encode..." >> "$LOG_FILE"
        ffmpeg -y -hide_banner $FFMPEG_HW_OPTS -i "$SOURCE_FILE" -map 0:v? -map 0:a? -c:v "$H264_ENC" -preset "${PRESET_H264_FALLBACK}" -crf "${CRF_H264_FALLBACK}" $AUDIO_OPTS -f mpegts -max_muxing_queue_size 4000 "$STAGING_REC/joined.ts" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
        FF_STATUS=${PIPESTATUS[0]}
        
        if [[ $FF_STATUS -ne 0 && "$HW_ACCEL" != "none" ]]; then
            echo "[$(date +%T)] WARNUNG: Hardware-Encoding fehlgeschlagen. Fallback auf Software (CPU)..." >> "$LOG_FILE"
            ffmpeg -y -hide_banner -i "$SOURCE_FILE" -map 0:v? -map 0:a? -c:v libx264 -preset "${PRESET_H264_FALLBACK}" -crf "${CRF_H264_FALLBACK}" $AUDIO_OPTS -f mpegts -max_muxing_queue_size 4000 "$STAGING_REC/joined.ts" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
            FF_STATUS=${PIPESTATUS[0]}
        fi
        
        ENCODING_PERFORMED=1
        EXPECTED_RATIO="${MIN_COMPRESSION_RATIO_H264_FALLBACK:-70}" # Example: expect max 70% of original size
        ACTION_TYPE_LOG="Import-Encode (Fallback)"
    fi
    if [[ $FF_STATUS -eq 0 ]] && [ -f "$STAGING_REC/joined.ts" ]; then
        smart_repair "$STAGING_REC/joined.ts"
        mv "$STAGING_REC/joined.ts" "$STAGING_REC/00001.ts"

        # QA Check: Dateigröße
        if ! check_size "$SOURCE_FILE" "$STAGING_REC/00001.ts" "$EXPECTED_RATIO" "$ACTION_TYPE_LOG"; then
            echo "[$(date +%T)] FEHLER: $ACTION_TYPE_LOG für $FILENAME fehlgeschlagen oder Ergebnis verdächtig. Originaldatei wird nicht gelöscht." >> "$LOG_FILE"
            send_mail "$ACTION_TYPE_LOG für '$PRETTY_TITLE' fehlgeschlagen oder Ergebnis verdächtig. Originaldatei wurde nicht gelöscht." "Import-Fehler"
            rm -rf "$STAGING_REC" # Den fehlerhaften Staging-Ordner löschen
            return 1
        fi

        # info-Datei erstellen: NFO-Daten haben Vorrang
        echo "T $PRETTY_TITLE" > "$STAGING_REC/info"
        echo "D ${META_DESC:-Importiert am $(date +"%d.%m.%Y")}" >> "$STAGING_REC/info"
        echo "[$(date +%T)] info-Datei für '$PRETTY_TITLE' wurde mit Metadaten befüllt." >> "$LOG_FILE"
        # NFO-Datei für Plex/Kodi in den Aufnahmeordner kopieren
        local PLEX_NAME=$(echo "$CLEAN_NAME" | sed 's/_/ /g')
        [[ -f "$NFO_SOURCE" ]] && cp "$NFO_SOURCE" "$STAGING_REC/${PLEX_NAME}.nfo"

        # --- MKV-Kapitel zu VDR-Schnittmarken konvertieren ---
        local MARKS_FILE="$STAGING_REC/marks"
        ffprobe -v error -show_chapters -of default=noprint_wrappers=1 "$SOURCE_FILE" 2>/dev/null | awk -F= '
        /^id=/ {
            if (time_str != "") {
                if (title != "") print time_str " " title;
                else print time_str;
            }
            time_str=""; title=""
        }
        /^start_time=/ {
            t=$2; h=int(t/3600); m=int((t%3600)/60); s=int(t%60); f=int((t-int(t))*25)+1; if(f>25) f=25
            time_str=sprintf("%02d:%02d:%02d.%02d", h, m, s, f)
        }
        /^TAG:title=/ {
            title=substr($0, 11); gsub(/\r/, "", title)
        }
        END {
            if (time_str != "") { if (title != "") print time_str " " title; else print time_str; }
        }' > "$MARKS_FILE"
        
        [[ ! -s "$MARKS_FILE" ]] && rm -f "$MARKS_FILE" || { echo "[$(date +%T)] INFO: MKV-Kapitel als VDR-Schnittmarken exportiert." >> "$LOG_FILE"; chown vdr:vdr "$MARKS_FILE" 2>/dev/null || true; }

        /usr/bin/vdr --genindex="$STAGING_REC" >/dev/null 2>&1
        
        # Lokale Untertitel (inkl. Ländercode wie .de.srt) einbinden, bevor nach neuen gesucht wird
        # grep -F ignoriert Sonderzeichen wie [] im Dateinamen, an denen find -name (Globbing) sonst scheitern würde
        local SRT_SOURCE=$(find "$(dirname "$SOURCE_FILE")" -maxdepth 1 -type f -name "*.srt" 2>/dev/null | grep -F "/${FILENAME%.*}" | head -n 1)
        if [[ -n "$SRT_SOURCE" && -f "$SRT_SOURCE" ]]; then
            echo "[$(date +%T)] Lokale Untertitel-Datei gefunden und kopiert." >> "$LOG_FILE"
            cp "$SRT_SOURCE" "$STAGING_REC/00001.srt"
            rm -f "$SRT_SOURCE"
        fi

        if [[ "$AUTO_SUB_DOWNLOAD" -eq 1 && ! -f "$STAGING_REC/00001.srt" ]]; then
            echo "[$(date +%T)] Suche nach Untertiteln (Sprache: ${SUB_LANG:-de}) für $FILENAME..." >> "$LOG_FILE"
            # Die Ausgabe von subliminal wird nun ins Log geschrieben
            timeout 60s subliminal download -l "${SUB_LANG:-de}" -d "$STAGING_REC" "$SOURCE_FILE" >> "$LOG_FILE" 2>&1
            local SUB_STATUS=$?
            local DOWNLOADED_SRT=$(find "$STAGING_REC" -maxdepth 1 -name "*.srt" | head -n 1)
            if [[ $SUB_STATUS -eq 124 ]]; then
                echo "[$(date +%T)] WARNUNG: Untertitel-Suche wegen Zeitueberschreitung (Timeout) abgebrochen." >> "$LOG_FILE"
            fi
            if [[ -f "$DOWNLOADED_SRT" ]]; then
                mv "$DOWNLOADED_SRT" "$STAGING_REC/00001.srt"
                echo "[$(date +%T)] Untertitel gefunden und als 00001.srt gespeichert." >> "$LOG_FILE"
            fi
        fi
        mkdir -p "$(dirname "$FINAL_DEST")"
        # -T verhindert das fatale Verschachteln von Ordnern, falls das Zielverzeichnis durch einen exakt zeitgleichen Import schon existiert
        if mv -T "$STAGING_REC" "$FINAL_DEST"; then
            chown -R vdr:vdr "$VIDEO_DIR/${TARGET_SUBDIR}$CLEAN_NAME"
            process_folder "$FINAL_DEST" "normal"
            touch "$VIDEO_DIR/.update"
            rm -f "$SOURCE_FILE"
        else
            echo "[$(date +%T)] FEHLER: Konnte $STAGING_REC nicht nach $FINAL_DEST verschieben." >> "$LOG_FILE"
            send_mail "Fehler beim Verschieben in den Zielordner für '$PRETTY_TITLE'. Die Originaldatei bleibt erhalten." "Import-Fehler"
            rm -rf "$STAGING_REC"
            return 1
        fi

        # --- TVScraper Integration ---
        if [[ "$USE_TVSCRAPER" -eq 1 ]]; then
            if [[ "$TVSCRAPER_MODE" == "immediate" ]]; then
                echo "[$(date +%T)] TVScraper (immediate): Triggere Scrape für $FINAL_DEST" >> "$LOG_FILE"
                /usr/bin/svdrpsend plug tvscraper SCRAPE "$FINAL_DEST" >/dev/null 2>&1 || true
            else
                echo "[$(date +%T)] TVScraper (batch): Film in VDR importiert, warte auf nächtlichen TVScraper-Lauf." >> "$LOG_FILE"
            fi
        fi

        echo "$PRETTY_TITLE" >> "$SESSION_FILE" 2>/dev/null || true
        echo "[$(date +%T)] ERFOLG: Import von '$PRETTY_TITLE' erfolgreich abgeschlossen!" >> "$LOG_FILE"
        send_mail "Der Film '$PRETTY_TITLE' wurde erfolgreich importiert." "Import erfolgreich: $PRETTY_TITLE"
        return 0
    else
        echo "[$(date +%T)] FEHLER: FFmpeg-Verarbeitung fuer $FILENAME abgebrochen (Status $FF_STATUS)." >> "$LOG_FILE"
        rm -rf "$STAGING_REC"
        return 1
    fi
}

# --- Orphan-Sweeper: Räumt alte Crash-Ordner auf ---
cleanup_orphans() {
    if [[ -d "$REPAIR_STAGING" ]]; then
        # Finde Ordner, die älter als 24 Stunden (+1440 Minuten) sind
        find "$REPAIR_STAGING" -mindepth 1 -maxdepth 1 -type d -mmin +1440 2>/dev/null | while read -r orphan; do
            echo "[$(date +%T)] WARNUNG: Orphan-Sweeper löscht veralteten Crash-Ordner: $orphan" >> "$LOG_FILE"
            rm -rf "$orphan"
        done
    fi
}

run_scan() {
    ensure_single_instance

    cleanup_orphans
    local MODE="$1"
    local COUNT=0
    
    if [[ "$MODE" == "normal" || "$MODE" == "import" ]]; then
        set_state "Scanne Import-Verzeichnis..."
        find "$IMPORT_DIR" -maxdepth 2 -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.ts" -o -name "*.avi" -o -name "*.mov" \) | while read -r FILE; do
            [[ $COUNT -ge "$MAX_FILES" ]] && break
            process_import "$FILE" "$MODE" && ((COUNT++))
        done
    fi
    
    # Den aufwendigen Komplett-Scan des VDR-Verzeichnisses überspringen, wenn nur "import" aufgerufen wurde
    if [[ "$MODE" != "import" ]]; then
        set_state "Scanne VDR-Verzeichnis..."
        while read -r DIR; do
            process_folder "$DIR" "$MODE"
        done < <(find -L "$VIDEO_DIR" -type d -name "*.rec" | sort)
    fi
    set_state "Scan abgeschlossen."
}

show_status() {
    echo -e "\n\033[1;36m========================================================\033[0m"
    echo -e "\033[1;37m 🎬 VDR-Rectools - System Status\033[0m"
    echo -e "\033[1;36m========================================================\033[0m\n"

    # 1. Prozess-Status (Herzschlag)
    local PID=""
    local IS_RUNNING=0
    if [[ -f "$LOCK_FILE" ]]; then
        PID=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
            if ps -p "$PID" -o comm= 2>/dev/null | grep -q -E "bash|sh|vdr-rectools|ffmpeg"; then
                IS_RUNNING=1
            fi
        fi
    fi

    if [[ $IS_RUNNING -eq 1 ]]; then
        local RUNTIME=$(ps -p "$PID" -o etime= 2>/dev/null | tr -d ' ')
        local CURRENT_ACTION="Arbeitet..."
        [[ -f "$STATE_FILE" ]] && CURRENT_ACTION=$(cat "$STATE_FILE" 2>/dev/null)
        echo -e " \033[1;32m🟢 AKTIV\033[0m    - Prozess läuft (PID: $PID, seit: $RUNTIME)"
        echo -e " \033[1;34m🎬 AKTUELL\033[0m  - $CURRENT_ACTION"
        
        local PROMPT_FILE="$VIDEO_DIR/.vdr-rectools.prompt"
        if [[ -f "$PROMPT_FILE" ]]; then
            local P_TITLE=$(cut -d'|' -f2 "$PROMPT_FILE" 2>/dev/null)
            echo -e " \033[1;33m⚠️  WARTE AUF BESTÄTIGUNG:\033[0m Re-Encode für '$P_TITLE'"
            echo -e " 👉 Bitte in der Konsole ausführen: \033[1;32mvdr-rectools confirm\033[0m"
        fi
        
        # Fortschrittsbalken berechnen und anzeigen
        if [[ -f "$DURATION_FILE" ]]; then
            local TOT_SEC=$(cat "$DURATION_FILE" 2>/dev/null)
            if [[ -n "$TOT_SEC" && "$TOT_SEC" =~ ^[0-9]+$ && "$TOT_SEC" -gt 0 ]]; then
                local LAST_TIME=$(tail -n 50 "$LOG_FILE" 2>/dev/null | grep -oE 'time=[ ]*[0-9]+:[0-9]{2}:[0-9]{2}' | tail -n 1 | cut -d= -f2 | tr -d ' ')
                if [[ -n "$LAST_TIME" ]]; then
                    local H=$(echo "$LAST_TIME" | cut -d: -f1)
                    local M=$(echo "$LAST_TIME" | cut -d: -f2)
                    local S=$(echo "$LAST_TIME" | cut -d: -f3)
                    # 10# verhindert Oktal-Interpretation bei z.B. 08
                    local CUR_SEC=$(( 10#$H * 3600 + 10#$M * 60 + 10#$S ))
                    local PERCENT=$(( CUR_SEC * 100 / TOT_SEC ))
                    [[ $PERCENT -gt 100 ]] && PERCENT=100
                    
                    local FILLED=$(( PERCENT / 5 ))
                    local EMPTY=$(( 20 - FILLED ))
                    local BAR=""
                    for ((i=0; i<FILLED; i++)); do BAR="${BAR}█"; done
                    for ((i=0; i<EMPTY; i++)); do BAR="${BAR}░"; done
                    echo -e " \033[1;35m⏳ FORTSCHRITT\033[0m- [$BAR] $PERCENT%"
                    
                    # --- ETA / Restzeit Berechnung ---
                    local SPEED=$(tail -n 50 "$LOG_FILE" 2>/dev/null | grep -o 'speed=[ ]*[0-9.]*x' | tail -n 1 | sed 's/speed=//;s/x//;s/ //g')
                    if [[ -n "$SPEED" && "$SPEED" != "0" && "$SPEED" != "0.0" ]]; then
                        local REM_SEC=$(( TOT_SEC - CUR_SEC ))
                        if [[ $REM_SEC -gt 0 ]]; then
                            # awk nutzen, da bash keine Fließkommazahlen dividieren kann
                            local ETA_SEC=$(awk -v rem="$REM_SEC" -v spd="$SPEED" 'BEGIN { if(spd>0) printf "%d", rem/spd; else print 0 }')
                            if [[ "$ETA_SEC" -gt 0 ]]; then
                                local ETA_H=$(( ETA_SEC / 3600 ))
                                local ETA_M=$(( (ETA_SEC % 3600) / 60 ))
                                local ETA_S=$(( ETA_SEC % 60 ))
                                if [[ $ETA_H -gt 0 ]]; then
                                    echo -e " \033[1;36m⏱️  RESTZEIT\033[0m   - $(printf "%02d:%02d:%02d" $ETA_H $ETA_M $ETA_S) (bei ${SPEED}x Speed)"
                                else
                                    echo -e " \033[1;36m⏱️  RESTZEIT\033[0m   - $(printf "%02d:%02d" $ETA_M $ETA_S) (bei ${SPEED}x Speed)"
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
    else
        echo -e " \033[1;30m⚪ INAKTIV\033[0m  - Wartet auf Arbeit im Hintergrund"
    fi

    # 2. Festplatten-Status
    if [[ -d "$VIDEO_DIR" ]]; then
        local FREE_KB=$(df -Pk "$VIDEO_DIR" | awk 'NR==2 {print $4}')
        local FREE_GB=$((FREE_KB / 1024 / 1024))
        if [[ "$FREE_GB" -lt "$MIN_FREE_GB" ]]; then
            echo -e " \033[1;31m💾 SPEICHER\033[0m - KRITISCH! Nur noch ${FREE_GB} GB frei in $VIDEO_DIR"
        else
            echo -e " \033[1;32m💾 SPEICHER\033[0m - OK (${FREE_GB} GB frei in $VIDEO_DIR)"
        fi
    else
        echo -e " \033[1;31m💾 SPEICHER\033[0m - FEHLER ($VIDEO_DIR nicht erreichbar!)"
    fi

    # 3. Import-Warteschlange
    if [[ -d "$IMPORT_DIR" ]]; then
        local QUEUE_COUNT=$(find "$IMPORT_DIR" -maxdepth 2 -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.ts" -o -name "*.avi" -o -name "*.mov" \) 2>/dev/null | wc -l)
        local SKIPPED_COUNT=$(find "$IMPORT_DIR" -maxdepth 2 -type f -name "*.skipped" 2>/dev/null | wc -l)
        
        if [[ $QUEUE_COUNT -gt 0 && $SKIPPED_COUNT -gt 0 ]]; then
            echo -e " \033[1;33m📥 IMPORT\033[0m   - $QUEUE_COUNT Datei(en) warten, \033[1;31m$SKIPPED_COUNT abgelehnt (.skipped)\033[0m"
        elif [[ $QUEUE_COUNT -gt 0 ]]; then
            echo -e " \033[1;33m📥 IMPORT\033[0m   - $QUEUE_COUNT Datei(en) warten auf Verarbeitung"
        elif [[ $SKIPPED_COUNT -gt 0 ]]; then
            echo -e " \033[1;31m📥 IMPORT\033[0m   - \033[1;31m$SKIPPED_COUNT Datei(en) abgelehnt (.skipped)\033[0m (Nutze 'confirm' Kommando)"
        else
            echo -e " \033[1;32m📥 IMPORT\033[0m   - Leer (Alles erledigt)"
        fi
    fi

    # 3b. Erledigte Importe (Sitzungsverlauf)
    if [[ -s "$SESSION_FILE" ]]; then
        local SESSION_TEXT="Letzte Sitzung"
        [[ $IS_RUNNING -eq 1 ]] && SESSION_TEXT="Diese Sitzung"
        echo -e " \033[1;32m✅ ERLEDIGT\033[0m   - $SESSION_TEXT importiert:"
        while read -r imported_title; do
            echo -e "              - \033[0;37m$imported_title\033[0m"
        done < "$SESSION_FILE"
    fi

    # 4. Live-Log mit farblichem Highlighting
    echo -e "\n\033[1;37m 📋 Letzte Log-Aktivitäten:\033[0m"
    echo -e "\033[1;30m--------------------------------------------------------\033[0m"
    if [[ -f "$LOG_FILE" ]]; then
        # 'grep -v "frame="' filtert den FFmpeg-Fortschritts-Spam aus der Anzeige heraus
        tail -n 40 "$LOG_FILE" 2>/dev/null | grep -v "frame=" | tail -n 8 | while read -r line; do
            if [[ "$line" == *"FEHLER"* || "$line" == *"KRITISCH"* ]]; then
                echo -e "\033[0;31m$line\033[0m" # Rot
            elif [[ "$line" == *"WARNUNG"* || "$line" == *"verdächtig"* ]]; then
                echo -e "\033[0;33m$line\033[0m" # Gelb
            elif [[ "$line" == *"erfolgreich"* || "$line" == *"ERFOLG"* ]]; then
                echo -e "\033[0;32m$line\033[0m" # Grün
            else
                echo -e "\033[0;37m$line\033[0m" # Weiß
            fi
        done
    else
        echo -e "\033[0;37m Noch keine Log-Einträge vorhanden.\033[0m"
    fi
    echo -e "\033[1;36m========================================================\033[0m\n"

    # --- HTML Dashboard synchronisieren ---
    [[ "${HTML_DASHBOARD:-0}" -eq 1 ]] && export_html_status 2>/dev/null
}

# --- NEU: OSD-optimierter Status (Ohne Farben/Umlaute für den TV) ---
show_osd_status() {
    echo "====================================================="
    echo " VDR-Rectools - OSD Status"
    echo "====================================================="

    local PID=""
    local IS_RUNNING=0
    if [[ -f "$LOCK_FILE" ]]; then
        PID=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
            if ps -p "$PID" -o comm= 2>/dev/null | grep -q -E "bash|sh|vdr-rectools|ffmpeg"; then
                IS_RUNNING=1
            fi
        fi
    fi

    if [[ $IS_RUNNING -eq 1 ]]; then
        local RUNTIME=$(ps -p "$PID" -o etime= 2>/dev/null | tr -d ' ')
        local CURRENT_ACTION="Arbeitet..."
        [[ -f "$STATE_FILE" ]] && CURRENT_ACTION=$(cat "$STATE_FILE" 2>/dev/null | tr 'äöüÄÖÜß' 'aeoeueAeOeUess')
        echo " STATUS  : AKTIV (PID: $PID, seit $RUNTIME)"
        echo " AKTUELL : $CURRENT_ACTION"
        
        local PROMPT_FILE="$VIDEO_DIR/.vdr-rectools.prompt"
        if [[ -f "$PROMPT_FILE" ]]; then
            local P_TITLE=$(cut -d'|' -f2 "$PROMPT_FILE" 2>/dev/null | tr 'äöüÄÖÜß' 'aeoeueAeOeUess')
            echo " "
            echo " *** AKTION ERFORDERLICH ***"
            echo " Re-Encode bestaetigen fuer:"
            echo " $P_TITLE"
            echo " -> Bitte das Menue 'Re-Encode ausstehend' nutzen!"
        fi
        
        if [[ -f "$DURATION_FILE" ]]; then
            local TOT_SEC=$(cat "$DURATION_FILE" 2>/dev/null)
            if [[ -n "$TOT_SEC" && "$TOT_SEC" =~ ^[0-9]+$ && "$TOT_SEC" -gt 0 ]]; then
                local LAST_TIME=$(tail -n 50 "$LOG_FILE" 2>/dev/null | grep -oE 'time=[ ]*[0-9]+:[0-9]{2}:[0-9]{2}' | tail -n 1 | cut -d= -f2 | tr -d ' ')
                if [[ -n "$LAST_TIME" ]]; then
                    local H=$(echo "$LAST_TIME" | cut -d: -f1); local M=$(echo "$LAST_TIME" | cut -d: -f2); local S=$(echo "$LAST_TIME" | cut -d: -f3)
                    local CUR_SEC=$(( 10#$H * 3600 + 10#$M * 60 + 10#$S ))
                    local PERCENT=$(( CUR_SEC * 100 / TOT_SEC ))
                    [[ $PERCENT -gt 100 ]] && PERCENT=100
                    
                    local FILLED=$(( PERCENT / 5 ))
                    local EMPTY=$(( 20 - FILLED ))
                    local BAR=""
                    for ((i=0; i<FILLED; i++)); do BAR="${BAR}#"; done
                    for ((i=0; i<EMPTY; i++)); do BAR="${BAR}-"; done
                    echo " FORTSCHR. [$BAR] $PERCENT%"
                    
                    local SPEED=$(tail -n 50 "$LOG_FILE" 2>/dev/null | grep -o 'speed=[ ]*[0-9.]*x' | tail -n 1 | sed 's/speed=//;s/x//;s/ //g')
                    if [[ -n "$SPEED" && "$SPEED" != "0" && "$SPEED" != "0.0" ]]; then
                        local REM_SEC=$(( TOT_SEC - CUR_SEC ))
                        if [[ $REM_SEC -gt 0 ]]; then
                            local ETA_SEC=$(awk -v rem="$REM_SEC" -v spd="$SPEED" 'BEGIN { if(spd>0) printf "%d", rem/spd; else print 0 }')
                            if [[ "$ETA_SEC" -gt 0 ]]; then
                                local ETA_M=$(( (ETA_SEC % 3600) / 60 )); local ETA_S=$(( ETA_SEC % 60 ))
                                echo " RESTZEIT  $(printf "%02d:%02d" $ETA_M $ETA_S) Min. (bei ${SPEED}x Speed)"
                            fi
                        fi
                    fi
                fi
            fi
        fi
    else
        echo " STATUS  : INAKTIV (Wartet auf Arbeit)"
    fi
    
    echo "====================================================="
    echo " Letzte Aktivitaeten:"
    if [[ -f "$LOG_FILE" ]]; then
        # Filtert Ladebalken raus, übersetzt Umlaute und kürzt die Zeile für den TV
        tail -n 40 "$LOG_FILE" 2>/dev/null | grep -v "frame=" | tail -n 6 | tr 'äöüÄÖÜß' 'aeoeueAeOeUess' | cut -c 1-52
    else
        echo " Noch keine Log-Eintraege vorhanden."
    fi
    echo "====================================================="
}

# --- NEU: HTML Web-Dashboard Generator ---
export_html_status() {
    local HTML="${HTML_PATH:-/var/www/html/rectools.html}"
    [[ -z "$HTML" ]] && return
    
    local PID=""
    local IS_RUNNING=0
    if [[ -f "$LOCK_FILE" ]]; then
        PID=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
            IS_RUNNING=1
        fi
    fi

    local STATUS_TEXT="<span style='color: #888;'>⚪ INAKTIV (Wartet auf Arbeit)</span>"
    local PROGRESS_HTML=""
    
    if [[ $IS_RUNNING -eq 1 ]]; then
        local CURRENT_ACTION="Arbeitet..."
        [[ -f "$STATE_FILE" ]] && CURRENT_ACTION=$(cat "$STATE_FILE" 2>/dev/null | sed 's/</\&lt;/g; s/>/\&gt;/g')
        STATUS_TEXT="<span style='color: #4CAF50;'>🟢 AKTIV</span> - $CURRENT_ACTION"
        
        if [[ -f "$DURATION_FILE" ]]; then
            local TOT_SEC=$(cat "$DURATION_FILE" 2>/dev/null)
            if [[ -n "$TOT_SEC" && "$TOT_SEC" =~ ^[0-9]+$ && "$TOT_SEC" -gt 0 ]]; then
                local LAST_TIME=$(tail -n 50 "$LOG_FILE" 2>/dev/null | grep -oE 'time=[ ]*[0-9]+:[0-9]{2}:[0-9]{2}' | tail -n 1 | cut -d= -f2 | tr -d ' ')
                if [[ -n "$LAST_TIME" ]]; then
                    local H=$(echo "$LAST_TIME" | cut -d: -f1); local M=$(echo "$LAST_TIME" | cut -d: -f2); local S=$(echo "$LAST_TIME" | cut -d: -f3)
                    local CUR_SEC=$(( 10#$H * 3600 + 10#$M * 60 + 10#$S ))
                    local PERCENT=$(( CUR_SEC * 100 / TOT_SEC ))
                    [[ $PERCENT -gt 100 ]] && PERCENT=100
                    
                    local SPEED=$(tail -n 50 "$LOG_FILE" 2>/dev/null | grep -o 'speed=[ ]*[0-9.]*x' | tail -n 1 | sed 's/speed=//;s/x//;s/ //g')
                    local ETA_STR=""
                    if [[ -n "$SPEED" && "$SPEED" != "0" && "$SPEED" != "0.0" ]]; then
                        local REM_SEC=$(( TOT_SEC - CUR_SEC ))
                        if [[ $REM_SEC -gt 0 ]]; then
                            local ETA_SEC=$(awk -v rem="$REM_SEC" -v spd="$SPEED" 'BEGIN { if(spd>0) printf "%d", rem/spd; else print 0 }')
                            if [[ "$ETA_SEC" -gt 0 ]]; then
                                local ETA_M=$(( (ETA_SEC % 3600) / 60 )); local ETA_S=$(( ETA_SEC % 60 ))
                                ETA_STR=" | Restzeit: $(printf "%02d:%02d" $ETA_M $ETA_S) Min."
                            fi
                        fi
                    fi
                    PROGRESS_HTML="<div style='margin-top: 15px; background: #333; border-radius: 5px; width: 100%; height: 25px; overflow: hidden; box-shadow: inset 0 1px 3px rgba(0,0,0,0.5);'><div style='background: #2196F3; width: ${PERCENT}%; height: 100%; text-align: center; color: white; line-height: 25px; font-size: 14px; font-weight: bold; white-space: nowrap;'>${PERCENT}%${ETA_STR}</div></div>"
                fi
            fi
        fi
    fi
    
    local PROMPT_HTML=""
    local PROMPT_FILE="$VIDEO_DIR/.vdr-rectools.prompt"
    local HAS_PROMPT=0
    if [[ -f "$PROMPT_FILE" ]]; then
        local P_STATUS=$(cut -d'|' -f1 "$PROMPT_FILE" 2>/dev/null)
        if [[ "$P_STATUS" == "WAIT" ]]; then
            HAS_PROMPT=1
            local P_TITLE=$(cut -d'|' -f2 "$PROMPT_FILE" 2>/dev/null | sed 's/&/&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            PROMPT_HTML="<div style='margin-top: 20px; background: rgba(58, 42, 0, 0.8); color: #ffeb3b; padding: 15px; border-radius: 8px; border: 1px solid #ffc107;'>"
            PROMPT_HTML+="<strong style='font-size: 1.1em;'>⚠️ AKTION ERFORDERLICH: Re-Encode</strong><br>"
            PROMPT_HTML+="<div style='margin-bottom: 15px; margin-top: 5px; color: #fff;'>Der Film <b>$P_TITLE</b> erfordert einen Re-Encode. Starten?</div>"
            PROMPT_HTML+="<a href='rectools_confirm.php?action=yes' style='display: inline-block; background: #4CAF50; color: white; padding: 8px 15px; text-decoration: none; border-radius: 4px; font-weight: bold; margin-right: 10px;'>✔️ JA, Starten</a>"
            PROMPT_HTML+="<a href='rectools_confirm.php?action=no' style='display: inline-block; background: #F44336; color: white; padding: 8px 15px; text-decoration: none; border-radius: 4px; font-weight: bold;'>❌ NEIN, Überspringen</a>"
            PROMPT_HTML+="</div>"
        fi
    fi
    
    if [[ $HAS_PROMPT -eq 0 ]]; then
        PROMPT_HTML="<div style='margin-top: 20px; background: rgba(0,0,0,0.3); color: #555; padding: 15px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.05);'>"
        PROMPT_HTML+="<strong style='font-size: 1.1em;'>ℹ️ Keine Aktion erforderlich</strong><br>"
        PROMPT_HTML+="<div style='margin-bottom: 15px; margin-top: 5px; color: #555;'>Aktuell stehen keine manuellen Best&auml;tigungen f&uuml;r Re-Encodes aus.</div>"
        # Nutze <span> statt <a>, damit die Buttons im inaktiven Zustand nicht angeklickt werden können
        PROMPT_HTML+="<span style='display: inline-block; background: rgba(255,255,255,0.1); color: #555; padding: 8px 15px; border-radius: 4px; font-weight: bold; margin-right: 10px; cursor: not-allowed;'>✔️ JA, Starten</span>"
        PROMPT_HTML+="<span style='display: inline-block; background: rgba(255,255,255,0.1); color: #555; padding: 8px 15px; border-radius: 4px; font-weight: bold; cursor: not-allowed;'>❌ NEIN, &Uuml;berspringen</span>"
        PROMPT_HTML+="</div>"
    fi
    
    local SESSION_HTML=""
    if [[ -s "$SESSION_FILE" ]]; then
        local SESSION_TEXT="Letzte Sitzung"
        [[ $IS_RUNNING -eq 1 ]] && SESSION_TEXT="Diese Sitzung"
        SESSION_HTML="<div style='margin-top: 15px; background: rgba(30, 58, 30, 0.8); color: #4CAF50; padding: 10px; border-radius: 5px; border: 1px solid #4CAF50;'>"
        SESSION_HTML+="<strong>✅ $SESSION_TEXT importiert:</strong><ul style='margin-top: 5px; margin-bottom: 0; padding-left: 20px; color: #fff;'>"
        while read -r imported_title; do
            local safe_title=$(echo "$imported_title" | sed 's/&/&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            SESSION_HTML+="<li>$safe_title</li>"
        done < "$SESSION_FILE"
        SESSION_HTML+="</ul></div>"
    fi

    local DISK_HTML=""
    if [[ -d "$VIDEO_DIR" ]]; then
        local FREE_KB=$(df -Pk "$VIDEO_DIR" | awk 'NR==2 {print $4}')
        local FREE_GB=$((FREE_KB / 1024 / 1024))
        local DISK_COLOR="#4CAF50"
        [[ "$FREE_GB" -lt "$MIN_FREE_GB" ]] && DISK_COLOR="#F44336"
        DISK_HTML="Speicher $VIDEO_DIR: <span style='color: $DISK_COLOR; font-weight: bold;'>${FREE_GB} GB frei</span>"
    fi

    local LOG_HTML=""
    if [[ -f "$LOG_FILE" ]]; then
        LOG_HTML=$(tail -n 40 "$LOG_FILE" 2>/dev/null | grep -v "frame=" | tail -n 12 | sed 's/&/&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' | awk '{
            if ($0 ~ /FEHLER/ || $0 ~ /KRITISCH/) print "<span style=\"color: #F44336;\">" $0 "</span><br>";
            else if ($0 ~ /WARNUNG/ || $0 ~ /verdächtig/) print "<span style=\"color: #FFC107;\">" $0 "</span><br>";
            else if ($0 ~ /erfolgreich/ || $0 ~ /ERFOLG/) print "<span style=\"color: #4CAF50;\">" $0 "</span><br>";
            else print "<span style=\"color: #ccc;\">" $0 "</span><br>";
        }')
    fi

    local BG_IMG_PATH="$(dirname "${HTML_PATH:-/var/www/html/rectools.html}")/dashboard_bg.jpg"
    local BODY_CSS="background-color: #121212;"
    if [[ -f "$BG_IMG_PATH" && $IS_RUNNING -eq 1 ]]; then
        BODY_CSS="background: linear-gradient(rgba(18, 18, 18, 0.75), rgba(18, 18, 18, 0.95)), url('dashboard_bg.jpg?t=$(date +%s)') no-repeat center center fixed; background-size: cover;"
    fi

    local TMP_HTML="/tmp/vdr-rectools-dashboard.tmp"
    cat <<EOF > "$TMP_HTML"
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="5">
    <title>🎬 VDR-Rectools Dashboard</title>
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
        <h2>🎬 VDR-Rectools - Live Dashboard</h2>
        
        <div class="status-box">
            <strong>Status:</strong> $STATUS_TEXT
            $PROGRESS_HTML
            $PROMPT_HTML
            $SESSION_HTML
        </div>
        
        <div class="status-box" style="font-size: 0.95em;">
            <strong>💾 Festplatte:</strong> $DISK_HTML
        </div>

        <h3 style="color: #bbb; font-size: 1.1em; margin-bottom: 10px;">📋 Letzte Log-Aktivitäten</h3>
        <div class="log-box">
            $LOG_HTML
        </div>
        
        <div class="footer">Auto-Refresh (5s) | Letzte Aktualisierung: $(date +"%d.%m.%Y %H:%M:%S")</div>
    </div>
</body>
</html>
EOF
    cat "$TMP_HTML" > "$HTML" 2>/dev/null || true
    rm -f "$TMP_HTML" 2>/dev/null || true
}
