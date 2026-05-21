#!/bin/bash
# ==============================================================================
# vdr-rectools - Media Processing Library
# ==============================================================================

extract_subtitles() {
    # Prüfen, ob überhaupt ein Untertitel-Stream existiert, um nutzlose FFmpeg-Aufrufe zu vermeiden
    if ffprobe -v error -select_streams s -show_entries stream=codec_type -of csv=p=0 "$1" 2>/dev/null | grep -q "subtitle"; then
        ffmpeg -y -i "$1" -an -vn -c:s srt "${1%.ts}.srt" </dev/null >/dev/null 2>&1
        chown vdr:vdr "${1%.ts}.srt" 2>/dev/null || true
    fi
}

get_audio_map() {
    # Nimmt Video und Audio, wirft aber Spuren mit "visual_impaired" (Audio-Description) ab
    echo "-map 0:v -map 0:a -map -0:a:m:disposition:visual_impaired? -c copy"
}

shrink_video() {
    local OUT="${1%.ts}_HEVC.ts"

    # Prüfen, ob die Datei bereits in H.265 vorliegt
    local CURRENT_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null | head -n 1 | tr -d '\r\n')
    if [[ "$CURRENT_CODEC" == "hevc" ]]; then
        echo "[$(date +%T)] SHRINK: $1 ist bereits in H.265 (HEVC). Abbruch." >> "$LOG_FILE"
        return 0
    fi
    local INPUT_FILE_SIZE=$(stat -c %s "$1" 2>/dev/null || echo 0)

    local FFMPEG_HW_OPTS=""
    local H265_ENC="libx265"
    case "$HW_ACCEL" in
        nvenc) FFMPEG_HW_OPTS="-hwaccel cuda -hwaccel_output_format cuda"; H265_ENC="hevc_nvenc" ;;
        vaapi) FFMPEG_HW_OPTS="-hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128"; H265_ENC="hevc_vaapi" ;;
        qsv) FFMPEG_HW_OPTS="-hwaccel qsv -hwaccel_output_format qsv"; H265_ENC="hevc_qsv" ;;
    esac

    echo "[$(date +%T)] Starte H.265 Kompression ($H265_ENC) für $1" >> "$LOG_FILE"
    ffmpeg -y $FFMPEG_HW_OPTS -i "$1" -c:v "$H265_ENC" -crf "${CRF_H265_DEFAULT:-23}" -preset "${PRESET_H265_DEFAULT:-medium}" -c:a copy -max_muxing_queue_size 4000 "$OUT" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
    
    local FF_STATUS=${PIPESTATUS[0]}
    if [[ $FF_STATUS -eq 0 && -f "$OUT" ]]; then
        if ! check_size "$1" "$OUT" "${MIN_COMPRESSION_RATIO_H265:-50}" "Shrink"; then
            echo "[$(date +%T)] FEHLER: Shrink für $1 fehlgeschlagen oder Ergebnis verdächtig. Originaldatei bleibt erhalten." >> "$LOG_FILE"
            send_mail "Shrink für '$1' fehlgeschlagen oder Ergebnis verdächtig. Originaldatei bleibt erhalten." "Shrink-Fehler"
            rm -f "$OUT" # Die fehlerhafte Ausgabedatei löschen
            return 1
        fi
        mv "$OUT" "$1"
        chown vdr:vdr "$1" 2>/dev/null || true
        /usr/bin/vdr --genindex="$(dirname "$1")" >/dev/null 2>&1
    else
        echo "[$(date +%T)] FEHLER: FFmpeg Shrink für $1 abgebrochen (Status $FF_STATUS)." >> "$LOG_FILE"
        rm -f "$OUT"
        return 1
    fi
}

