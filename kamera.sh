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
LOGFILE="$WORK_DIR/kamera.log"
STATUS_FILE="$WORK_DIR/error.log" # Behält den Namen, erlaubt jetzt Kommentare
DIAG_LOGFILE="$WORK_DIR/Netzwerkanalyse.log" # NEUE Datei für Diagnose
IMAGE="$WORK_DIR/strecke.jpg"
cd $WORK_DIR || exit 1

# Funktion zur Protokollierung des Erfolgs
log_success() {
    TODAY=$(date +"%d.%m.%Y")
    # Erfolg im Hauptlog protokollieren (Tageszeile oder neue Zeile)
    grep -q "$TODAY" "$LOGFILE" && sed -i "/$TODAY/s/$/|/" "$LOGFILE" || {
        LINE_NUM=$(($(wc -l < "$LOGFILE") + 1))
        echo "$LINE_NUM [$TODAY] |" >> "$LOGFILE"
    }
    # Längenprüfung
    [ $(wc -l < "$LOGFILE") -gt 500 ] && tail -n 200 "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"

    # WICHTIG: Fehlerzähler bei Erfolg zurücksetzen (in der COUNTER=-Zeile)
    if [ -f "$STATUS_FILE" ] && grep -q '^COUNTER=' "$STATUS_FILE"; then
        # Wenn Datei und Zeile existieren, ersetze die Zeile
        sed -i "s/^COUNTER=.*/COUNTER=0/" "$STATUS_FILE"
    else
        # Wenn Datei oder Zeile fehlt, erstelle/überschreibe mit Zähler 0
        # Vorsicht: Überschreibt existierende Kommentare, wenn COUNTER=-Zeile fehlte!
        echo "COUNTER=0" > "$STATUS_FILE"
        echo "# Automatisch erstellt/zurückgesetzt von log_success" >> "$STATUS_FILE"
        echo "# Diese Datei speichert den Zähler für aufeinanderfolgende Fehler." >> "$STATUS_FILE"
        echo "# Nur die Zeile 'COUNTER=N' ist für das Skript relevant." >> "$STATUS_FILE"
    fi
}

