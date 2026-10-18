#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="$PROJECT_DIR/build/yunsftp.app"
DEST_APP="/Applications/yunsftp.app"
LEGACY_APP="/Applications/ForkLift Silicon.app"

if [ ! -d "$APP_SRC" ]; then
    echo "App bundle not found. Building first..."
    bash "$PROJECT_DIR/scripts/build_app.sh"
fi

echo "=== Installing yunsftp to /Applications ==="
# Clean legacy and existing bundle
rm -rf "$DEST_APP"
rm -rf "$LEGACY_APP"

cp -R "$APP_SRC" "$DEST_APP"
xattr -cr "$DEST_APP" 2>/dev/null || true

echo "=== Installation Complete! ==="
echo "Installed to: $DEST_APP"
file "$DEST_APP/Contents/MacOS/yunsftp"