apply_vdr_marks() {
    local TARGET_FILE="$1"
    local REC_DIR="$(dirname "$TARGET_FILE")"
    local MARKS_FILE="$REC_DIR/marks"
    local OUT_FILE="${TARGET_FILE%.ts}_cut.ts"
    
    echo "[$(date +%T)] Aktion: Starte automatischen Werbeschnitt für $TARGET_FILE" >> "$LOG_FILE"

    if [[ ! -f "$MARKS_FILE" ]]; then
        echo "[$(date +%T)] WARNUNG: Keine 'marks'-Datei in $REC_DIR gefunden. Es gibt nichts zu schneiden." >> "$LOG_FILE"
        return 1
    fi

    local segments=()
    local start_mark=""
    
    # Lese die Schnittmarken ein (Ungerade = Start, Gerade = Ende)
    while read -r line; do
        # Format: hh:mm:ss.ff [comment]
        local time_val=$(echo "$line" | awk '{print $1}')
        [[ -z "$time_val" ]] && continue
        
        # ffmpeg benötigt hh:mm:ss.ms
        local hhmmss=$(echo "$time_val" | cut -d'.' -f1)
        local ff=$(echo "$time_val" | cut -s -d'.' -f2)
        local ms="000"
        if [[ -n "$ff" ]]; then
            ff=$((10#$ff)) # Führende Nullen sicher entfernen
            ms=$(printf "%03d" $(( ff * 40 )))
        fi
        local ffmpeg_time="${hhmmss}.${ms}"

        if [[ -z "$start_mark" ]]; then
            start_mark="$ffmpeg_time"
        else
            local end_mark="$ffmpeg_time"
            segments+=("$start_mark $end_mark")
            start_mark=""
        fi
    done < "$MARKS_FILE"

    # Falls eine ungerade Anzahl Marken existiert, geht der letzte Schnitt bis zum Ende
    if [[ -n "$start_mark" ]]; then
        segments+=("$start_mark end")
    fi

    if [[ ${#segments[@]} -eq 0 ]]; then
        echo "[$(date +%T)] FEHLER: Konnte keine gültigen Marken parsen." >> "$LOG_FILE"
        return 1
    fi

    # Segmente extrahieren
    local concat_file="$REC_DIR/concat.txt"
    > "$concat_file"
    local i=0
    local segment_files=()

    echo "[$(date +%T)] INFO: Extrahiere ${#segments[@]} Videosegment(e)..." >> "$LOG_FILE"
    
    for seg in "${segments[@]}"; do
        local s_time=$(echo "$seg" | awk '{print $1}')
        local e_time=$(echo "$seg" | awk '{print $2}')
        local seg_file="$REC_DIR/segment_$i.ts"
        segment_files+=("$seg_file")
        
        if [[ "$e_time" == "end" ]]; then
            ffmpeg -y -ss "$s_time" -i "$TARGET_FILE" -c copy -copyts "$seg_file" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
        else
            # Dauer exakt berechnen, da -to bei DVB-Timestamps (PTS) in Kombination mit -copyts sofort abbricht
            local t_time=$(awk -v s="$s_time" -v e="$e_time" '
                function to_ms(t) {
                    split(t, a, ":"); split(a[3], b, ".");
                    return (a[1]*3600000) + (a[2]*60000) + (b[1]*1000) + b[2];
                }
                BEGIN {
                    diff = to_ms(e) - to_ms(s);
                    if(diff < 0) diff = 0;
                    printf "%.3f", diff / 1000;
                }
            ')
            ffmpeg -y -ss "$s_time" -i "$TARGET_FILE" -t "$t_time" -c copy -copyts "$seg_file" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
        fi
        
        local FF_STATUS=${PIPESTATUS[0]}
        if [[ $FF_STATUS -eq 0 && -f "$seg_file" ]]; then
            echo "file '$(basename "$seg_file")'" >> "$concat_file"
        else
            echo "[$(date +%T)] FEHLER: Extraktion von Segment $i fehlgeschlagen." >> "$LOG_FILE"
            rm -f "${segment_files[@]}" "$concat_file"
            return 1
        fi
        ((i++))
    done

    # Segmente zusammenfügen
    echo "[$(date +%T)] INFO: Füge Segmente zusammen (Concat)..." >> "$LOG_FILE"
    ffmpeg -y -f concat -safe 0 -i "$concat_file" -c copy -fflags +genpts -avoid_negative_ts make_zero "$OUT_FILE" </dev/null 2>&1 | filter_ffmpeg_log >> "$LOG_FILE"
    
    local FF_STATUS=${PIPESTATUS[0]}
    rm -f "${segment_files[@]}" "$concat_file"

    if [[ $FF_STATUS -eq 0 && -f "$OUT_FILE" ]]; then
        # Check: Ist die Datei nicht versehentlich extrem geschrumpft? (Erwarten min. 10% der Originalgröße)
        local IN_SIZE=$(stat -c%s "$TARGET_FILE" 2>/dev/null || echo 0)
        local OUT_SIZE=$(stat -c%s "$OUT_FILE" 2>/dev/null || echo 0)
        
        if [[ "$OUT_SIZE" -lt $(( IN_SIZE / 10 )) ]]; then
            echo "[$(date +%T)] FEHLER: Geschnittenes Video ist extrem klein (< 10%). Abbruch zum Schutz der Daten." >> "$LOG_FILE"
            rm -f "$OUT_FILE"
            return 1
        fi
        
        echo "[$(date +%T)] ERFOLG: Werbeschnitt abgeschlossen." >> "$LOG_FILE"
        mv "$OUT_FILE" "$TARGET_FILE"
        return 0
    else
        echo "[$(date +%T)] FEHLER: Zusammenfügen der Segmente fehlgeschlagen." >> "$LOG_FILE"
        rm -f "$OUT_FILE"
        return 1
    fi
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
            echo "[$(date +%T)] Erstelle Poster-Snapshot bei $SEEK_POINT..." >> "$LOG_FILE"
        ffmpeg -y -ss "$SEEK_POINT" -i "$VIDEO_FILE" -frames:v 1 -update 1 -q:v 2 "$DEST_DIR/poster.jpg" </dev/null >/dev/null 2>&1
    fi

    # Fanart kopieren, falls poster.jpg erfolgreich war
    if [ -f "$DEST_DIR/poster.jpg" ]; then
        cp "$DEST_DIR/poster.jpg" "$DEST_DIR/fanart.jpg"
        chown vdr:vdr "$DEST_DIR/poster.jpg" "$DEST_DIR/fanart.jpg" 2>/dev/null || true
    fi
}
