#!/bin/bash
# ==============================================================================
# vdr-rectools - Media Processing Library
# ==============================================================================

extract_subtitles() {
    ffmpeg -y -i "$1" -an -vn -c:s srt "${1%.ts}.srt" </dev/null >/dev/null 2>&1
    chown vdr:vdr "${1%.ts}.srt" 2>/dev/null || true
}

get_audio_map() {
    # Nimmt Video und Audio, wirft aber Spuren mit "visual_impaired" (Audio-Description) ab
    echo "-map 0:v -map 0:a -map -0:a:m:disposition:visual_impaired? -c copy"
}

shrink_video() {
    local OUT="${1%.ts}_HEVC.ts"
    local LOG_FILE="/var/log/vdr-rectools.log"

    # Prüfen, ob die Datei bereits in H.265 vorliegt
    local CURRENT_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null)
    if [[ "$CURRENT_CODEC" == "hevc" ]]; then
        echo "[$(date +%T)] SHRINK: $1 ist bereits in H.265 (HEVC). Abbruch." >> "$LOG_FILE"
        return 0
    fi
    local INPUT_FILE_SIZE=$(stat -c %s "$1" 2>/dev/null || echo 0)
    echo "Starte H.265 Kompression für $1" >> "$LOG_FILE"
    ffmpeg -y -i "$1" -c:v libx265 -crf "${CRF_H265_DEFAULT:-23}" -preset "${PRESET_H265_DEFAULT:-medium}" -c:a copy -max_muxing_queue_size 4000 "$OUT" </dev/null >/dev/null 2>&1
    if [ -f "$OUT" ]; then
        if ! check_size "$1" "$OUT" "${MIN_COMPRESSION_RATIO_H265:-50}" "Shrink"; then
            echo "[$(date +%T)] FEHLER: Shrink für $1 fehlgeschlagen oder Ergebnis verdächtig. Originaldatei bleibt erhalten." >> "$LOG_FILE"
            send_mail "Shrink für '$1' fehlgeschlagen oder Ergebnis verdächtig. Originaldatei bleibt erhalten." "Shrink-Fehler"
            rm -f "$OUT" # Die fehlerhafte Ausgabedatei löschen
            return 1
        fi
        mv "$OUT" "$1"
        /usr/bin/vdr --genindex="$(dirname "$1")" >/dev/null 2>&1
    fi
}

apply_vdr_marks() {
    echo "Werbeschnitt (via Marks) in Vorbereitung für $1" >> "/var/log/vdr-rectools.log"
}

extract_images() {
    local VIDEO_FILE="$1"
    local DEST_DIR="$(dirname "$VIDEO_FILE")"
    
    # Nutze SNAPSHOT_TIME aus vdr-rectools.conf, Fallback auf 00:05:00
    local SEEK_POINT="${SNAPSHOT_TIME:-00:05:00}"

    # 1. Versuch: Eingebettetes Cover extrahieren (falls vorhanden)
    ffmpeg -y -i "$VIDEO_FILE" -map 0:v -map -0:V -c copy "$DEST_DIR/poster.jpg" </dev/null >/dev/null 2>&1

    # 2. Versuch: Falls poster.jpg fehlt oder zu klein ist (< 10kb), Snapshot erstellen
    if [ ! -f "$DEST_DIR/poster.jpg" ] || [ $(stat -c%s "$DEST_DIR/poster.jpg" 2>/dev/null || echo 0) -lt 10000 ]; then
        # -update 1 sorgt dafür, dass ein einzelnes Bild geschrieben wird
        echo "[$(date +%T)] Erstelle Poster-Snapshot bei $SEEK_POINT..." >> "/var/log/vdr-rectools.log"
        ffmpeg -y -ss "$SEEK_POINT" -i "$VIDEO_FILE" -frames:v 1 -update 1 -q:v 2 "$DEST_DIR/poster.jpg" </dev/null >/dev/null 2>&1
    fi

    # Fanart kopieren, falls poster.jpg erfolgreich war
    if [ -f "$DEST_DIR/poster.jpg" ]; then
        cp "$DEST_DIR/poster.jpg" "$DEST_DIR/fanart.jpg"
        chown vdr:vdr "$DEST_DIR/poster.jpg" "$DEST_DIR/fanart.jpg" 2>/dev/null || true
    fi
}
