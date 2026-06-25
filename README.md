# CodexHub

[English](#codexhub) | [한국어](#codexhub-한국어)

CodexHub is a local macOS utility for checking locally configured Codex accounts and switching the active account.

## Features

- View locally configured Codex accounts
- Add, remove, and switch locally stored Codex accounts
- See best-effort local usage and quota status when available
- Open a lightweight settings panel for status lookup behavior

## Requirements

- macOS 14 or later
- Codex CLI available locally as `codex`

CodexHub delegates new sign-ins to the official Codex CLI login flow, then stores the resulting local Codex auth snapshot for account switching.

Add the Codex accounts you want to manage from the CodexHub account management panel. CodexHub opens the normal Codex browser login flow and saves the account after login completes.

If you previously used `codex-auth`, CodexHub reads and writes the same local `~/.codex/accounts` account store format, so existing stored accounts should appear without reinstalling or invoking `codex-auth`.

## Install

### Download ZIP from Releases

Download `CodexHub.zip` from the latest GitHub Release, unzip it, and move `CodexHub.app` to `/Applications`.

On first launch, macOS may warn that the app cannot be opened because it was downloaded from the internet. If that happens, open Finder, right-click `CodexHub.app`, and choose **Open**.

Use the `.sha256` file published with the release to verify the ZIP:

```sh
shasum -a 256 -c CodexHub.zip.sha256
```

The command should print `CodexHub.zip: OK`.

After launch, CodexHub appears in the macOS menu bar.

### Build from Source

CodexHub can also be built and installed locally from source.

Building from source requires Xcode Command Line Tools or Xcode because the build script uses Apple's Swift compiler tools.

Build the app:

```sh
./build.sh
```

The app bundle is created at:

```sh
build/CodexHub.app
```

Then ad-hoc sign it for local use, copy it to `/Applications`, remove the quarantine attribute, and open it:

```sh
codesign --force --deep --sign - build/CodexHub.app
ditto build/CodexHub.app /Applications/CodexHub.app
xattr -cr /Applications/CodexHub.app
open /Applications/CodexHub.app
```

After launch, CodexHub appears in the macOS menu bar.

## Package a Release

Create the release ZIP and checksum with:

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

## Privacy and Usage Notes

CodexHub is an independent local utility. It is not an official OpenAI app.

CodexHub does not increase usage limits, bypass restrictions, or share credentials. Users are responsible for complying with OpenAI's terms and their workspace policies.

Usage and quota display is informational. When available, CodexHub can show best-effort local quota status fallback data for the currently active account.

CodexHub stores Codex auth snapshots locally under your Codex home directory, usually `~/.codex/accounts`, so it can switch accounts later. Treat those files like passwords. CodexHub does not run a remote service or sync account information to a CodexHub-controlled server.

No credentials, tokens, or account registry are bundled with this repository.

Account switching uses local Codex auth snapshots already stored on this Mac. Switching is user-confirmed from the app UI.

CodexHub does not require or invoke the external `codex-auth` executable. Its account store remains compatible with the `codex-auth` local format for users who already have stored accounts.

---

# CodexHub 한국어

[English](#codexhub) | [한국어](#codexhub-한국어)

CodexHub는 로컬에 설정된 Codex 계정을 확인하고 활성 계정을 전환할 수 있는 macOS 유틸리티입니다.

## 기능

- 로컬에 설정된 Codex 계정 확인
- 로컬에 저장된 Codex 계정 추가, 삭제, 전환
- 가능한 경우 로컬에서 확인 가능한 최선의 사용량 및 할당량 상태 표시
- 상태 조회 동작을 조정할 수 있는 가벼운 설정 패널 제공

## 요구 사항

- macOS 14 이상
- 로컬에서 사용할 수 있는 Codex CLI `codex`

CodexHub는 새 로그인을 공식 Codex CLI 로그인 흐름에 위임한 뒤, 생성된 로컬 Codex 인증 snapshot을 계정 전환용으로 저장합니다.

CodexHub 계정 관리 패널에서 로컬로 관리할 Codex 계정을 추가하세요. CodexHub는 일반 Codex 브라우저 로그인 흐름을 열고, 로그인이 끝나면 해당 계정을 저장합니다.

이전에 `codex-auth`를 사용했다면, CodexHub가 같은 로컬 `~/.codex/accounts` 계정 저장소 형식을 읽고 쓰므로 기존 저장 계정이 별도 재설치나 실행 없이 표시됩니다.

## 설치

### Releases에서 ZIP 다운로드

최신 GitHub Release에서 `CodexHub.zip`을 다운로드하고 압축을 푼 뒤, `CodexHub.app`을 `/Applications`로 옮기세요.

처음 실행할 때 macOS가 인터넷에서 다운로드한 앱이라며 실행을 막을 수 있습니다. 그럴 때는 Finder에서 `CodexHub.app`을 우클릭한 뒤 **열기**를 선택하세요.

릴리스와 함께 제공되는 `.sha256` 파일로 ZIP 파일을 검증할 수 있습니다.

```sh
shasum -a 256 -c CodexHub.zip.sha256
```

명령은 `CodexHub.zip: OK`를 출력해야 합니다.

실행 후 CodexHub는 macOS 메뉴 막대에 표시됩니다.

### 소스에서 빌드

CodexHub는 소스에서 로컬로 빌드하고 설치할 수도 있습니다.

소스에서 빌드하려면 빌드 스크립트가 Apple의 Swift 컴파일러 도구를 사용하므로 Xcode 명령줄 도구 또는 Xcode가 필요합니다.

앱을 빌드합니다.

```sh
./build.sh
```

앱 번들은 다음 위치에 생성됩니다.

```sh
build/CodexHub.app
```

그다음 로컬 사용을 위해 ad-hoc 서명하고, `/Applications`로 복사한 뒤 quarantine 속성을 제거하고 실행합니다.

```sh
codesign --force --deep --sign - build/CodexHub.app
ditto build/CodexHub.app /Applications/CodexHub.app
xattr -cr /Applications/CodexHub.app
open /Applications/CodexHub.app
```

실행 후 CodexHub는 macOS 메뉴 막대에 표시됩니다.

## 릴리스 패키지 만들기

다음 명령으로 릴리스 ZIP과 체크섬을 생성할 수 있습니다.

```sh
./scripts/package.sh
```

파일은 다음 위치에 생성됩니다.

```sh
dist/CodexHub.zip
dist/CodexHub.zip.sha256
```

## 구조

- `Sources/main.swift`: SwiftUI 앱 소스
- `Resources/`: 아이콘 및 CodexHub 가격표 데이터
- `scripts/package.sh`: 릴리스 ZIP 패키징 헬퍼
- `Tools/GenerateIcon.swift`: 아이콘 생성 헬퍼
- `build.sh`: 독립 실행형 빌드 스크립트
- `THIRD_PARTY_NOTICES.md`: 타사 저작권 표시 및 라이선스 고지

## 오픈 소스 참고 사항

CodexHub는 프로젝트 전용 토큰 스캔 및 가격표 데이터를 사용합니다. 타사 고지는 `THIRD_PARTY_NOTICES.md`에 정리되어 있습니다.

## 라이선스

MIT. `LICENSE`를 참고하세요.

타사 고지는 `THIRD_PARTY_NOTICES.md`에 정리되어 있습니다.

## 개인정보 및 사용 참고 사항

CodexHub는 독립적인 로컬 유틸리티이며, OpenAI의 공식 앱이 아닙니다.

CodexHub는 사용 한도를 늘리거나, 제한을 우회하거나, 자격 증명을 공유하지 않습니다. 사용자는 OpenAI 약관과 본인 워크스페이스 정책을 준수할 책임이 있습니다.

사용량 및 할당량 표시는 참고용입니다. 가능한 경우 CodexHub는 현재 활성 계정에 대해 로컬에서 확인 가능한 최선의 할당량 상태 대체 데이터를 표시할 수 있습니다.

CodexHub는 나중에 계정을 전환할 수 있도록 Codex 인증 snapshot을 보통 `~/.codex/accounts`인 Codex 홈 디렉터리 아래에 로컬로 저장합니다. 이 파일들은 비밀번호처럼 다루세요. CodexHub는 원격 서비스를 실행하지 않으며, 계정 정보를 CodexHub가 관리하는 서버로 동기화하지 않습니다.

이 저장소에는 자격 증명, 토큰, 계정 레지스트리가 포함되어 있지 않습니다.

계정 전환은 이 Mac에 로컬로 저장된 Codex 인증 snapshot을 사용합니다. 전환은 앱 UI에서 사용자가 확인한 뒤 수행됩니다.

CodexHub는 외부 `codex-auth` 실행 파일을 필요로 하지 않고 호출하지도 않습니다. 다만 기존 저장 계정이 있는 사용자를 위해 `codex-auth` 로컬 저장소 형식과 호환됩니다.
