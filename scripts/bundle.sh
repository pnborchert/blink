#!/usr/bin/env bash
# Builds Blink and wraps the binary into a signed Blink.app.
#
# Environment:
#   BUILD_DIR      SwiftPM scratch path            (default: .build)
#   OUT_DIR        where Blink.app is written      (default: dist)
#   VERSION        CFBundleShortVersionString      (default: contents of VERSION file)
#   BUNDLE_ID      CFBundleIdentifier              (default: io.github.pnborchert.blink)
#   SIGN_IDENTITY  codesign identity, "-" = ad-hoc (default: -)
#   UNIVERSAL=1    build for arm64 and x86_64
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR="${BUILD_DIR:-.build}"
OUT_DIR="${OUT_DIR:-dist}"
VERSION="${VERSION:-$(cat VERSION)}"
BUNDLE_ID="${BUNDLE_ID:-io.github.pnborchert.blink}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release --product Blink --scratch-path "$BUILD_DIR" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release --scratch-path "$BUILD_DIR" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="$OUT_DIR/Blink.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Blink" "$APP/Contents/MacOS/Blink"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Finder/iCloud metadata on the bundle makes codesign fail ("resource fork,
# Finder information, or similar detritus not allowed").
xattr -cr "$APP"
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/Blink"), signed: $SIGN_IDENTITY)"
