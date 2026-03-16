#!/bin/bash
# Package Treadmill.app into a DMG for distribution
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/Release/Treadmill.app"
VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
DMG_NAME="Treadmill-${VERSION}-macOS.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
STAGING="$BUILD_DIR/dmg-staging"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Treadmill.app not found. Run ./scripts/build.sh first."
    exit 1
fi

echo "==> Creating DMG: $DMG_NAME"

# Clean staging
rm -rf "$STAGING"
mkdir -p "$STAGING"

# Copy app
cp -R "$APP_PATH" "$STAGING/"

# Create symlink to /Applications
ln -s /Applications "$STAGING/Applications"

# Create DMG
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Treadmill" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Clean staging
rm -rf "$STAGING"

echo ""
echo "==> DMG created: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"

# Also create a zip for GitHub releases
ZIP_NAME="Treadmill-${VERSION}-macOS.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
cd "$BUILD_DIR/Build/Products/Release"
zip -r -y "$ZIP_PATH" Treadmill.app
echo "    ZIP created: $ZIP_PATH"
