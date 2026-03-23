#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/ReasonableLivePlayer/ReasonableLivePlayer.csproj"
APP_NAME="Reasonable Live Player"
BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
ICO="$SCRIPT_DIR/ReasonableLivePlayer/icon.ico"
ICON_PNG="$SCRIPT_DIR/ReasonableLivePlayer/icon.png"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    RID="osx-arm64"
else
    RID="osx-x64"
fi

echo "==> Publishing for $RID..."
dotnet publish "$PROJECT" -c Release -r "$RID" --self-contained true -p:PublishSingleFile=true -o "$SCRIPT_DIR/publish"

echo "==> Creating .app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$SCRIPT_DIR/publish/ReasonableLivePlayer" "$BUNDLE/Contents/MacOS/"
# Copy native libraries (.dylib) that aren't bundled into the single file
cp "$SCRIPT_DIR"/publish/*.dylib "$BUNDLE/Contents/MacOS/" 2>/dev/null || true
cp "$SCRIPT_DIR/Info.plist" "$BUNDLE/Contents/"

# Convert icon.png to .icns
echo "==> Converting icon..."
ICONSET="$SCRIPT_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Use pre-converted PNG as source (ico→png done offline via ImageMagick)
SRC="$ICON_PNG"
if [ ! -f "$SRC" ]; then
    # Fallback: try sips on the .ico
    sips -s format png "$ICO" --out "$ICONSET/source.png" >/dev/null 2>&1
    SRC="$ICONSET/source.png"
fi

# Generate required icon sizes
for SIZE in 16 32 128 256 512; do
    sips -z $SIZE $SIZE "$SRC" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null 2>&1
done
for SIZE in 32 64 256 512 1024; do
    HALF=$((SIZE / 2))
    sips -z $SIZE $SIZE "$SRC" --out "$ICONSET/icon_${HALF}x${HALF}@2x.png" >/dev/null 2>&1
done

iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ad-hoc code sign
echo "==> Code signing..."
codesign --deep --force --sign - "$BUNDLE"

echo ""
echo "==> Done! App bundle created at:"
echo "    $BUNDLE"
echo ""
echo "    To run:  open \"$BUNDLE\""
