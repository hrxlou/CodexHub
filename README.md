# CodexHub

CodexHub is a local macOS menu bar utility for viewing Codex account status and switching between accounts already configured on this Mac.

CodexHub is an independent local utility. It is not an official OpenAI app.

CodexHub does not increase usage limits, bypass restrictions, or share credentials. Users are responsible for complying with OpenAI's terms and their workspace policies.

Usage and quota display is informational. When available, CodexHub can show best-effort local quota status fallback data for the currently active account.

## Privacy

CodexHub does not collect, store, export, import, sync, or proxy OpenAI or ChatGPT credentials. It does not run a remote service or sync account information to a CodexHub-controlled server.

No credentials, tokens, or account registry are bundled with this repository.

Account switching uses local `codex-auth` state for accounts already configured on this Mac. Switching is user-confirmed from the menu bar UI.

## Requirements

- macOS 14 or later
- Xcode command line tools or Xcode
- `codex-auth` installed and configured with the accounts you want to use locally

CodexHub expects `codex-auth` to be available on your `PATH`. After configuring your local accounts with `codex-auth`, verify that CodexHub will be able to read them:

```sh
codex-auth list
```

## Install

### Download ZIP from Releases

Download `CodexHub.zip` from the latest GitHub Release, unzip it, and move `CodexHub.app` to `/Applications`.

Dragging `CodexHub.app` into `/Applications` should work, but it does not remove macOS Gatekeeper checks. This project does not currently ship notarized builds, so on first launch macOS may require you to open the app from Finder with right-click, then Open.

To verify the download when a checksum file is provided:

```sh
shasum -a 256 -c CodexHub.zip.sha256
```

The command should print `CodexHub.zip: OK`.

After launch, CodexHub appears in the macOS menu bar.

### Build from Source

CodexHub can also be built and installed locally from source.

Build the app:

```sh
./build.sh
```

The app bundle is created at:

```sh
build/CodexHub.app
```

Then ad-hoc sign it for local use, copy it to `/Applications`, and open it:

```sh
codesign --force --deep --sign - build/CodexHub.app
rm -rf /Applications/CodexHub.app
cp -R build/CodexHub.app /Applications/CodexHub.app
xattr -cr /Applications/CodexHub.app
codesign --force --deep --sign - /Applications/CodexHub.app
open /Applications/CodexHub.app
```

After launch, CodexHub appears in the macOS menu bar.

## Release Packaging

Maintainers can create a release ZIP and checksum with:

```sh
./scripts/package.sh
```

The files are written to:

```sh
dist/CodexHub.zip
dist/CodexHub.zip.sha256
```

## Structure

- `Sources/main.swift`: SwiftUI app source
- `Resources/`: icons and CodexHub price book data
- `scripts/package.sh`: release ZIP packaging helper
- `Tools/GenerateIcon.swift`: icon generation helper
- `build.sh`: standalone build script
- `THIRD_PARTY_NOTICES.md`: third-party attribution and license notices

## Open Source Notes

CodexHub uses project-specific token scanning and price book data. Third-party notices are listed in `THIRD_PARTY_NOTICES.md`.

## License

MIT. See `LICENSE`.

Third-party notices are listed in `THIRD_PARTY_NOTICES.md`.
