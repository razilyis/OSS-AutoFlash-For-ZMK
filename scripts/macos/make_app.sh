#!/bin/bash
# AutoFlash for ZMK.app バンドルを作成する。
set -euo pipefail
cd "$(dirname "$0")/../.."

swift build -c release

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGE="$STAGE_DIR/AutoFlash for ZMK.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp .build/release/AutoFlash "$STAGE/Contents/MacOS/AutoFlash"
cp scripts/macos/Info.plist "$STAGE/Contents/Info.plist"
cp scripts/macos/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
xattr -cr "$STAGE"

# ローカルの自己署名証明書(Keychain Access > 証明書アシスタントで作成)で署名する。
# Ad-hoc署名(--sign -)はビルドごとに識別子が変わり、Keychainのトークン読み取り許可が
# 毎回リセットされて確認ダイアログが出続けるため、固定の証明書を使う。
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-AutoFlash for ZMK Dev}"
codesign --force --sign "$CODESIGN_IDENTITY" "$STAGE"
codesign --verify "$STAGE"

APP="dist/AutoFlash for ZMK.app"
rm -rf "$APP"
mkdir -p dist
mv "$STAGE" "$APP"

echo "Built: $APP"
echo "起動: open '$APP'"
