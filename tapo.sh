#!/bin/sh

# === Konfiguration laden ===
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "FEHLER: Konfigurationsdatei $CONFIG_FILE nicht gefunden!"
    echo "Bitte kopieren Sie config.sh.example zu config.sh und tragen Sie Ihre Daten ein."
    exit 1
fi

# Konfiguration laden
. "$CONFIG_FILE"

# === Lokale Konfiguration ===
WORK_DIR="/home/OMC"
IMAGE="$WORK_DIR/tapocam.jpg"
LOGFILE="$WORK_DIR/tapo.log"
MAX_LOG_LINES=500

# Silent Mode für Cronjobs (keine Progress-Updates, nur Fehler)
SILENT_MODE=1

cd "$WORK_DIR" || exit 1

# === Hilfsfunktion: Zeilenbegrenzung für das Log ===
trim_logfile() {
    [ -f "$LOGFILE" ] && tail -n "$MAX_LOG_LINES" "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
}

# === Logging-Funktion für Silent Mode ===
log_message() {
    local level="$1"
    local message="$2"
    echo "$(date) [$level] $message" >> "$LOGFILE"
    # Bei Fehlern auch auf stderr ausgeben für Cronjob-Monitoring
    if [ "$level" = "ERROR" ]; then
        echo "FEHLER: $message" >&2
    fi
    trim_logfile
}

# === Datums- und Temperaturvariablen setzen ===
DATE=$(date +"%d.%m.%Y - %H:%M") || {
    log_message "ERROR" "Fehler beim Setzen von DATE"
    exit 2
}
TEMPE=$(vcgencmd measure_temp | sed "s/temp=\(.*\)'C/\1°C/") || {
    log_message "ERROR" "Fehler beim Messen der Temperatur"
    exit 2
}
# WLAN-Signal mit Qualitätsbewertung
get_wlan_quality() {
    local signal_dbm="$1"
    case "$signal_dbm" in
        -*[0-9]*) # Negative Zahl (dBm-Wert)
            local dbm_num=$(echo "$signal_dbm" | sed 's/-//' | sed 's/ dBm//')
            if [ "$dbm_num" -le 50 ]; then
                echo "(Exzellent)"
            elif [ "$dbm_num" -le 60 ]; then
                echo "(Sehr gut)"
            elif [ "$dbm_num" -le 70 ]; then
                echo "(Gut)"
            elif [ "$dbm_num" -le 80 ]; then
                echo "(Ausreichend)"
            elif [ "$dbm_num" -le 90 ]; then
                echo "(Schlecht)"
            else
                echo "(Unbrauchbar)"
            fi
            ;;
        *) echo "(Unbekannt)" ;;
    esac
}

WLAN_SIGNAL=$(iw dev wlan0 link 2>/dev/null | grep 'signal:' | sed 's/.*signal: \(.*\) dBm.*/\1 dBm/') || WLAN_SIGNAL="N/A"
WLAN_QUALITY=$(get_wlan_quality "$WLAN_SIGNAL")
WLAN_DISPLAY="$WLAN_SIGNAL $WLAN_QUALITY"
UPTIME_VAL=$(uptime -p | sed 's/up //') || UPTIME_VAL="N/A"

# === Kameraaufnahme mit Timeout ===
timeout 30 ffmpeg -y -loglevel error -i "$RTSP_URL" \
  -vframes 1 -q:v 5 "$IMAGE" 2>/dev/null

FFMPEG_EXIT=$?
if [ $FFMPEG_EXIT -eq 124 ]; then
    log_message "ERROR" "Kamera-Timeout nach 30 Sekunden"
    exit 3
elif [ $FFMPEG_EXIT -ne 0 ]; then
    log_message "ERROR" "Kameraaufnahme fehlgeschlagen (Exit Code: $FFMPEG_EXIT)"
    exit 3
fi

# === Bildbearbeitung mit ImageMagick ===
convert "$IMAGE" \
    \
    -fill "#333333" -draw "rectangle 20,450 800,530" \
    -fill "#333333" -draw "rectangle 1630,350 1800,500" \
    -gravity northeast \
    -pointsize 23 -fill white \
    -draw "text 15,25 'Offroad Minicar-Crew e.V.'" \
    -draw "text 15,55 '$DATE'" \
    -draw "text 15,85 'CPU $TEMPE'" \
    -draw "text 15,115 'WLAN $WLAN_DISPLAY'" \
    -draw "text 15,145 'Uptime: $UPTIME_VAL'" \
    "$IMAGE" 2>/dev/null

if [ $? -ne 0 ]; then
    log_message "ERROR" "Bildbearbeitung fehlgeschlagen"
    exit 4
fi

# === Upload mit Timeout ===
timeout 60 sshpass -p "$FTP_PASS" scp -o ConnectTimeout=30 -o ServerAliveInterval=10 "$IMAGE" "$FTP_USER@$FTP_HOST:$REMOTE_DIR/tapo.jpg" 2>/dev/null

UPLOAD_EXIT=$?
if [ $UPLOAD_EXIT -eq 124 ]; then
    log_message "ERROR" "Bild-Upload-Timeout nach 60 Sekunden"
    exit 5
elif [ $UPLOAD_EXIT -ne 0 ]; then
    log_message "ERROR" "Bild-Upload fehlgeschlagen (Exit Code: $UPLOAD_EXIT)"
    exit 5
fi

# === Log mit hochladen (nur wenn Bild erfolgreich hochgeladen wurde) ===
timeout 30 sshpass -p "$FTP_PASS" scp -o ConnectTimeout=15 -o ServerAliveInterval=5 "$LOGFILE" "$FTP_USER@$FTP_HOST:$REMOTE_DIR/tapo.log" 2>/dev/null

LOG_UPLOAD_EXIT=$?
if [ $LOG_UPLOAD_EXIT -eq 124 ]; then
    log_message "WARNING" "Log-Upload-Timeout nach 30 Sekunden - Bild wurde trotzdem hochgeladen"
elif [ $LOG_UPLOAD_EXIT -ne 0 ]; then
    log_message "WARNING" "Log-Upload fehlgeschlagen (Exit Code: $LOG_UPLOAD_EXIT) - Bild wurde trotzdem hochgeladen"
else
    log_message "SUCCESS" "Webcam-Upload erfolgreich abgeschlossen"
fi

