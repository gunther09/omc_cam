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

echo "=== OMC Webcam Manueller Start ==="
echo "$(date '+%H:%M:%S') - Starte Kameraaufnahme..."

# === Hilfsfunktion: Zeilenbegrenzung für das Log ===
trim_logfile() {
    [ -f "$LOGFILE" ] && tail -n "$MAX_LOG_LINES" "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
}

# === Progress-Update Funktion ===
progress_update() {
    echo "$(date '+%H:%M:%S') - $1"
}

# === Datums- und Temperaturvariablen setzen ===
progress_update "Sammle Systemdaten..."
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

progress_update "CPU: $TEMPE | WLAN: $WLAN_DISPLAY | Uptime: $UPTIME_VAL"

# === Kameraaufnahme mit Timeout ===
progress_update "Verbinde mit Kamera (RTSP)..."
timeout 30 ffmpeg -y -loglevel error -i "$RTSP_URL" \
  -vframes 1 -q:v 5 "$IMAGE" 2>&1

FFMPEG_EXIT=$?
if [ $FFMPEG_EXIT -eq 124 ]; then
    progress_update "❌ FEHLER: Kamera-Timeout (30 Sekunden)"
    echo "$(date) [ERROR] Kamera-Timeout nach 30 Sekunden" >> "$LOGFILE"
    trim_logfile
    exit 1
elif [ $FFMPEG_EXIT -ne 0 ]; then
    progress_update "❌ FEHLER: Kameraaufnahme fehlgeschlagen (Exit Code: $FFMPEG_EXIT)"
    echo "$(date) [ERROR] Kameraaufnahme fehlgeschlagen (Exit Code: $FFMPEG_EXIT)" >> "$LOGFILE"
    trim_logfile
    exit 1
fi

progress_update "✅ Kamerabild erfolgreich aufgenommen"

# === Bildbearbeitung mit ImageMagick ===
progress_update "Bearbeite Bild (Overlay mit Systemdaten)..."
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
    "$IMAGE" 2>&1

if [ $? -ne 0 ]; then
    progress_update "❌ FEHLER: Bildbearbeitung fehlgeschlagen"
    echo "$(date) [ERROR] Bildbearbeitung fehlgeschlagen" >> "$LOGFILE"
    trim_logfile
    exit 1
fi

progress_update "✅ Bildbearbeitung abgeschlossen"

# === Upload mit Progress ===
progress_update "Starte Upload des Bildes..."
timeout 60 sshpass -p "$FTP_PASS" scp -o ConnectTimeout=30 -o ServerAliveInterval=10 "$IMAGE" "$FTP_USER@$FTP_HOST:$REMOTE_DIR/tapo.jpg" 2>&1

UPLOAD_EXIT=$?
if [ $UPLOAD_EXIT -eq 124 ]; then
    progress_update "❌ FEHLER: Upload-Timeout (60 Sekunden)"
    echo "$(date) [ERROR] Bild-Upload-Timeout nach 60 Sekunden" >> "$LOGFILE"
    trim_logfile
    exit 1
elif [ $UPLOAD_EXIT -ne 0 ]; then
    progress_update "❌ FEHLER: Bild-Upload fehlgeschlagen (Exit Code: $UPLOAD_EXIT)"
    echo "$(date) [ERROR] Bild-Upload fehlgeschlagen (Exit Code: $UPLOAD_EXIT)" >> "$LOGFILE"
    trim_logfile
    exit 1
fi

progress_update "✅ Bild erfolgreich hochgeladen"

# === Log mit hochladen (nur wenn Bild erfolgreich hochgeladen wurde) ===
progress_update "Lade Logdatei hoch..."
timeout 30 sshpass -p "$FTP_PASS" scp -o ConnectTimeout=15 -o ServerAliveInterval=5 "$LOGFILE" "$FTP_USER@$FTP_HOST:$REMOTE_DIR/tapo.log" 2>&1

LOG_UPLOAD_EXIT=$?
if [ $LOG_UPLOAD_EXIT -eq 124 ]; then
    progress_update "⚠️  WARNUNG: Log-Upload-Timeout (30 Sekunden) - Bild wurde trotzdem hochgeladen"
    echo "$(date) [WARNING] Log-Upload-Timeout nach 30 Sekunden" >> "$LOGFILE"
    trim_logfile
elif [ $LOG_UPLOAD_EXIT -ne 0 ]; then
    progress_update "⚠️  WARNUNG: Log-Upload fehlgeschlagen (Exit Code: $LOG_UPLOAD_EXIT) - Bild wurde trotzdem hochgeladen"
    echo "$(date) [WARNING] Log-Upload fehlgeschlagen (Exit Code: $LOG_UPLOAD_EXIT)" >> "$LOGFILE"
    trim_logfile
else
    progress_update "✅ Logdatei erfolgreich hochgeladen"
fi

progress_update "=== Webcam-Upload komplett abgeschlossen ==="
echo "$(date) [SUCCESS] Manueller Webcam-Upload erfolgreich abgeschlossen" >> "$LOGFILE"
trim_logfile