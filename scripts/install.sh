#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="$PROJECT_DIR/build/yunsftp.app"
DEST_APP="/Applications/yunsftp.app"
LEGACY_APP="/Applications/ForkLift Silicon.app"

echo "=== Building fresh app bundle ==="
bash "$PROJECT_DIR/scripts/build_app.sh"

echo "=== Installing yunsftp to /Applications ==="
# Clean legacy and existing bundle
rm -rf "$DEST_APP"
rm -rf "$LEGACY_APP"

cp -R "$APP_SRC" "$DEST_APP"
xattr -cr "$DEST_APP" 2>/dev/null || true

# Refresh LaunchServices so macOS immediately picks up the updated app icon and bundle
touch "$DEST_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST_APP" 2>/dev/null || true

echo "=== Installation Complete! ==="
echo "Installed to: $DEST_APP"
file "$DEST_APP/Contents/MacOS/yunsftp"
