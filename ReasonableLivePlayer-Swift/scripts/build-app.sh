#!/bin/bash
# Builds "Reasonable Live Player.app" from the Swift package.
#
#   ./scripts/build-app.sh                  native architecture, ad-hoc signed
#   UNIVERSAL=1 ./scripts/build-app.sh      arm64 + x86_64
#   CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./scripts/build-app.sh
#
# A stable signing identity keeps the Accessibility permission across updates.
# Ad-hoc signing changes the app's identity on every build, so macOS asks again.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Reasonable Live Player"
EXECUTABLE="ReasonableLivePlayer"
VERSION="${VERSION:-2.0.0}"
BUILD_DATE="$(date -u +%Y-%m-%d)"
OUT="$ROOT/dist"
BUNDLE="$OUT/$APP_NAME.app"
ICON_PNG="$ROOT/Resources/icon.png"
IDENTITY="${CODESIGN_IDENTITY:--}"

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

cd "$ROOT"
echo "==> Building (release)..."
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "==> Creating app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$BUNDLE/Contents/MacOS/$EXECUTABLE"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD_DATE__/$BUILD_DATE/g" \
    "$ROOT/Resources/Info.plist" > "$BUNDLE/Contents/Info.plist"

make_icns() {
    local out="$1"
    local set
    set="$(mktemp -d)/icon.iconset"
    mkdir -p "$set"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICON_PNG" --out "$set/icon_${size}x${size}.png" >/dev/null
    done
    for size in 32 64 256 512 1024; do
        sips -z $size $size "$ICON_PNG" --out "$set/icon_$((size / 2))x$((size / 2))@2x.png" >/dev/null
    done
    iconutil -c icns "$set" -o "$out"
    rm -rf "$(dirname "$set")"
}

echo "==> Creating icons..."
make_icns "$BUNDLE/Contents/Resources/AppIcon.icns"
make_icns "$BUNDLE/Contents/Resources/RLPDocument.icns"

echo "==> Code signing (identity: $IDENTITY)..."
codesign --force --deep --sign "$IDENTITY" "$BUNDLE"

echo
echo "Done: $BUNDLE"
echo "Run:  open \"$BUNDLE\""