# Fehlerbehandlungsfunktion (jetzt mit Zählerlogik für Kommentare)
handle_error() {
    ERROR_MSG="$1"
    # Zeilennummer ermitteln
    LINE_NUM=$(($(wc -l < "$LOGFILE") + 1))
    CURRENT_COUNT=0 # Standardwert

    # Aktuellen Fehlerzähler aus der 'COUNTER='-Zeile lesen
    if [ -f "$STATUS_FILE" ]; then
        COUNTER_LINE=$(grep '^COUNTER=' "$STATUS_FILE" || echo "") # Finde Zeile oder gib leer zurück
        if [ -n "$COUNTER_LINE" ]; then
            CURRENT_VALUE=$(echo "$COUNTER_LINE" | sed 's/^COUNTER=//')
            # Sicherstellen, dass es eine Zahl ist, sonst 0 (POSIX-konform)
            case "$CURRENT_VALUE" in
                ''|*[!0-9]*) CURRENT_COUNT=0 ;;
                *) CURRENT_COUNT=$CURRENT_VALUE ;; # Ist eine Zahl
            esac
        fi
        # Wenn keine COUNTER=-Zeile gefunden wurde, bleibt CURRENT_COUNT 0
    fi

    # Zähler erhöhen
    NEUER_ZAEHLER=$((CURRENT_COUNT + 1))

    # Neuen Zählerstand in die 'COUNTER='-Zeile speichern oder Zeile hinzufügen
    if [ -f "$STATUS_FILE" ] && grep -q '^COUNTER=' "$STATUS_FILE"; then
         # Wenn Datei und Zeile existieren, ersetze die Zeile
        sed -i "s/^COUNTER=.*/COUNTER=$NEUER_ZAEHLER/" "$STATUS_FILE"
    else
        # Wenn Datei oder Zeile fehlt, füge Zähler hinzu (oder erstelle Datei)
        # Fügt am Ende hinzu, um Kommentare am Anfang zu erhalten
        echo "COUNTER=$NEUER_ZAEHLER" >> "$STATUS_FILE"
        if ! grep -q "Diese Datei speichert" "$STATUS_FILE"; then
             # Füge Standardkommentar hinzu, falls noch nicht vorhanden
             echo "# Diese Datei speichert den Zähler für aufeinanderfolgende Fehler." >> "$STATUS_FILE"
             echo "# Nur die Zeile 'COUNTER=N' ist für das Skript relevant." >> "$STATUS_FILE"
        fi
    fi


    # Fehler im Hauptlog protokollieren (mit ERR-Markierung)
    echo "$LINE_NUM [$(date)] ERR: $ERROR_MSG" | tee -a "$LOGFILE"

    # Neustart prüfen
    if [ "$NEUER_ZAEHLER" -ge 10 ]; then
        # Neustart-Meldung loggen (als OK, da Aktion erfolgt)
        LINE_NUM=$((LINE_NUM + 1))
        echo "$LINE_NUM [$(date)] OK Raspberry Pi wird neu gestartet (10 aufeinanderfolgende Fehler)" | tee -a "$LOGFILE"

        # WICHTIG: Zähler *vor* dem Neustart zurücksetzen (in der COUNTER=-Zeile)
        if [ -f "$STATUS_FILE" ] && grep -q '^COUNTER=' "$STATUS_FILE"; then
            sed -i "s/^COUNTER=.*/COUNTER=0/" "$STATUS_FILE"
        else
            # Sollte nicht passieren, wenn Zähler >= 10, aber zur Sicherheit
            echo "COUNTER=0" > "$STATUS_FILE"
            echo "# Zurückgesetzt vor Neustart" >> "$STATUS_FILE"
        fi

        # Neustart ausführen (benötigt sudo-Rechte ohne Passwort!)
        sudo shutdown -r +0 "Neustart wegen anhaltender Probleme ($NEUER_ZAEHLER Fehler)" &
        # Skript hier beenden, da Neustart eingeleitet wurde
        exit 1 # oder exit 0, je nachdem ob dies als Fehler gilt
    fi
}

# --- Temporäre Diagnose direkt zu Beginn (schreibt in DIAG_LOGFILE) ---
# echo "=== Diagnose Start $(date) ===" >> "$DIAG_LOGFILE"
# echo "--- USB Geräte ---" >> "$DIAG_LOGFILE"
# lsusb >> "$DIAG_LOGFILE" 2>&1
# echo "--- Netzwerk Interfaces ---" >> "$DIAG_LOGFILE"
# ip a >> "$DIAG_LOGFILE" 2>&1
# echo "--- Stromversorgung/Throttling ---" >> "$DIAG_LOGFILE"
# # Prüfen ob vcgencmd existiert und ausführbar ist
# if command -v vcgencmd > /dev/null && [ -x "$(command -v vcgencmd)" ]; then
#     vcgencmd get_throttled >> "$DIAG_LOGFILE" 2>&1
# else
#     echo "vcgencmd nicht gefunden oder nicht ausführbar." >> "$DIAG_LOGFILE"
# fi
# echo "--- Modem Status (falls mmcli vorhanden) ---" >> "$DIAG_LOGFILE"
# # Prüfen ob mmcli existiert
# if command -v mmcli > /dev/null; then
#    mmcli -L >> "$DIAG_LOGFILE" 2>&1
#    # Versuche Details für Modems zu bekommen (kann fehlschlagen, wenn keins da)
#    mmcli -L | grep -Eo '[0-9]+$' | while read -r modem_index; do
#        echo "--- Details Modem $modem_index ---" >> "$DIAG_LOGFILE"
#        mmcli -m "$modem_index" >> "$DIAG_LOGFILE" 2>&1
#    done
# else
#    echo "mmcli nicht gefunden." >> "$DIAG_LOGFILE"
# fi
# echo "=== Diagnose Ende ===" >> "$DIAG_LOGFILE"
# --- Ende Temporäre Diagnose ---

