#!/usr/bin/env bash
# scripts/update-appcast.sh
# 将新版本条目插入 appcast.xml（Sparkle 自动更新 feed）
#
# Usage:
#   bash scripts/update-appcast.sh <version> <build_number> <ed_signature> <length>
#
# Example:
#   bash scripts/update-appcast.sh 1.2.0 42 "abc123..." 5242880

set -euo pipefail

VERSION="${1:?版本号不能为空}"
BUILD_NUMBER="${2:?Build 号不能为空}"
ED_SIGNATURE="${3:?EdDSA 签名不能为空}"
LENGTH="${4:?文件大小不能为空}"

APPCAST="$(cd "$(dirname "$0")/.." && pwd)/appcast.xml"
DOWNLOAD_BASE="https://github.com/open-maestri/open-maestri/releases/download/v${VERSION}"
PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"

NEW_ITEM="    <item>
      <title>open-maestri ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url=\"${DOWNLOAD_BASE}/open-maestri-${VERSION}.zip\"
        sparkle:edSignature=\"${ED_SIGNATURE}\"
        length=\"${LENGTH}\"
        type=\"application/octet-stream\"
      />
    </item>"

# 将新条目插入到注释行之后（即列表顶部）
sed -i '' "s|    <!-- Items are prepended here by scripts/update-appcast.sh -->|${NEW_ITEM}\n    <!-- Items are prepended here by scripts/update-appcast.sh -->|" "$APPCAST"

echo "✅ appcast.xml updated with v${VERSION}"
