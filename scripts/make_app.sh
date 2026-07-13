#!/bin/bash
# AutoFlash for ZMK.app バンドルを作成する。
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGE="$STAGE_DIR/AutoFlash for ZMK.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp .build/release/AutoFlash "$STAGE/Contents/MacOS/AutoFlash"
cp scripts/Info.plist "$STAGE/Contents/Info.plist"
cp scripts/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
xattr -cr "$STAGE"

# ad-hoc署名。特別なTCC権限を必要としないため、証明書なしのローカルビルドで十分。
codesign --force --sign - "$STAGE"
codesign --verify "$STAGE"

APP="dist/AutoFlash for ZMK.app"
rm -rf "$APP"
mkdir -p dist
mv "$STAGE" "$APP"

echo "Built: $APP"
echo "起動: open '$APP'"
