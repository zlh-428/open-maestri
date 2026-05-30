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
# 用 -plist 解析 hdiutil 输出，读取真实挂载点，不依赖 -mountpoint 猜测路径
MOUNT_DIR=$(hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen -plist | \
  python3 -c "
import sys, plistlib
data = plistlib.loads(sys.stdin.buffer.read())
for entity in data.get('system-entities', []):
    mp = entity.get('mount-point', '')
    if mp:
        print(mp)
        break
")

if [ -z "$MOUNT_DIR" ]; then
  echo "✗ hdiutil attach 未能获取挂载点"
  exit 1
fi
echo "  → 挂载于: ${MOUNT_DIR}"

# 复制卷图标（若 AppIcon.icns 存在）
if [ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
  cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
  # SetFile 在新版 Xcode CLI 中已废弃，若可用则设置自定义图标标志，否则跳过
  if command -v SetFile &>/dev/null; then
    SetFile -a C "$MOUNT_DIR"
  fi
fi

hdiutil detach "$MOUNT_DIR" -quiet

echo "▶ Compressing to final DMG..."
hdiutil convert "$TMP_DMG" \
  -format UDZO \
  -o "$OUTPUT_DMG"
rm -f "$TMP_DMG"

SIZE=$(du -sh "$OUTPUT_DMG" | cut -f1)
echo ""
echo "✓ Done: $OUTPUT_DMG ($SIZE)"
