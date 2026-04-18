# ==============================================================================
# vdr-rectools - V1.7.2 (Core Library)
# ==============================================================================
source /usr/share/vdr-rectools/media_tools.sh

send_mail() {
    local BODY="$1"
    local SUBJECT="$2"
    local LOG_PATH="/var/log/vdr-rectools.log"
    local RECIPIENT="$MAIL_NOTIFY"

    [[ -z "$RECIPIENT" ]] && return

    local TMP_LOG="/tmp/rectools_mail_log.txt"
    tail -n 100 "$LOG_PATH" > "$TMP_LOG"
    
    local LOG_CONTENT=$(cat "$TMP_LOG")
    echo -e "$BODY\n\n--- Letzte 100 Zeilen aus dem Log ---\n$LOG_CONTENT" | \
    mail -s "VDR-Rectools: $SUBJECT" "$RECIPIENT"
    
    rm -f "$TMP_LOG"
}

check_disk_space() {
    local FREE_KB=$(df -Pk "$VIDEO_DIR" | awk 'NR==2 {print $4}')
    local FREE_GB=$((FREE_KB / 1024 / 1024))
    if [[ "$FREE_GB" -lt "$MIN_FREE_GB" ]]; then
        return 1
    fi
    return 0
}

cleanup_empty_dirs() {
    find "$VIDEO_DIR" -mindepth 1 -type d -empty -exec rmdir {} + 2>/dev/null
}

process_import() {
    local SOURCE_FILE="$1"
    local MODE="$2"
    local FILENAME=$(basename "$SOURCE_FILE")
    local FILM_TITLE="${FILENAME%.*}"
    local CLEAN_NAME=$(echo "$FILM_TITLE" | sed 's/[^a-zA-Z0-9._-]/_/g')

    local REL_PATH=$(dirname "${SOURCE_FILE#$IMPORT_DIR/}")
    local TARGET_SUBDIR=""
    if [[ "$REL_PATH" != "." ]]; then
        TARGET_SUBDIR="$REL_PATH/"
    fi

    local VCODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$SOURCE_FILE" 2>/dev/null)
    if [[ ! "$VCODEC" =~ ^(h264|mpeg2video|hevc)$ ]]; then
        echo "[$(date +%T)] IMPORT ABGELEHNT: Codec $VCODEC in $FILENAME" >> "$LOG_FILE"
        return 1
    fi

    if [[ "$MODE" == "dryrun" ]]; then
        echo "[DRY-RUN] Import $FILENAME -> $TARGET_SUBDIR"
        return 0
    fi

    check_disk_space || return 1

    local DATE_STR=$(date +"%Y-%m-%d.%H.%M.1-0.rec")
    local STAGING_REC="$REPAIR_STAGING/import_$CLEAN_NAME"
    local FINAL_DEST="$VIDEO_DIR/${TARGET_SUBDIR}$CLEAN_NAME/$DATE_STR"

    mkdir -p "$STAGING_REC"
    ffmpeg -y -i "$SOURCE_FILE" -map 0:v -map 0:a -map -0:a:m:disposition:visual_impaired? -c copy -copyts -fflags +genpts -f mpegts "$STAGING_REC/00001.ts" </dev/null >/dev/null 2>&1

    if [ -f "$STAGING_REC/00001.ts" ]; then
        echo "T $CLEAN_NAME" > "$STAGING_REC/info"
        echo "D Importiert am $(date +"%d.%m.%Y")" >> "$STAGING_REC/info"
        /usr/bin/vdr --genindex="$STAGING_REC" >/dev/null 2>&1
        mkdir -p "$(dirname "$FINAL_DEST")"

        if [[ "$AUTO_SUB_DOWNLOAD" -eq 1 ]]; then
            echo "Suche Untertitel (${SUB_LANG:-de}) online für: $FILENAME" >> "$LOG_FILE"
            subliminal download -l "${SUB_LANG:-de}" -d "$STAGING_REC" "$SOURCE_FILE" >/dev/null 2>&1
            local DOWNLOADED_SRT=$(find "$STAGING_REC" -maxdepth 1 -name "*.srt" | head -n 1)
            if [[ -f "$DOWNLOADED_SRT" ]]; then
                mv "$DOWNLOADED_SRT" "$STAGING_REC/00001.srt"
                echo "Untertitel erfolgreich gefunden und integriert." >> "$LOG_FILE"
            fi
        fi

        mv "$STAGING_REC" "$FINAL_DEST"
        chown -R vdr:vdr "$VIDEO_DIR/${TARGET_SUBDIR}$CLEAN_NAME"

        process_folder "$FINAL_DEST" "normal"

        touch "$VIDEO_DIR/.update"
        rm -f "$SOURCE_FILE"

        send_mail "Der Film/Die Serie '$CLEAN_NAME' wurde erfolgreich importiert." "Import abgeschlossen: $CLEAN_NAME"
        return 0
    fi
    return 1
}

