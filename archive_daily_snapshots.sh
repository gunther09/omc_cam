#!/bin/sh

# Archiviert feste Tages-Snapshots der bereits hochgeladenen Bilder auf dem Server.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "FEHLER: Konfigurationsdatei $CONFIG_FILE nicht gefunden!" >&2
    exit 1
fi

. "$CONFIG_FILE"

TIMESTAMP="${1:-$(date +"%H%M")}"
MONTH_DIR="$(date +"%Y-%m")"
DAY_STAMP="$(date +"%Y-%m-%d")"

case "$TIMESTAMP" in
    1000|1230|1600) ;;
    *)
        echo "FEHLER: Ungueltiger Archiv-Zeitstempel '$TIMESTAMP' (erlaubt: 1000, 1230, 1600)" >&2
        exit 2
        ;;
esac

archive_remote_image() {
    CAMERA_NAME="$1"
    SOURCE_FILE="$2"
    TARGET_DIR="$REMOTE_DIR/daily/$CAMERA_NAME/$MONTH_DIR"
    TARGET_FILE="$TARGET_DIR/${DAY_STAMP}_${TIMESTAMP}.jpg"
    SSH_ERR_FILE="/tmp/archive_daily_${CAMERA_NAME}_${TIMESTAMP}_$$"

    sshpass -p "$FTP_PASS" ssh -o ConnectTimeout=60 "$FTP_USER@$FTP_HOST" \
        "mkdir -p \"$TARGET_DIR\" && if [ -f \"$REMOTE_DIR/$SOURCE_FILE\" ]; then cp \"$REMOTE_DIR/$SOURCE_FILE\" \"$TARGET_FILE\"; else exit 3; fi" \
        2>"$SSH_ERR_FILE"
    SSH_EXIT=$?

    if [ $SSH_EXIT -ne 0 ]; then
        SSH_ERR=$(head -3 "$SSH_ERR_FILE" | tr '\n' '; ')
        rm -f "$SSH_ERR_FILE"

        if [ $SSH_EXIT -eq 3 ]; then
            echo "WARNUNG: Quelldatei fehlt auf dem Server: $REMOTE_DIR/$SOURCE_FILE" >&2
            return 1
        fi

        echo "FEHLER: Archivierung fuer $CAMERA_NAME fehlgeschlagen - Details: $SSH_ERR" >&2
        return 1
    fi

    rm -f "$SSH_ERR_FILE"
    return 0
}

archive_remote_image "kamera" "strecke.jpg"
archive_remote_image "tapo" "tapo.jpg"
