# update.sh
#!/bin/bash

echo "=== OMC Webcam Update ==="

# Prüfen ob config.sh existiert
if [ ! -f "/home/OMC/config.sh" ]; then
    echo "❌  FEHLER: config.sh nicht gefunden!"
    echo "Bitte erstellen Sie zuerst die config.sh mit Ihren Zugangsdaten."
    exit 1
fi

# Git-Stand HART auf origin/main setzen (ohne Merge)
echo "Hole Updates von GitHub..."
cd /home/OMC

# Lokale Änderungen komplett verwerfen und exakt auf origin/main setzen
echo "Verwerfe lokale Änderungen und setze Arbeitsbaum auf origin/main..."
git fetch --all --prune
git reset --hard origin/main
# Optional: Untracked Dateien/Ordner entfernen (gefährlich). Auskommentiert lassen oder bewusst aktivieren.
# git clean -fd    # entfernt untracked Dateien/Ordner (aus Repo-Sicht)
# git clean -fdx   # entfernt zusätzlich ignorierte Dateien (z.B. Build-Artefakte)

if [ $? -eq 0 ]; then
    echo "✅  Update erfolgreich!"
    echo "Scripts sind jetzt aktuell."

    # Scripts ausführbar machen
    chmod +x *.sh
else
    echo "❌  Update fehlgeschlagen!"
    exit 1
fi
