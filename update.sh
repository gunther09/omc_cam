# update.sh
#!/bin/bash

echo "=== OMC Webcam Update ==="

# Prüfen ob config.sh existiert
if [ ! -f "/home/OMC/config.sh" ]; then
    echo "❌  FEHLER: config.sh nicht gefunden!"
    echo "Bitte erstellen Sie zuerst die config.sh mit Ihren Zugangsdaten."
    exit 1
fi

# Git pull ausführen
echo "Hole Updates von GitHub..."
cd /home/OMC
git pull origin main

if [ $? -eq 0 ]; then
    echo "✅  Update erfolgreich!"
    echo "Scripts sind jetzt aktuell."

    # Scripts ausführbar machen
    chmod +x *.sh
"update.sh" 28 lines, 606 bytes
