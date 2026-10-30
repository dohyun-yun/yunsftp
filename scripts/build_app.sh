#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=== Building yunsftp for Apple Silicon (arm64) ==="
swift build -c release --arch arm64

APP_NAME="yunsftp.app"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME"

echo "=== Creating macOS App Bundle: $APP_BUNDLE ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Find release binary location
BIN_SRC=""
if [ -f "$PROJECT_DIR/.build/out/Products/Release/yunsftp" ]; then
    BIN_SRC="$PROJECT_DIR/.build/out/Products/Release/yunsftp"
elif [ -f "$PROJECT_DIR/.build/arm64-apple-macosx/release/yunsftp" ]; then
    BIN_SRC="$PROJECT_DIR/.build/arm64-apple-macosx/release/yunsftp"
elif [ -f "$PROJECT_DIR/.build/release/yunsftp" ]; then
    BIN_SRC="$PROJECT_DIR/.build/release/yunsftp"
fi

if [ -z "$BIN_SRC" ]; then
    echo "Error: Binary yunsftp not found in build outputs!"
    exit 1
fi

# Copy binary
cp "$BIN_SRC" "$APP_BUNDLE/Contents/MacOS/yunsftp"
chmod +x "$APP_BUNDLE/Contents/MacOS/yunsftp"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy App Icon
cp "$PROJECT_DIR/Resources/yunsftp.icns" "$APP_BUNDLE/Contents/Resources/yunsftp.icns"

# Code sign. SIGN_IDENTITY (e.g. "Developer ID Application: Name (TEAMID)") enables a real
# signature with hardened runtime; otherwise an ad-hoc signature with a persistent designated
# requirement so TCC grants (Full Disk Access) survive rebuilds.
echo "=== Signing App Bundle ==="
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" \
        --entitlements "$PROJECT_DIR/Resources/yunsftp.entitlements" \
        "$APP_BUNDLE"
else
    codesign --force --deep --sign - \
        --identifier "com.finsternis.yunsftp" \
        -r '=designated => identifier "com.finsternis.yunsftp"' \
        --entitlements "$PROJECT_DIR/Resources/yunsftp.entitlements" \
        "$APP_BUNDLE"
fi

echo "=== Build Complete! App bundle created at: $APP_BUNDLE ==="
file "$APP_BUNDLE/Contents/MacOS/yunsftp"
