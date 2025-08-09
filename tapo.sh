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

# === Umgebungsvariablen für Cron-Job-Kompatibilität ===
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="/home/OMC"

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

# === Logging-Funktionen ===
# Fehler-Logging (detailliert)
log_error() {
    local message="$1"
    echo "$(date) [ERROR] $message" >> "$LOGFILE"
    echo "FEHLER: $message" >&2
    trim_logfile
}

# Erfolgs-Logging (minimal wie kamera.sh)
log_success() {
    TODAY=$(date +"%d.%m.%Y")
    # Erfolg im Hauptlog protokollieren (Tageszeile oder neue Zeile)
    grep -q "$TODAY" "$LOGFILE" && sed -i "/$TODAY/s/$/|/" "$LOGFILE" || {
        LINE_NUM=$(($(wc -l < "$LOGFILE") + 1))
        echo "$LINE_NUM [$TODAY] |" >> "$LOGFILE"
    }
    trim_logfile
}

# === Datums- und Temperaturvariablen setzen ===
DATE=$(date +"%d.%m.%Y - %H:%M") || {
    log_error "Fehler beim Setzen von DATE"
    exit 2
}
TEMPE=$(vcgencmd measure_temp | sed "s/temp=\(.*\)'C/\1°C/") || {
    log_error "Fehler beim Messen der Temperatur"
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

# WLAN-Interface ermitteln und Signal messen
WLAN_INTERFACE=$(ls /sys/class/net/ 2>/dev/null | grep -E '^(wlan|wifi)' | head -1)
if [ -z "$WLAN_INTERFACE" ]; then
    WLAN_INTERFACE="wlan0"  # Fallback
fi

WLAN_SIGNAL=$(/sbin/iw dev "$WLAN_INTERFACE" link 2>/dev/null | grep 'signal:' | sed 's/.*signal: \(.*\) dBm.*/\1 dBm/') || WLAN_SIGNAL="N/A"
WLAN_QUALITY=$(get_wlan_quality "$WLAN_SIGNAL")
WLAN_DISPLAY="$WLAN_SIGNAL $WLAN_QUALITY"
UPTIME_VAL=$(uptime -p | sed 's/up //') || UPTIME_VAL="N/A"

# === Kameraaufnahme mit Timeout ===
# Temporäre Datei für ffmpeg-Fehlermeldungen
FFMPEG_ERROR_FILE="/tmp/ffmpeg_error_$$"

timeout 30 /usr/bin/ffmpeg -y -loglevel error -i "$RTSP_URL" \
  -vframes 1 -q:v 5 "$IMAGE" 2>"$FFMPEG_ERROR_FILE"

FFMPEG_EXIT=$?
if [ $FFMPEG_EXIT -eq 124 ]; then
    log_error "Kamera-Timeout nach 30 Sekunden - Keine Verbindung zur Kamera ($RTSP_URL)"
    exit 3
elif [ $FFMPEG_EXIT -ne 0 ]; then
    # Fehlermeldung aus ffmpeg-Output lesen
    FFMPEG_ERROR=""
    if [ -f "$FFMPEG_ERROR_FILE" ] && [ -s "$FFMPEG_ERROR_FILE" ]; then
        FFMPEG_ERROR=$(cat "$FFMPEG_ERROR_FILE" | head -3 | tr '\n' '; ')
    fi
    log_error "Kameraaufnahme fehlgeschlagen (Exit Code: $FFMPEG_EXIT) - Verbindung zu $RTSP_URL: $FFMPEG_ERROR"
    exit 3
fi

# Temporäre Datei aufräumen
rm -f "$FFMPEG_ERROR_FILE"

# === Bildbearbeitung mit ImageMagick ===
# pixel werden von links oben gezählt
convert "$IMAGE" \
    \
    -fill "#333333" -draw "rectangle 20,530 800,610" \ #linke breite Balken 
    -fill "#333333" -draw "rectangle 1630,450 1800,600" \ # rechte viereck 
    -gravity northeast \
    -pointsize 23 -fill white \
    -draw "text 15,25 'Offroad Minicar-Crew e.V.'" \
    -draw "text 15,55 '$DATE'" \
    -draw "text 15,85 'CPU $TEMPE'" \
    -draw "text 15,115 'WLAN $WLAN_DISPLAY'" \
    -draw "text 15,145 'Uptime: $UPTIME_VAL'" \
    "$IMAGE" 2>/dev/null

if [ $? -ne 0 ]; then
    log_error "Bildbearbeitung fehlgeschlagen"
    exit 4
fi

# === Upload mit Timeout ===
timeout 60 sshpass -p "$FTP_PASS" scp -o ConnectTimeout=30 -o ServerAliveInterval=10 "$IMAGE" "$FTP_USER@$FTP_HOST:$REMOTE_DIR/tapo.jpg" 2>/dev/null

UPLOAD_EXIT=$?
if [ $UPLOAD_EXIT -eq 124 ]; then
    log_error "Bild-Upload-Timeout nach 60 Sekunden"
    exit 5
elif [ $UPLOAD_EXIT -ne 0 ]; then
    log_error "Bild-Upload fehlgeschlagen (Exit Code: $UPLOAD_EXIT)"
    exit 5
fi

# === Log mit hochladen (nur wenn Bild erfolgreich hochgeladen wurde) ===
timeout 30 sshpass -p "$FTP_PASS" scp -o ConnectTimeout=15 -o ServerAliveInterval=5 "$LOGFILE" "$FTP_USER@$FTP_HOST:$REMOTE_DIR/tapo.log" 2>/dev/null

LOG_UPLOAD_EXIT=$?
if [ $LOG_UPLOAD_EXIT -eq 124 ]; then
    # Log-Upload-Fehler sind nicht kritisch, trotzdem Erfolg protokollieren
    log_success
elif [ $LOG_UPLOAD_EXIT -ne 0 ]; then
    # Log-Upload-Fehler sind nicht kritisch, trotzdem Erfolg protokollieren
    log_success
else
    # Alles erfolgreich
    log_success
fi

