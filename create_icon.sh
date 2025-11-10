#!/bin/bash
set -e

# Script to create macOS app icon from PNG image
# Usage: ./create_icon.sh input.png

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <input.png>"
    echo "Example: $0 ~/Downloads/icon.png"
    exit 1
fi

INPUT_PNG="$1"

if [ ! -f "$INPUT_PNG" ]; then
    echo "Error: File $INPUT_PNG not found"
    exit 1
fi

echo "Creating app icon from: $INPUT_PNG"

# Create temporary directory for iconset
ICONSET_DIR="AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir "$ICONSET_DIR"

# Generate all required sizes for macOS
sips -z 16 16     "$INPUT_PNG" --out "$ICONSET_DIR/icon_16x16.png"
sips -z 32 32     "$INPUT_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32     "$INPUT_PNG" --out "$ICONSET_DIR/icon_32x32.png"
sips -z 64 64     "$INPUT_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128   "$INPUT_PNG" --out "$ICONSET_DIR/icon_128x128.png"
sips -z 256 256   "$INPUT_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256   "$INPUT_PNG" --out "$ICONSET_DIR/icon_256x256.png"
sips -z 512 512   "$INPUT_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512   "$INPUT_PNG" --out "$ICONSET_DIR/icon_512x512.png"
sips -z 1024 1024 "$INPUT_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png"

# Convert to .icns
iconutil -c icns "$ICONSET_DIR" -o Resources/AppIcon.icns

# Clean up
rm -rf "$ICONSET_DIR"

echo "✅ Icon created: Resources/AppIcon.icns"
echo "Now rebuild the app with: ./build_app.sh"
