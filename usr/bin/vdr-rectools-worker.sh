#!/bin/bash
# ==============================================================================
# vdr-rectools - Background Job Worker
# ==============================================================================

JOB_DIR="/tmp/vdr-rectools-jobs"
mkdir -p "$JOB_DIR"
chmod 777 "$JOB_DIR"

echo "VDR-Rectools Worker gestartet. Warte auf Jobs in $JOB_DIR..."

while true; do
    for job in "$JOB_DIR"/*.job; do
        [ -e "$job" ] || continue
        
        # 1. Atomisches Claiming (verhindert Race-Conditions mit anderen Workern)
        LOCK_FILE="${job%.job}.lock"
        mv "$job" "$LOCK_FILE" 2>/dev/null || continue
        
        # 2. Variablen initialisieren und sicher einlesen (Source-able format)
        ACTION=""
        PARAM=""
        source "$LOCK_FILE"
        
        # 3. Job synchron ausfuehren und Exit-Code abfangen
        SUCCESS=0
        if [ "$ACTION" == "update-html" ]; then
            /usr/bin/vdr-rectools update-html "$PARAM" >/dev/null 2>&1
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
        
        # 4. Saubere Status-Historie (Lock wird zu Done oder Err)
        if [ $SUCCESS -eq 0 ]; then
            mv "$LOCK_FILE" "${job%.job}.done" 2>/dev/null
        else
            mv "$LOCK_FILE" "${job%.job}.err" 2>/dev/null
        fi
    done
    
    sleep 0.5
done