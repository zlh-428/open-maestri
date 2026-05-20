#!/bin/bash
# build-maestri.sh — 本地 Release 打包脚本
# 用法：bash build-maestri.sh [--launch]
#   --launch   打包完成后自动启动 App

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
EXEC="$BUILD_DIR/open-maestri"
OUTPUT_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$OUTPUT_DIR/open-maestri.app"
SPARKLE="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

LAUNCH=false
for arg in "$@"; do
  [[ "$arg" == "--launch" ]] && LAUNCH=true
done

echo "🔨 Building open-maestri app + omaestri CLI..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

if [ ! -f "$EXEC" ]; then
  echo "✗ Build failed: executable not found at $EXEC"
  exit 1
fi

echo "▶ Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp "$EXEC" "$APP_BUNDLE/Contents/MacOS/open-maestri"
cp "$PROJECT_DIR/Sources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 将 CLI 二进制复制到 app bundle Resources
CLI_SRC="$BUILD_DIR/omaestri"
APP_RESOURCES="$APP_BUNDLE/Contents/Resources"
cp "$CLI_SRC" "$APP_RESOURCES/omaestri"
echo "✅ omaestri copied to $APP_RESOURCES"

# Assets（图标）
ASSETS_SRC="$PROJECT_DIR/Sources/Assets.xcassets"
if [ -d "$ASSETS_SRC" ]; then
  xcrun actool \
    --compile "$APP_BUNDLE/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist /dev/null \
    "$ASSETS_SRC" 2>/dev/null || true
fi

# 本地化字符串：将 .xcstrings 编译为各语言 .lproj/Localizable.strings
XCSTRINGS="$PROJECT_DIR/Sources/Resources/Localizable.xcstrings"
if [ -f "$XCSTRINGS" ]; then
  echo "▶ Compiling localizations..."
  python3 - "$XCSTRINGS" "$APP_BUNDLE/Contents/Resources" <<'PYEOF'
import json, os, sys

xcstrings_path = sys.argv[1]
resources_dir = sys.argv[2]

with open(xcstrings_path) as f:
    data = json.load(f)

langs = set()
for val in data["strings"].values():
    for lang in val.get("localizations", {}).keys():
        langs.add(lang)

for lang in langs:
    lproj_dir = os.path.join(resources_dir, f"{lang}.lproj")
    os.makedirs(lproj_dir, exist_ok=True)
    strings_path = os.path.join(lproj_dir, "Localizable.strings")
    lines = []
    for key, val in data["strings"].items():
        loc = val.get("localizations", {}).get(lang)
        if loc:
            string_unit = loc.get("stringUnit", {})
            translated = string_unit.get("value", key)
        else:
            # fallback to source language
            src = val.get("localizations", {}).get(data["sourceLanguage"], {})
            translated = src.get("stringUnit", {}).get("value", key)
        escaped = translated.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        lines.append(f'"{key}" = "{escaped}";')
    with open(strings_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"  ✅ {lang}.lproj/Localizable.strings ({len(lines)} keys)")
PYEOF
fi

# Sparkle framework
if [ -d "$SPARKLE" ]; then
  cp -R "$SPARKLE" "$APP_BUNDLE/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP_BUNDLE/Contents/MacOS/open-maestri" 2>/dev/null || true
  codesign --force --sign - \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
fi

# SwiftTerm（若编译为独立 dylib 则复制）
for dylib in "$BUILD_DIR"/*.dylib; do
  [ -f "$dylib" ] && cp "$dylib" "$APP_BUNDLE/Contents/Frameworks/" || true
done

echo "▶ Code signing (ad-hoc)..."
ENTITLEMENTS="$PROJECT_DIR/Sources/open-maestri.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
  codesign --force --deep --sign - \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo ""
echo "✓ Done: $APP_BUNDLE ($SIZE)"
echo ""

if $LAUNCH; then
  echo "▶ Launching..."
  pkill -x "open-maestri" 2>/dev/null || true
  sleep 0.3
  open "$APP_BUNDLE"
else
  echo "Tip: run with --launch to open automatically, or:"
  echo "  open \"$APP_BUNDLE\""
fi
