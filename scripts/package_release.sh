#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="v$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/Resources/Info.plist")"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/yunsftp.app"
DMG_NAME="yunsftp-${VERSION}-macos-arm64.dmg"
ZIP_NAME="yunsftp-${VERSION}-macos-arm64.zip"

echo "=== 1. Building Release App Bundle ==="
./scripts/build_app.sh

echo "=== 2. Creating macOS DMG Installer ==="
DMG_STAGING="$(mktemp -d /tmp/yunsftp_dmg_staging.XXXXXX)"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$BUILD_DIR/$DMG_NAME"
hdiutil create -volname "yunsftp" -srcfolder "$DMG_STAGING" -ov -format UDZO "$BUILD_DIR/$DMG_NAME"
rm -rf "$DMG_STAGING"

echo "=== 3. Creating Portable ZIP Archive ==="
rm -f "$BUILD_DIR/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$BUILD_DIR/$ZIP_NAME"

echo "=== 4. Generating SHA256 Checksums ==="
cd "$BUILD_DIR"
shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > checksums.txt
cat checksums.txt

echo "=== Packaging Complete! ==="
ls -lh "$BUILD_DIR/$DMG_NAME" "$BUILD_DIR/$ZIP_NAME" "$BUILD_DIR/checksums.txt"
