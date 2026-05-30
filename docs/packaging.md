# open-maestri Packaging Guide

A practical reference for building and distributing the open-maestri macOS app.

---

## Prerequisites

### Required

- **Xcode Command Line Tools**

  ```bash
  xcode-select --install
  ```

  Provides `swift`, `swiftc`, `xcodebuild`, `xcrun`, `codesign`, `lipo`, `hdiutil`, `install_name_tool`.

- **Swift 5.9+** (bundled with Xcode 15+)

  ```bash
  swift --version
  ```

### Optional

- **create-dmg** — polished DMG with background, icon layout, and window size

  ```bash
  brew install create-dmg
  ```

- **Sparkle `generate_keys` tool** — required once for EdDSA key setup (see [Sparkle Key Setup](#sparkle-edsa-key-setup-one-time))

---

## Build Commands

### Development Build

Produces a debug binary at `.build/debug/open-maestri`. The `dev.sh` script watches for changes and auto-relaunches:

```bash
# Manual debug build
swift build

# Auto-watch + relaunch (run alongside Xcode)
bash scripts/dev.sh
```

The dev script assembles a temporary `.app` bundle at `/tmp/maestri-app-build/open-maestri.app` and relaunches whenever Xcode rebuilds the debug binary.

### Release Build (Packaged .app)

```bash
bash scripts/build-maestri.sh
```

Produces `build/open-maestri.app`. To launch immediately after packaging:

```bash
bash scripts/build-maestri.sh --launch
```

---

## build-maestri.sh Walkthrough

The script performs these steps in order:

1. **Host-arch app build**
   Runs `swift build -c release` for the main `open-maestri` executable using the host architecture. Sparkle and SwiftTerm have framework/dylib dependencies that make a universal app binary impractical.

2. **Universal Binary for `omaestri` CLI**
   Builds `omaestri` separately for both `arm64-apple-macosx` and `x86_64-apple-macosx`, then merges them with `lipo -create` into a single universal binary. This matches the Maestri reference binary (~279 KB universal).

3. **App bundle assembly**
   Creates `build/open-maestri.app/Contents/{MacOS,Resources,Frameworks}` and copies:
   - Main executable → `Contents/MacOS/open-maestri`
   - `Info.plist` → `Contents/Info.plist`
   - Universal `omaestri` → `Contents/Resources/omaestri`

4. **Asset compilation**
   Compiles `Sources/Assets.xcassets` (app icon) via `xcrun actool` targeting macOS 14.0.

5. **Localization compilation**
   Converts `Sources/Resources/Localizable.xcstrings` to per-language `*.lproj/Localizable.strings` files using an embedded Python script.

6. **Sparkle framework embedding**
   Copies `Sparkle.framework` from the SPM artifact cache into `Contents/Frameworks/`, patches the rpath with `install_name_tool`, and ad-hoc signs the framework.

7. **Ad-hoc code signing**
   Signs the entire bundle with `codesign --force --deep --sign -`, applying `Sources/open-maestri.entitlements` if present.

---

## Packaging as DMG

### Option A: hdiutil (no extra tools)

```bash
VERSION="1.0.0"
APP="build/open-maestri.app"
DMG="build/open-maestri-${VERSION}.dmg"

# Create a writable staging image
hdiutil create -volname "open-maestri" \
  -srcfolder "$APP" \
  -ov -format UDRW \
  "build/staging.dmg"

# Convert to compressed read-only DMG
hdiutil convert "build/staging.dmg" \
  -format UDZO \
  -o "$DMG"

rm "build/staging.dmg"
echo "DMG: $DMG"
```

### Option B: create-dmg (polished, recommended for releases)

```bash
VERSION="1.0.0"
APP="build/open-maestri.app"
DMG="build/open-maestri-${VERSION}.dmg"

create-dmg \
  --volname "open-maestri" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "open-maestri.app" 180 170 \
  --hide-extension "open-maestri.app" \
  --app-drop-link 480 170 \
  "$DMG" \
  "$APP"
```

---

## Packaging as ZIP

Required for Sparkle's `appcast.xml` delta updates and as a GitHub Release artifact alongside the DMG.

```bash
VERSION="1.0.0"
APP="build/open-maestri.app"
ZIP="build/open-maestri-${VERSION}.zip"

ditto -c -k --keepParent "$APP" "$ZIP"
echo "ZIP: $ZIP"
```

> Use `ditto` rather than `zip` — it preserves macOS extended attributes and resource forks correctly.

---

## Computing Checksums

Provide SHA-256 checksums in release notes and `appcast.xml`:

```bash
VERSION="1.0.0"

# SHA-256
shasum -a 256 "build/open-maestri-${VERSION}.dmg"
shasum -a 256 "build/open-maestri-${VERSION}.zip"

# File size in bytes (required by Sparkle appcast)
stat -f%z "build/open-maestri-${VERSION}.zip"
```

---

## Sparkle EdDSA Key Setup (One-Time)

Sparkle 2.x uses Ed25519 signing. The public key lives in `Info.plist` under `SUPublicEDKey`; the private key must be stored securely and never committed.

### Generate keys

```bash
# From the Sparkle release archive or via SPM artifact
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

This prints a public key and writes the private key to the macOS Keychain under the service name `https://sparkle-project.org`.

### Store the public key

Paste the printed public key into `Sources/Info.plist`:

```xml
<key>SUPublicEDKey</key>
<string>PASTE_PUBLIC_KEY_HERE</string>
```

### Sign a release ZIP

```bash
.build/artifacts/sparkle/Sparkle/bin/sign_update "build/open-maestri-${VERSION}.zip"
```

Output is the `sparkle:edSignature` value for `appcast.xml`.

### appcast.xml entry template

```xml
<item>
  <title>Version 1.0.0</title>
  <sparkle:version>100</sparkle:version>
  <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
  <pubDate>Fri, 30 May 2026 00:00:00 +0000</pubDate>
  <enclosure
    url="https://example.com/releases/open-maestri-1.0.0.zip"
    sparkle:edSignature="SIGNATURE_FROM_sign_update"
    length="BYTE_SIZE"
    type="application/octet-stream"/>
</item>
```

---

## Signing Notes

### Current: Ad-hoc Signing (`--sign -`)

The build script signs with `-` (ad-hoc identity). This:

- Satisfies Gatekeeper's basic code integrity check on the same machine
- Does **not** produce a Developer ID signature — Gatekeeper will quarantine the app on other machines
- Users must right-click → Open on first launch, or run:

  ```bash
  xattr -dr com.apple.quarantine build/open-maestri.app
  ```

### Future: Developer ID Signing

To distribute outside the Mac App Store with full Gatekeeper trust:

1. Obtain a **Developer ID Application** certificate from the Apple Developer portal.
2. Replace `--sign -` in the build script with:

   ```bash
   --sign "Developer ID Application: Your Name (TEAM_ID)"
   ```

3. Sign Sparkle.framework with the same identity before signing the app bundle.
4. Proceed to notarization (see below).

---

## Notarization (Future Path)

Notarization is required for Developer ID-signed apps distributed outside the App Store on macOS 10.15+.

```bash
# Submit for notarization
xcrun notarytool submit "build/open-maestri-${VERSION}.dmg" \
  --apple-id "you@example.com" \
  --team-id "TEAM_ID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# Staple the notarization ticket to the DMG
xcrun stapler staple "build/open-maestri-${VERSION}.dmg"

# Verify
spctl -a -t open --context context:primary-signature \
  -v "build/open-maestri-${VERSION}.dmg"
```

Store credentials in the Keychain:

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "you@example.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password"
```

> Notarization requires a paid Apple Developer Program membership and a Developer ID certificate. It is not compatible with ad-hoc signing.
