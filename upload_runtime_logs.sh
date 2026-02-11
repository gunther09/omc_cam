#!/bin/sh

# Lädt die Laufzeit-Logs aus RAM in den Remote-Ordner hoch.
# Für stündlichen Cronjob gedacht.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "FEHLER: Konfigurationsdatei $CONFIG_FILE nicht gefunden!" >&2
    exit 1
fi

. "$CONFIG_FILE"

RUNTIME_DIR="${RUNTIME_DIR:-/run/omc}"
if [ ! -d "$RUNTIME_DIR" ]; then
    RUNTIME_DIR="/dev/shm/omc"
fi
if [ ! -d "$RUNTIME_DIR" ]; then
    RUNTIME_DIR="/tmp/omc"
fi

upload_if_exists() {
    LOCAL_FILE="$1"
    REMOTE_NAME="$2"
    [ -f "$LOCAL_FILE" ] || return 0
    timeout 45 sshpass -p "$FTP_PASS" scp -o ConnectTimeout=20 -o ServerAliveInterval=5 "$LOCAL_FILE" "$FTP_USER@$FTP_HOST:$REMOTE_DIR/$REMOTE_NAME" >/dev/null 2>&1
}

upload_if_exists "$RUNTIME_DIR/tapo.log" "tapo.log"
upload_if_exists "$RUNTIME_DIR/kamera.log" "kamera.log"
upload_if_exists "$RUNTIME_DIR/error.log" "error.log"
