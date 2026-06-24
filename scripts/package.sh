#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$ROOT_DIR/build/CodexHub.app"
ZIP_PATH="$DIST_DIR/CodexHub.zip"
CHECKSUM_PATH="$DIST_DIR/CodexHub.zip.sha256"

"$ROOT_DIR/build.sh" >/dev/null

codesign --force --deep --sign - "$APP_PATH"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

ditto --norsrc --noextattr --noqtn --noacl -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
(cd "$DIST_DIR" && shasum -a 256 "CodexHub.zip" > "CodexHub.zip.sha256")

echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
