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

cd "$WORK_DIR" || exit 1

# === Hilfsfunktion: Zeilenbegrenzung für das Log ===
trim_logfile() {
    [ -f "$LOGFILE" ] && tail -n "$MAX_LOG_LINES" "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
}

# === Datums- und Temperaturvariablen setzen ===
DATE=$(date +"%d.%m.%Y - %H:%M") || {
    echo "$(date) [ERROR] Fehler beim Setzen von DATE" >> "$LOGFILE"
    trim_logfile
    exit 1
}
TEMPE=$(vcgencmd measure_temp | sed "s/temp=\(.*\)'C/\1°C/") || {
    echo "$(date) [ERROR] Fehler beim Messen der Temperatur" >> "$LOGFILE"
    trim_logfile
    exit 1
}
WLAN_SIGNAL=$(iwconfig wlan0 2>/dev/null | grep -o 'Signal level=.*dBm' | sed 's/Signal level=//') || WLAN_SIGNAL="N/A"
UPTIME_VAL=$(uptime -p | sed 's/up //') || UPTIME_VAL="N/A"

# === Kameraaufnahme ===
ffmpeg -y -loglevel error -i "$RTSP_URL" \
  -vframes 1 -q:v 5 "$IMAGE"

if [ $? -ne 0 ]; then
    echo "$(date) [ERROR] Kameraaufnahme fehlgeschlagen" >> "$LOGFILE"
    trim_logfile
    exit 1
fi

# === Bildbearbeitung mit ImageMagick ===
convert "$IMAGE" \
    
    -fill "#333333" -draw "rectangle 20,450 800,530" \
    -fill "#333333" -draw "rectangle 1630,350 1800,500" \
    -gravity northeast \
    -pointsize 23 -fill white \
    -draw "text 15,25 'Offroad Minicar-Crew e.V.'" \
    -draw "text 15,55 '$DATE'" \
    -draw "text 15,85 'CPU $TEMPE'" \
    -draw "text 15,115 'WLAN $WLAN_SIGNAL'" \
    -draw "text 15,145 'Uptime: $UPTIME_VAL'" \
    "$IMAGE"

if [ $? -ne 0 ]; then
    echo "$(date) [ERROR] Bildbearbeitung fehlgeschlagen" >> "$LOGFILE"
    trim_logfile
    exit 1
fi

# === Upload ===
sshpass -p "$FTP_PASS" scp -o ConnectTimeout=30 "$IMAGE" "$FTP_USER@$FTP_HOST:$REMOTE_DIR/tapo.jpg"

if [ $? -ne 0 ]; then
    echo "$(date) [ERROR] Upload fehlgeschlagen" >> "$LOGFILE"
    trim_logfile
    exit 1
fi

# === Log mit hochladen (nur wenn Bild erfolgreich hochgeladen wurde) ===
sshpass -p "$FTP_PASS" scp -o ConnectTimeout=30 "$LOGFILE" "$FTP_USER@$FTP_HOST:$REMOTE_DIR/tapo.log"

