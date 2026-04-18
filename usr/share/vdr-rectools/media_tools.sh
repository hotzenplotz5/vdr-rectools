# ==============================================================================
# vdr-rectools - V1.7.2 (Media Processing Library)
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

    # Prüfen, ob die Datei bereits in H.265 vorliegt
    local CURRENT_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$1" 2/dev/null)
    if [[ "$CURRENT_CODEC" == "hevc" ]]; then
        echo "[$(date +%T)] SHRINK: $1 ist bereits in H.265 (HEVC). Abbruch." >> "/var/log/vdr-rectools.log"
        return 0
    fi
    echo "Starte H.265 Kompression für $1" >> "/var/log/vdr-rectools.log"
    ffmpeg -y -i "$1" -c:v libx265 -crf 23 -preset medium -c:a copy "$OUT" </dev/null >/dev/null 2>&1
    if [ -f "$OUT" ]; then
        mv "$OUT" "$1"
        /usr/bin/vdr --genindex="$(dirname "$1")" >/dev/null 2>&1
    fi
}

apply_vdr_marks() {
    echo "Werbeschnitt (via Marks) in Vorbereitung für $1" >> "/var/log/vdr-rectools.log"
}
