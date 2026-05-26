#!/bin/bash
# ==============================================================================
# vdr-rectools - Background Job Worker
# ==============================================================================

JOB_DIR="/tmp/vdr-rectools-jobs"
mkdir -p "$JOB_DIR"
chmod 777 "$JOB_DIR"

write_status() {
    local J_NAME="$1"
    local STATE="$2"
    local PROG="$3"
    local MSG="$4"
    local S_FILE="$JOB_DIR/${J_NAME}.status"
    local T_FILE="${S_FILE}.tmp"
    echo "state=$STATE" > "$T_FILE"
    echo "progress=$PROG" >> "$T_FILE"
    echo "message=$MSG" >> "$T_FILE"
    echo "updated=$(date +%s)" >> "$T_FILE"
    mv "$T_FILE" "$S_FILE" 2>/dev/null
    chmod 666 "$S_FILE" 2>/dev/null
}

# 0. Crash-Recovery: Heartbeat-basiertes Stale Lock Reclaim
# Findet .lock Dateien, die aelter als 5 Minuten sind. Da aktive Jobs jede Minute einen
# Heartbeat (touch) erhalten, bedeutet dies, dass der Worker hart gecrasht ist (Stromausfall, SIGKILL).
find "$JOB_DIR" -maxdepth 1 -type f -name "*.lock" -mmin +5 -print0 2>/dev/null | while IFS= read -r -d '' stale_lock; do
    mv "$stale_lock" "${stale_lock%.lock}.job" 2>/dev/null
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] CRASH RECOVERY: Zombie-Lock $(basename "$stale_lock") requeued." >> "/var/log/vdr-rectools-worker.log"
    J_NAME=$(basename "${stale_lock%.lock}")
    write_status "$J_NAME" "queued" 0 "Crash Recovery: Job neu eingereiht nach Absturz"
done

for job in "$JOB_DIR"/*.job; do
    [ -e "$job" ] || continue
    
    JOB_NAME=$(basename "${job%.job}")
    
    # 1. Atomisches Claiming (verhindert Race-Conditions mit anderen Workern)
    LOCK_FILE="${job%.job}.lock"
    mv "$job" "$LOCK_FILE" 2>/dev/null || continue
    
    # 2. Heartbeat Lease-Renewal: Hintergrundprozess, der das Lock aktiv am Leben haelt
    (
        while [ -f "$LOCK_FILE" ]; do
            touch "$LOCK_FILE" 2>/dev/null
            sleep 60
        done
    ) &
    HEARTBEAT_PID=$!
    
    # 3. Variablen initialisieren und sicher einlesen (Safe-Parsing statt source)
    ACTION=""
    PARAM=""
    LANGUAGE=""
    IDEMPOTENCY_KEY=""
    while IFS='=' read -r key value; do
        value="${value%\"}"
        value="${value#\"}"
        case "$key" in
            ACTION) ACTION="$value" ;;
            PARAM) PARAM="$value" ;;
            LANGUAGE) LANGUAGE="$value" ;;
            IDEMPOTENCY_KEY) IDEMPOTENCY_KEY="$value" ;;
        esac
    done < "$LOCK_FILE"
    
    write_status "$JOB_NAME" "running" 10 "Ausfuehrung gestartet"
    
    # 4. Job synchron ausfuehren und Exit-Code abfangen
    SUCCESS=0
    # Sprache als Override exportieren, damit functions.sh es zwingend nutzt
    export LANGUAGE_OVERRIDE="$LANGUAGE"
    
    if [ "$ACTION" == "update-html" ]; then
        /usr/bin/vdr-rectools update-html >/dev/null 2>&1
        SUCCESS=$?
    elif [ "$ACTION" == "import" ]; then
        /usr/bin/vdr-rectools import >/dev/null 2>&1
        SUCCESS=$?
    elif [ "$ACTION" == "stop" ]; then
        /usr/bin/vdr-rectools stop >/dev/null 2>&1
        SUCCESS=$?
    elif [ "$ACTION" == "restart_vdr" ]; then
        /bin/systemctl --no-block restart vdr.service >/dev/null 2>&1
        SUCCESS=$?
    else
        SUCCESS=1
    fi
    
    # 5. Saubere Status-Historie, Logging und Cleanup
    LOG_FILE="/var/log/vdr-rectools-worker.log"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] EXIT=$SUCCESS ACTION=$ACTION PARAM=$PARAM" >> "$LOG_FILE"
    if [ $SUCCESS -eq 0 ]; then
        mv "$LOCK_FILE" "${job%.job}.done" 2>/dev/null
        write_status "$JOB_NAME" "done" 100 "Erfolgreich abgeschlossen"
    else
        mv "$LOCK_FILE" "${job%.job}.err" 2>/dev/null
        write_status "$JOB_NAME" "error" 0 "Fehler (Exit $SUCCESS)"
    fi
    
    # Idempotency Key aufraeumen
    if [ -n "$IDEMPOTENCY_KEY" ]; then
        rm -f "$JOB_DIR/key_$IDEMPOTENCY_KEY" 2>/dev/null
    fi
    
    # Heartbeat sauber beenden
    kill "$HEARTBEAT_PID" 2>/dev/null
done

# 5. Housekeeping: Alte Status-Dateien sicher aufraeumen (unbedenklich, da Oneshot)
find "$JOB_DIR" -type f -name "*.done" -mmin +60 -delete 2>/dev/null
find "$JOB_DIR" -type f -name "*.err" -mmin +1440 -delete 2>/dev/null
find "$JOB_DIR" -type f -name "*.status" -mmin +60 -delete 2>/dev/null