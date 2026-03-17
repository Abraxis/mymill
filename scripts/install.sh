#!/bin/bash
# Build, install to /Applications, and launch Treadmill.app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Treadmill.app"
INSTALL_DIR="/Applications"

cd "$PROJECT_DIR"

# Generate project
echo "==> Generating Xcode project..."
xcodegen generate

# Build
echo "==> Building..."
xcodebuild build \
    -project Treadmill.xcodeproj \
    -scheme Treadmill \
    -configuration Release \
    -destination 'platform=macOS' \
    SYMROOT="$BUILD_DIR" \
    2>&1 | tail -5

APP_PATH="$BUILD_DIR/Release/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
    echo "==> Build failed!"
    exit 1
fi

# Kill running instance
echo "==> Stopping existing instance..."
pkill -x Treadmill 2>/dev/null || true
sleep 1

# Install
echo "==> Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/$APP_NAME"
cp -R "$APP_PATH" "$INSTALL_DIR/$APP_NAME"

# Launch
echo "==> Launching..."
open "$INSTALL_DIR/$APP_NAME"

echo "==> Done! Treadmill is running from $INSTALL_DIR/$APP_NAME"
