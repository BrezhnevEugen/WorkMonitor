#!/bin/bash
set -e

APP_NAME="WorkMonitor"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

echo "=== Building $APP_NAME ==="

# Build with Swift Package Manager
swift build -c release

echo "=== Creating app bundle ==="

# Create .app structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"

# Copy Info.plist
cp "$APP_NAME/Info.plist" "$CONTENTS/Info.plist"

echo "=== Done! ==="
echo ""
echo "App bundle created: $APP_BUNDLE"
echo ""
echo "To run:"
echo "  open $APP_BUNDLE"
echo ""
echo "To install to Applications:"
echo "  cp -r $APP_BUNDLE /Applications/"
echo "  open /Applications/$APP_BUNDLE"
