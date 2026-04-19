#!/bin/bash
# ==============================================================================
# vdr-rectools - Core Functions (V1.7.3)
# ==============================================================================

# 1. HARDCODED DEFAULTS (Sicherheitsnetz)
VIDEO_DIR="/srv/vdr/video"
IMPORT_DIR="/srv/vdr/import"
REPAIR_STAGING="/srv/vdr/tmp/staging"
SNAPSHOT_TIME="00:05:00"
MAIL_NOTIFY=""
AUTO_SUB_DOWNLOAD=1
MIN_FREE_GB=50
MAX_FILES=5
LOG_FILE="/var/log/vdr-rectools.log"

# 2. CONFIG EINLESEN (Der neue Standard-Pfad via Debconf)
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
    [[ -z "$MAIL_NOTIFY" ]] && return

    echo -e "$BODY\n\n--- Letzte Log-Eintraege ---\n$(tail -n 20 $LOG_FILE)" | \
    mail -s "VDR-Rectools: $SUBJECT" "$MAIL_NOTIFY"
}

check_disk_space() {
    local FREE_KB=$(df -Pk "$VIDEO_DIR" | awk 'NR==2 {print $4}')
    local FREE_GB=$((FREE_KB / 1024 / 1024))
    [[ "$FREE_GB" -lt "$MIN_FREE_GB" ]] && return 1
    return 0
}

process_import() {
    local SOURCE_FILE="$1"
    local MODE="$2"
    local FILENAME=$(basename "$SOURCE_FILE")
    local FILM_TITLE="${FILENAME%.*}"
    local CLEAN_NAME=$(echo "$FILM_TITLE" | sed 's/[^a-zA-Z0-9._-]/_/g')

    # REL_PATH Logik für Unterordner im Import
    local REL_PATH=$(dirname "${SOURCE_FILE#$IMPORT_DIR/}")
    local TARGET_SUBDIR=""
    [[ "$REL_PATH" != "." ]] && TARGET_SUBDIR="$REL_PATH/"

    # Codec Check via ffprobe
    local VCODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$SOURCE_FILE" 2>/dev/null)
    if [[ ! "$VCODEC" =~ ^(h264|mpeg2video|hevc)$ ]]; then
        echo "[$(date +%T)] IMPORT ABGELEHNT: Codec $VCODEC in $FILENAME" >> "$LOG_FILE"
        return 1
    fi

    [[ "$MODE" == "dryrun" ]] && { echo "[DRY-RUN] Import $FILENAME -> $TARGET_SUBDIR"; return 0; }
    
    check_disk_space || { echo "[$(date +%T)] FEHLER: Zu wenig Speicherplatz für $FILENAME" >> "$LOG_FILE"; return 1; }

    local DATE_STR=$(date +"%Y-%m-%d.%H.%M.1-0.rec")
    local STAGING_REC="$REPAIR_STAGING/import_$CLEAN_NAME"
    local FINAL_DEST="$VIDEO_DIR/${TARGET_SUBDIR}$CLEAN_NAME/$DATE_STR"

    mkdir -p "$STAGING_REC"
    
    # Audio Params holen und remuxen
    local AUDIO_PARAMS=$(get_audio_map)
    ffmpeg -y -i "$SOURCE_FILE" $AUDIO_PARAMS -copyts -fflags +genpts -f mpegts "$STAGING_REC/00001.ts" </dev/null >/dev/null 2>&1

    if [ -f "$STAGING_REC/00001.ts" ]; then
        echo "T $CLEAN_NAME" > "$STAGING_REC/info"
        echo "D Importiert am $(date +"%d.%m.%Y")" >> "$STAGING_REC/info"
        
        /usr/bin/vdr --genindex="$STAGING_REC" >/dev/null 2>&1
        
        if [[ "$AUTO_SUB_DOWNLOAD" -eq 1 ]]; then
            subliminal download -l "${SUB_LANG:-de}" -d "$STAGING_REC" "$SOURCE_FILE" >/dev/null 2>&1
            local DOWNLOADED_SRT=$(find "$STAGING_REC" -maxdepth 1 -name "*.srt" | head -n 1)
            [[ -f "$DOWNLOADED_SRT" ]] && mv "$DOWNLOADED_SRT" "$STAGING_REC/00001.srt"
        fi

        mkdir -p "$(dirname "$FINAL_DEST")"
        mv "$STAGING_REC" "$FINAL_DEST"
        chown -R vdr:vdr "$VIDEO_DIR/${TARGET_SUBDIR}$CLEAN_NAME"

        process_folder "$FINAL_DEST" "normal"
        touch "$VIDEO_DIR/.update"
        rm -f "$SOURCE_FILE"
        
        send_mail "Der Film '$CLEAN_NAME' wurde erfolgreich importiert." "Import erfolgreich: $CLEAN_NAME"
        return 0
    fi
    return 1
}

