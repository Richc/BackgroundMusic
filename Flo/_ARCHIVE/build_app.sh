#!/bin/bash
#
# build_app.sh - Build Flo.app bundle
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/Flo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🌊 Building Flo..."

# Build the executable
swift build -c release

# Create app bundle directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$SCRIPT_DIR/.build/release/Flo" "$MACOS_DIR/Flo"

# Copy resources bundle
if [ -d "$SCRIPT_DIR/.build/release/Flo_Flo.bundle" ]; then
    cp -R "$SCRIPT_DIR/.build/release/Flo_Flo.bundle" "$RESOURCES_DIR/"
fi

# Copy icon
cp "$SCRIPT_DIR/../Sources/Flo/Resources/Flo icon.icns" "$RESOURCES_DIR/AppIcon.icns"

# Copy Flo logo for in-app use  
cp "$SCRIPT_DIR/../Sources/Flo/Resources/FloLogo.png" "$RESOURCES_DIR/FloLogo.png"

# Copy menu bar icons
cp "$SCRIPT_DIR/../Sources/Flo/Resources/MenuBarIcon.png" "$RESOURCES_DIR/MenuBarIcon.png"
cp "$SCRIPT_DIR/../Sources/Flo/Resources/MenuBarIcon@2x.png" "$RESOURCES_DIR/MenuBarIcon@2x.png"
cp "$SCRIPT_DIR/../Sources/Flo/Resources/MenuBarIcon@3x.png" "$RESOURCES_DIR/MenuBarIcon@3x.png"

# Sign the app (ad-hoc for local use)
codesign --force --deep --sign - "$APP_DIR"

echo "✅ Flo.app built successfully!"
echo "📍 Location: $APP_DIR"
echo ""
echo "To install, run:"
echo "  cp -R \"$APP_DIR\" /Applications/"
