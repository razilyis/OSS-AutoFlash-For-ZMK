#!/bin/bash
# AutoFlash for ZMK.dmg を作成する(配布用)。
set -euo pipefail
cd "$(dirname "$0")/../.."

./scripts/macos/make_app.sh

APP="dist/AutoFlash for ZMK.app"
DMG="dist/AutoFlash for ZMK.dmg"
VOLUME_NAME="AutoFlash for ZMK"

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp -R "$APP" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG"

echo "Built: $DMG"
