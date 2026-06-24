# CodexHub

CodexHub is a local macOS menu bar app for switching Codex accounts and tracking quota/token usage.

## Build

```sh
./build.sh
```

The app bundle is created at:

```sh
build/CodexHub.app
```

## Install Locally

```sh
./build.sh
codesign --force --deep --sign - build/CodexHub.app
rm -rf /Applications/CodexHub.app
cp -R build/CodexHub.app /Applications/CodexHub.app
xattr -cr /Applications/CodexHub.app
codesign --force --deep --sign - /Applications/CodexHub.app
open /Applications/CodexHub.app
```

## Structure

- `Sources/main.swift`: SwiftUI app source
- `Resources/`: icons and CodexHub price book data
- `Tools/GenerateIcon.swift`: icon generation helper
- `build.sh`: standalone build script

## Open Source Notes

CodexHub keeps its token usage scanner and price book in a project-specific
format. The app reads local Codex JSONL session logs and does not vendor
third-party source files or assets.
