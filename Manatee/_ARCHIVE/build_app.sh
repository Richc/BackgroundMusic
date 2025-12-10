#!/bin/bash
#
# build_app.sh - Build Manatee.app bundle
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/Manatee.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🐋 Building Manatee..."

# Build the executable
swift build -c release

# Create app bundle directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$SCRIPT_DIR/.build/release/Manatee" "$MACOS_DIR/Manatee"

# Copy resources bundle
if [ -d "$SCRIPT_DIR/.build/release/Manatee_Manatee.bundle" ]; then
    cp -R "$SCRIPT_DIR/.build/release/Manatee_Manatee.bundle" "$RESOURCES_DIR/"
fi

# Copy icon
cp "$SCRIPT_DIR/manatee logo/Manatee.icns" "$RESOURCES_DIR/AppIcon.icns"

# Copy Manatee logo for in-app use
cp "$SCRIPT_DIR/manatee logo/icon.iconset/icon_32x32@2x.png" "$RESOURCES_DIR/ManateeLogo.png"

# Copy menu bar icons
cp "$SCRIPT_DIR/manatee logo/icon.iconset/icon_16x16.png" "$RESOURCES_DIR/MenuBarIcon.png"
cp "$SCRIPT_DIR/manatee logo/icon.iconset/icon_16x16@2x.png" "$RESOURCES_DIR/MenuBarIcon@2x.png"
cp "$SCRIPT_DIR/manatee logo/icon.iconset/icon_32x32@2x.png" "$RESOURCES_DIR/MenuBarIcon@3x.png"

# Sign the app (ad-hoc for local use)
codesign --force --deep --sign - "$APP_DIR"

echo "✅ Manatee.app built successfully!"
echo "📍 Location: $APP_DIR"
echo ""
echo "To install, run:"
echo "  cp -R \"$APP_DIR\" /Applications/"
