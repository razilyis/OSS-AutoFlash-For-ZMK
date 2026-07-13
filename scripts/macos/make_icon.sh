#!/bin/bash
# icon.svg から AppIcon.icns を生成する(Xcode 不要)。
# デザイン変更時のみ実行すればよい。生成物 AppIcon.icns はリポジトリに含める。
set -euo pipefail
cd "$(dirname "$0")"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

swift render_icon.swift icon.svg "$WORK_DIR" 16 32 64 128 256 512 1024

cp "$WORK_DIR/icon_16.png" "$ICONSET/icon_16x16.png"
cp "$WORK_DIR/icon_32.png" "$ICONSET/icon_16x16@2x.png"
cp "$WORK_DIR/icon_32.png" "$ICONSET/icon_32x32.png"
cp "$WORK_DIR/icon_64.png" "$ICONSET/icon_32x32@2x.png"
cp "$WORK_DIR/icon_128.png" "$ICONSET/icon_128x128.png"
cp "$WORK_DIR/icon_256.png" "$ICONSET/icon_128x128@2x.png"
cp "$WORK_DIR/icon_256.png" "$ICONSET/icon_256x256.png"
cp "$WORK_DIR/icon_512.png" "$ICONSET/icon_256x256@2x.png"
cp "$WORK_DIR/icon_512.png" "$ICONSET/icon_512x512.png"
cp "$WORK_DIR/icon_1024.png" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o AppIcon.icns
echo "Built: scripts/macos/AppIcon.icns"
