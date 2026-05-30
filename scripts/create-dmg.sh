#!/bin/bash
# create-dmg.sh — 将已打包的 .app bundle 封装为带图标的 DMG 安装包
# 用法：bash scripts/create-dmg.sh
#   输入：build/open-maestri.app
#   输出：build/Open.Maestri.dmg

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/build/open-maestri.app"
OUTPUT_DMG="$PROJECT_DIR/build/Open.Maestri.dmg"
TMP_DMG="$PROJECT_DIR/build/Open.Maestri.tmp.dmg"
STAGING="$PROJECT_DIR/build/dmg-staging"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "✗ App bundle not found: $APP_BUNDLE"
  echo "  Run 'bash scripts/build-maestri.sh' first."
  exit 1
fi

echo "▶ Preparing DMG staging area..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "▶ Creating writable DMG..."
hdiutil create \
  -volname "Open Maestri" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDRW \
  "$TMP_DMG"
rm -rf "$STAGING"

echo "▶ Setting volume icon..."
MOUNT_DIR=$(hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen | tail -1 | awk '{print $NF}')
cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR"
hdiutil detach "$MOUNT_DIR" -quiet

echo "▶ Compressing to final DMG..."
hdiutil convert "$TMP_DMG" \
  -format UDZO \
  -o "$OUTPUT_DMG"
rm -f "$TMP_DMG"

SIZE=$(du -sh "$OUTPUT_DMG" | cut -f1)
echo ""
echo "✓ Done: $OUTPUT_DMG ($SIZE)"
