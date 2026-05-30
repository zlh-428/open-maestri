# Releasing open-maestri

This document describes the manual release process for open-maestri.

---

## Version Number (Semantic Versioning)

```
MAJOR.MINOR.PATCH
```

| Bump | When |
|------|------|
| MAJOR | Breaking changes to workspace format or IPC protocol |
| MINOR | New features (new node types, CLI commands, canvas capabilities) |
| PATCH | Bug fixes, performance improvements, localization updates |

Current version is declared in `Sources/Info.plist` (`CFBundleShortVersionString` + `CFBundleVersion`).

---

## Pre-Release Checklist

### 1. Verify the codebase

```bash
# Run all tests
swift test

# Release build (catches link/symbol errors that debug builds hide)
swift build -c release
```

### 2. Update version in Info.plist

Edit `Sources/Info.plist` — bump both fields together:

```xml
<key>CFBundleShortVersionString</key>
<string>1.2.0</string>          <!-- human-readable, e.g. 1.2.0 -->
<key>CFBundleVersion</key>
<string>120</string>            <!-- monotonically increasing integer, e.g. 120 -->
```

### 3. Update the Sparkle appcast

Edit `appcast.xml` (create if absent, see template below) — add a new `<item>` before committing.

### 4. Write the Release Notes

Follow the [Release Notes format](#release-notes-format) below and add an entry to `CHANGELOG.md`.

### 5. Commit and tag

```bash
# Stage the version bump + changelog
git add Sources/Info.plist appcast.xml CHANGELOG.md

git commit -m "🔖 chore(release): bump version to 1.2.0"

# Lightweight tag — GitHub uses this as the release name
git tag v1.2.0

git push origin main --tags
```

### 6. Build the release package

```bash
# Produces build/open-maestri.app (ad-hoc signed, Sparkle bundled)
bash build-maestri.sh

# Package as DMG (requires create-dmg or hdiutil)
# Option A — hdiutil (built-in, no extras needed)
hdiutil create -volname "open-maestri 1.2.0" \
  -srcfolder build/open-maestri.app \
  -ov -format UDZO \
  build/open-maestri-1.2.0.dmg

# Option B — create-dmg (prettier window)
# brew install create-dmg
# create-dmg \
#   --volname "open-maestri 1.2.0" \
#   --window-size 600 400 \
#   --icon-size 128 \
#   --app-drop-link 450 200 \
#   build/open-maestri-1.2.0.dmg \
#   build/open-maestri.app

# ZIP (alternative distribution)
cd build
zip -r --symlinks open-maestri-1.2.0-macos.zip open-maestri.app
cd ..
```

### 7. Compute checksums

```bash
shasum -a 256 build/open-maestri-1.2.0.dmg
shasum -a 256 build/open-maestri-1.2.0-macos.zip
```

### 8. Create the GitHub Release

1. Go to `https://github.com/your-org/open-maestri/releases/new`
2. Choose tag `v1.2.0`
3. Set title: `open-maestri v1.2.0`
4. Paste the bilingual release notes (see format below)
5. Upload `open-maestri-1.2.0.dmg` and `open-maestri-1.2.0-macos.zip`
6. Publish release

### 9. Update the Sparkle appcast and push

After uploading assets, update the `<enclosure url=...>` in `appcast.xml` with the real GitHub asset download URL, then push.

---

## Release Notes Format

Use the bilingual template below. English first, Chinese second.

```markdown
## What's New in open-maestri v1.2.0

### ✨ New Features
- Canvas: added multi-select with drag-lasso
- File Tree: support Git stage/unstage from context menu

### 🐛 Bug Fixes
- Fixed node disappearing during pinch-zoom on Retina display
- Portal: prevent repeated URL loads on workspace restore

### ⚡ Performance
- Cold launch now under 1.5s on Apple Silicon

### 🔧 Improvements
- omaestri CLI shipped as Universal Binary (arm64 + x86_64)

---

## v1.2.0 更新内容

### ✨ 新功能
- 画布：支持拖拽框选多选节点
- 文件树：右键菜单支持 Git stage / unstage 操作

### 🐛 问题修复
- 修复 Retina 屏幕捏合缩放时节点消失的问题
- Portal 节点：修复工作区恢复后 URL 重复加载的问题

### ⚡ 性能优化
- Apple Silicon 上冷启动时间降至 1.5s 以内

### 🔧 改进
- omaestri CLI 现在以 Universal Binary（arm64 + x86_64）分发
```

### Change Category Reference

| Emoji | Category | 中文 |
|-------|----------|------|
| ✨ | New Features | 新功能 |
| 🐛 | Bug Fixes | 问题修复 |
| ⚡ | Performance | 性能优化 |
| 🔧 | Improvements | 改进 |
| 🔒 | Security | 安全 |
| 🌍 | Localization | 本地化 |
| 💥 | Breaking Changes | 不兼容变更 |
| 🗑️ | Removed | 已移除 |

---

## Installation Instructions (for Release page)

```markdown
### Installation

**Requirements:** macOS 14.0 (Sonoma) or later · Apple Silicon or Intel

1. Download `open-maestri-1.2.0.dmg`
2. Open the DMG and drag **open-maestri.app** to your Applications folder
3. On first launch, right-click the app and choose **Open** to bypass Gatekeeper
   (the app is ad-hoc signed, not notarized — see note below)

**Auto-update:** open-maestri uses [Sparkle](https://sparkle-project.org/) for in-app update checks.
Once installed, go to **open-maestri → Check for Updates…** to receive future releases automatically.
```

---

## Release Assets

| File | Description |
|------|-------------|
| `open-maestri-{VERSION}.dmg` | Disk image — recommended for most users |
| `open-maestri-{VERSION}-macos.zip` | ZIP archive — for scripted installs or CI environments |

Both assets contain the same `.app` bundle.

---

## Sparkle Appcast

`appcast.xml` lives at the repository root. Sparkle polls the URL declared in
`Sources/Info.plist` under `SUFeedURL`.

### Template

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>open-maestri Updates</title>
    <link>https://github.com/your-org/open-maestri</link>
    <language>en</language>

    <item>
      <title>open-maestri 1.2.0</title>
      <pubDate>Sat, 24 May 2025 12:00:00 +0000</pubDate>
      <sparkle:version>120</sparkle:version>
      <sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>What's New</h2>
        <ul>
          <li>Canvas: added multi-select with drag-lasso</li>
          <li>Fixed node disappearing during pinch-zoom</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://github.com/your-org/open-maestri/releases/download/v1.2.0/open-maestri-1.2.0.dmg"
        sparkle:version="120"
        sparkle:shortVersionString="1.2.0"
        length="12345678"
        type="application/octet-stream"
        sparkle:edSignature="PLACEHOLDER_ED25519_SIGNATURE" />
    </item>

  </channel>
</rss>
```

> **`sparkle:edSignature`** — generate with Sparkle's `sign_update` tool:
> ```bash
> .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/Resources/sign_update \
>   build/open-maestri-1.2.0.dmg
> ```
> Paste the printed signature into `sparkle:edSignature`. The corresponding public key must be set in `SUPublicEDKey` in `Info.plist`.

---

## Code Signing Notes

The `build-maestri.sh` script signs the app **ad-hoc** (`--sign -`). This means:

- The app runs on any Mac without requiring an Apple Developer account.
- macOS Gatekeeper will show a warning on first launch on other machines — users must right-click → Open to bypass it.
- The app **cannot be distributed via the Mac App Store** and is **not notarized**.

To distribute notarized builds in the future:

1. Obtain an Apple Developer account and a Developer ID Application certificate.
2. Replace `--sign -` with `--sign "Developer ID Application: Your Name (TEAMID)"` in `build-maestri.sh`.
3. Submit the `.dmg` to Apple notarization: `xcrun notarytool submit ...`
4. Staple the ticket: `xcrun stapler staple build/open-maestri-1.2.0.dmg`

---

## Build Script Reference

`build-maestri.sh` performs the following steps automatically:

1. `swift build -c release` — main app (host architecture)
2. Builds `omaestri` CLI as a Universal Binary (arm64 + x86_64 via `lipo`)
3. Assembles `build/open-maestri.app` bundle with `Info.plist`, icon, localizations
4. Copies `Sparkle.framework` into `Contents/Frameworks/`
5. Ad-hoc code signs the entire bundle

**Options:**

```bash
bash build-maestri.sh           # build only
bash build-maestri.sh --launch  # build then open the app
```

Output: `build/open-maestri.app`