process_folder() {
    local REC_DIR="$1"
    local MODE="$2"

    if [[ ! -d "$REC_DIR" ]]; then
        return 1
    fi

    cd "$REC_DIR" || return 1

    local FILM_TITLE=$(grep "^T " info | head -n 1 | cut -c3- | tr -d '\r' | sed 's/[^a-zA-Z0-9._-]/_/g')
    if [[ -z "$FILM_TITLE" ]]; then
        FILM_TITLE=$(basename "$(dirname "$REC_DIR")")
    fi

    local CLEAN_NAME=$(echo "$FILM_TITLE" | sed 's/_/ /g')
    local NEW_VDR_FILE="00001.ts"
    local PLEX_LINK="$CLEAN_NAME.ts"

    if ls 000[0-9][0-9].ts 2>/dev/null | grep -qv "00001.ts"; then
        if [[ "$MODE" != "dryrun" ]]; then
            cat $(ls -v 000[0-9][0-9].ts | grep -v "00001.ts") > "00001.ts.tmp"
            rm 000[0-9][0-9].ts index marks 2>/dev/null
            mv "00001.ts.tmp" "00001.ts"
            /usr/bin/vdr --genindex=. >/dev/null 2>&1
        fi
    fi

    if [[ "$MODE" == "repair" && -f "$NEW_VDR_FILE" ]]; then
        check_disk_space || return 1
        local TARGET_FILE="$REPAIR_STAGING/${FILM_TITLE}_REPAIRED.ts"
        local A_MAP=$(get_audio_map "$NEW_VDR_FILE")

        ffmpeg -y -threads 1 -fflags +genpts -i "$NEW_VDR_FILE" $A_MAP -copyts -muxdelay 0 "$TARGET_FILE" </dev/null >/dev/null 2>&1

        if [ -f "$TARGET_FILE" ] && ffprobe -v error "$TARGET_FILE" 2>/dev/null; then
            local ORIG_SIZE=$(stat -c%s "$NEW_VDR_FILE")
            local NEW_SIZE=$(stat -c%s "$TARGET_FILE")
            local MIN_SIZE=$((ORIG_SIZE * 98 / 100))

            if [ "$NEW_SIZE" -ge "$MIN_SIZE" ]; then
                mv "$TARGET_FILE" "$NEW_VDR_FILE"
                /usr/bin/vdr --genindex=. >/dev/null 2>&1
                send_mail "Die Aufnahme '$FILM_TITLE' wurde erfolgreich repariert." "Reparatur erfolgreich: $FILM_TITLE"
            fi
        fi
    fi

    if [[ -f "$NEW_VDR_FILE" && "$MODE" != "dryrun" ]]; then
        if [[ ! -L "$PLEX_LINK" ]]; then
            ln -sf "$NEW_VDR_FILE" "$PLEX_LINK"
        fi

        if [[ -f "00001.srt" && ! -f "${PLEX_LINK%.ts}.srt" ]]; then
            ln -sf "00001.srt" "${PLEX_LINK%.ts}.srt"
        elif [[ ! -f "${PLEX_LINK%.ts}.srt" ]]; then
            extract_subtitles "$NEW_VDR_FILE"
        fi
        
        # Das hier muss immer laufen:
        extract_images "$NEW_VDR_FILE"

        local NFO_FILE="${PLEX_LINK%.ts}.nfo"
        if [[ ! -f "$NFO_FILE" && -f "info" ]]; then
            local NFO_TITLE=$(grep "^T " info | head -n 1 | cut -c3- | tr -d '\r' | sed 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g')
            local NFO_DESC=$(grep "^D " info | cut -c3- | tr -d '\r' | sed 's/|/\n/g; s/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g')
            echo "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" > "$NFO_FILE"
            echo "<movie>" >> "$NFO_FILE"
            echo "  <title>${NFO_TITLE}</title>" >> "$NFO_FILE"
            echo "  <plot>${NFO_DESC}</plot>" >> "$NFO_FILE"
            echo "</movie>" >> "$NFO_FILE"
            chown vdr:vdr "$NFO_FILE"
        fi
    fi
}

run_scan() {
    local MODE="$1"
    local COUNT=0
    find "$IMPORT_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" \) | while read -r FILE; do
        if [[ $COUNT -ge $MAX_FILES ]]; then
            break
        fi
        if process_import "$FILE" "$MODE"; then
            ((COUNT++))
        fi
    done

    while read -r DIR; do
        if [[ $COUNT -ge $MAX_FILES ]]; then
            break
        fi
        if process_folder "$DIR" "$MODE"; then
            ((COUNT++))
        fi
    done < <(find -L "$VIDEO_DIR" -type d -name "*.rec" | sort)

    cleanup_empty_dirs
    rm -f "$PID_FILE"
}