process_folder() {
    local REC_DIR="$1"
    local MODE="$2"
    [[ ! -d "$REC_DIR" ]] && return 1
    cd "$REC_DIR" || return 1

    local FILM_TITLE=$(grep "^T " info 2>/dev/null | head -n 1 | cut -c3- | tr -d '\r' | sed 's/[^a-zA-Z0-9._-]/_/g')
    [[ -z "$FILM_TITLE" ]] && FILM_TITLE=$(basename "$(dirname "$REC_DIR")")

    local CLEAN_NAME=$(echo "$FILM_TITLE" | sed 's/_/ /g')
    local NEW_VDR_FILE="00001.ts"
    local PLEX_LINK="$CLEAN_NAME.ts"

    if ls 000[0-9][0-9].ts 2>/dev/null | grep -qv "00001.ts"; then
        [[ "$MODE" != "dryrun" ]] && {
            cat $(ls -v 000[0-9][0-9].ts | grep -v "00001.ts") > "00001.ts.tmp"
            rm 000[0-9][0-9].ts index marks 2>/dev/null
            mv "00001.ts.tmp" "00001.ts"
            /usr/bin/vdr --genindex=. >/dev/null 2>&1
        }
    fi

    if [[ -f "$NEW_VDR_FILE" && "$MODE" != "dryrun" ]]; then
        [[ ! -L "$PLEX_LINK" ]] && ln -sf "$NEW_VDR_FILE" "$PLEX_LINK"
        
        if [[ -f "00001.srt" && ! -f "${PLEX_LINK%.ts}.srt" ]]; then
            ln -sf "00001.srt" "${PLEX_LINK%.ts}.srt"
        elif [[ ! -f "${PLEX_LINK%.ts}.srt" ]]; then
            extract_subtitles "$NEW_VDR_FILE"
        fi
        
        extract_images "$NEW_VDR_FILE"

        local NFO_FILE="${PLEX_LINK%.ts}.nfo"
        if [[ ! -f "$NFO_FILE" && -f "info" ]]; then
            local NFO_TITLE=$(grep "^T " info | head -n 1 | cut -c3- | tr -d '\r' | sed 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g')
            local NFO_DESC=$(grep "^D " info | cut -c3- | tr -d '\r' | sed 's/|/\n/g; s/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g')
            echo -e "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<movie>\n  <title>${NFO_TITLE}</title>\n  <plot>${NFO_DESC}</plot>\n</movie>" > "$NFO_FILE"
            chown vdr:vdr "$NFO_FILE" 2>/dev/null || true
        fi
    fi
}

run_scan() {
    local MODE="$1"
    local COUNT=0
    find "$IMPORT_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.ts" \) | while read -r FILE; do
        [[ $COUNT -ge "$MAX_FILES" ]] && break
        process_import "$FILE" "$MODE" && ((COUNT++))
    done
    
    while read -r DIR; do
        process_folder "$DIR" "$MODE"
    done < <(find -L "$VIDEO_DIR" -type d -name "*.rec" | sort)
}
