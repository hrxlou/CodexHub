#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME="CodexHub"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BIN_PATH="$MACOS_DIR/CodexHub"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR"

if [[ ! -f "$ROOT_DIR/Resources/CodexHub.icns" \
  || ! -f "$ROOT_DIR/Resources/CodexHubMenuIcon.png" \
  || ! -f "$ROOT_DIR/Resources/CodexHubIcon.png" \
  || ! -f "$ROOT_DIR/Resources/CodexHubIconLight.png" \
  || ! -f "$ROOT_DIR/Resources/CodexHubIconDark.png" \
  || "$ROOT_DIR/Resources/CodexHubIconSource.png" -nt "$ROOT_DIR/Resources/CodexHub.icns" ]]; then
  xcrun swift "$ROOT_DIR/Tools/GenerateIcon.swift" "$ROOT_DIR"
fi

cp "$ROOT_DIR/Resources/PriceBook.json" "$RESOURCES_DIR/PriceBook.json"
cp "$ROOT_DIR/Resources/CodexHub.icns" "$RESOURCES_DIR/CodexHub.icns"
cp "$ROOT_DIR/Resources/CodexHubIcon.png" "$RESOURCES_DIR/CodexHubIcon.png"
cp "$ROOT_DIR/Resources/CodexHubIconLight.png" "$RESOURCES_DIR/CodexHubIconLight.png"
cp "$ROOT_DIR/Resources/CodexHubIconDark.png" "$RESOURCES_DIR/CodexHubIconDark.png"
cp "$ROOT_DIR/Resources/CodexHubMenuIcon.png" "$RESOURCES_DIR/CodexHubMenuIcon.png"
cp "$ROOT_DIR/LICENSE" "$RESOURCES_DIR/LICENSE"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"

if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

SOURCE_FILES=()
while IFS= read -r source_file; do
  SOURCE_FILES+=("$source_file")
done < <(find "$ROOT_DIR/Sources" -name '*.swift' -print | sort)

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" xcrun swiftc "${SOURCE_FILES[@]}" \
  -parse-as-library \
  -target arm64-apple-macosx14.0 \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework SwiftUI \
  -framework AppKit \
  -o "$BIN_PATH"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>CodexHub</string>
  <key>CFBundleIdentifier</key>
  <string>local.codexhub</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>CodexHub</string>
  <key>CFBundleDisplayName</key>
  <string>CodexHub</string>
  <key>CFBundleIconFile</key>
  <string>CodexHub.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.3.0</string>
  <key>CFBundleVersion</key>
  <string>6</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