# Internetverbindungs-Check zu Beginn
ping -c 4 8.8.8.8 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    # Fehler über handle_error behandeln (inkl. Zähler & Neustart-Check)
    handle_error "Keine Internetverbindung verfügbar - Skript wird beendet"
    # Skript beenden, da keine Verbindung besteht
    exit 1
fi
   
# Datums- und Temperaturvariablen setzen
DATE=$(date +"%d.%m.%Y - %H:%M") || handle_error "Fehler beim Setzen von DATE"
FILEDATE=$(date +"%d-%m-%Y--%H-%M") || handle_error "Fehler beim Setzen von FILEDATE"
MONAT=$(date +"%Y-%m") || handle_error "Fehler beim Setzen von MONAT"
TEMPE=$(vcgencmd measure_temp | sed "s/temp=\(.*\)'C/\1°C/") || handle_error "Fehler beim Messen der Temperatur"
WLAN_SIGNAL=$(iw dev wlan0 link 2>/dev/null | grep 'signal:' | sed 's/.*signal: \(.*\) dBm.*/\1 dBm/') || WLAN_SIGNAL="N/A"
# Aufnahme des Kamerabildes
raspistill -w 1920 -h 1080 -q 100 -ex auto --nopreview -awb auto -vf -hf -rot 90 -o "$IMAGE" || handle_error "Fehler beim Aufnehmen des Kamerabilds"
# Bildbearbeitung mit ImageMagick
convert "$IMAGE" \
    -gravity northeast \
    -fill "#333333" -draw "rectangle 1350,0 1920,280" \
    -pointsize 23 -fill white \
    -draw "text 15,25 'Offroad Minicar-Crew e.V.'" \
    -draw "text 15,55 '$DATE'" \
    -draw "text 15,85 'CPU $TEMPE'" \
    -draw "text 15,115 'WLAN $WLAN_SIGNAL'" \
    -gravity northwest \
    -fill "#8A9A9A" -draw "rectangle 0,0 600,600" \
    "$IMAGE" || handle_error "Fehler bei der Bildbearbeitung mit ImageMagick"
# FTP- und Backup-Operationen mit Timeout
sshpass -p "$FTP_PASS" ssh -o ConnectTimeout=120 $FTP_USER@$FTP_HOST "mkdir -p $REMOTE_DIR/$MONAT" 2>>$LOGFILE || handle_error "Fehler beim Erstellen des Backup-Ordners (Timeout nach 2 Minuten)"
sshpass -p "$FTP_PASS" ssh -o ConnectTimeout=120 $FTP_USER@$FTP_HOST "cp $REMOTE_DIR/strecke.jpg $REMOTE_DIR/$MONAT/$FILEDATE.jpg" 2>>$LOGFILE || handle_error "Fehler beim Archivieren des alten Bilds (Timeout nach 2 Minuten)"
sshpass -p "$FTP_PASS" scp -o ConnectTimeout=120 "$IMAGE" $FTP_USER@$FTP_HOST:$REMOTE_DIR/strecke.jpg 2>>$LOGFILE || handle_error "Fehler beim Hochladen des neuen Bilds (Timeout nach 2 Minuten)"
# Erfolgsprotokollierung und Hochladen der Logs
log_success # Setzt den Fehlerzähler zurück

# Hochladen der Haupt-Logdatei
sshpass -p "$FTP_PASS" scp -o ConnectTimeout=120 "$LOGFILE" "$FTP_USER@$FTP_HOST:$REMOTE_DIR/$(basename "$LOGFILE")" 2>>"$LOGFILE" || handle_error "Fehler beim Hochladen der Log-Datei ($(basename "$LOGFILE")) (Timeout nach 2 Minuten)"

# NEU: Hochladen der Fehlerzähler-Datei (error.log)
sshpass -p "$FTP_PASS" scp -o ConnectTimeout=120 "$STATUS_FILE" "$FTP_USER@$FTP_HOST:$REMOTE_DIR/$(basename "$STATUS_FILE")" 2>>"$LOGFILE" || handle_error "Fehler beim Hochladen der Zähler-Datei ($(basename "$STATUS_FILE")) (Timeout nach 2 Minuten)"