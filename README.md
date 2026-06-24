# CodexHub

[English](#codexhub) | [한국어](#codexhub-한국어)

CodexHub is a local macOS utility for checking locally configured Codex accounts and switching the active account.

## Features

- View locally configured Codex accounts
- Switch between accounts already available through `codex-auth`
- See best-effort local usage and quota status when available
- Open a lightweight settings panel for status lookup behavior

## Requirements

- macOS 14 or later
- `codex-auth` installed and configured with the accounts you want to use locally

CodexHub does not bundle or install `codex-auth`. Install it separately from the upstream project and review its behavior before use.

If you use npm, install `codex-auth` with:

```sh
npm install -g @loongphy/codex-auth
```

The current npm release may require Node.js 22 or later. `codex-auth login` also requires the `codex` command to be available on your `PATH`.

Confirm that the command is available:

```sh
codex-auth --version
```

If you have not added accounts yet, use `codex-auth` to add the Codex accounts you want to manage on this Mac:

```sh
codex-auth login
```

Repeat the login flow for each account you want to add. If your accounts are already registered in `codex-auth`, you can skip this step.

Verify that CodexHub will be able to read the local account list:

```sh
codex-auth list
```

For import options, aliases, and current command details, see the upstream `codex-auth` documentation: <https://github.com/Loongphy/codex-auth>

## Troubleshooting

### Detailed status lookup

**Detailed status lookup (experimental)** is off by default. Turn it on when you want CodexHub to ask `codex-auth` for more detailed account status.

Detailed lookup can be more accurate than local-only status, but it depends on the installed `codex-auth` version and its configuration. If status lookup becomes unreliable, turn this setting off. Quota and usage display is informational only.

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

CodexHub does not collect, store, export, import, sync, or proxy OpenAI or ChatGPT credentials. It does not run a remote service or sync account information to a CodexHub-controlled server.

No credentials, tokens, or account registry are bundled with this repository.

Account switching uses local `codex-auth` state for accounts already configured on this Mac. Switching is user-confirmed from the app UI.

`codex-auth` is an external tool and is not bundled with CodexHub. CodexHub only invokes a user-installed `codex-auth` executable found locally on this Mac.

---

# CodexHub 한국어

[English](#codexhub) | [한국어](#codexhub-한국어)

CodexHub는 로컬에 설정된 Codex 계정을 확인하고 활성 계정을 전환할 수 있는 macOS 유틸리티입니다.

## 기능

- 로컬에 설정된 Codex 계정 확인
- `codex-auth`를 통해 이미 사용할 수 있는 계정 간 전환
- 가능한 경우 로컬에서 확인 가능한 최선의 사용량 및 할당량 상태 표시
- 상태 조회 동작을 조정할 수 있는 가벼운 설정 패널 제공

## 요구 사항

- macOS 14 이상
- 로컬에서 사용하려는 계정이 설정된 `codex-auth`

CodexHub는 `codex-auth`를 앱에 포함하거나 대신 설치하지 않습니다. 별도로 설치하고, 사용 전에 동작 방식을 확인하세요.

npm을 사용한다면 다음 명령으로 `codex-auth`를 설치할 수 있습니다.

```sh
npm install -g @loongphy/codex-auth
```

현재 npm 릴리스는 Node.js 22 이상을 요구할 수 있습니다. `codex-auth login`은 `codex` 명령이 `PATH`에서 실행 가능해야 합니다.

명령이 실행 가능한지 확인합니다.

```sh
codex-auth --version
```

아직 계정을 추가하지 않았다면 `codex-auth`로 이 Mac에서 관리할 Codex 계정을 추가합니다.

```sh
codex-auth login
```

추가하려는 계정마다 로그인 흐름을 반복하세요. 이미 `codex-auth`에 계정이 등록되어 있다면 이 단계는 건너뛰어도 됩니다.

CodexHub가 로컬 계정 목록을 읽을 수 있는지 확인합니다.

```sh
codex-auth list
```

가져오기, 별칭, 최신 명령 설명은 upstream `codex-auth` 문서를 참고하세요: <https://github.com/Loongphy/codex-auth>

## 문제 해결

### 상세 상태 조회

**상세 상태 조회 (실험적)**는 기본적으로 꺼져 있습니다. CodexHub가 `codex-auth`에 더 자세한 계정 상태 조회를 요청하게 하려면 켜세요.

상세 조회는 로컬 전용 상태보다 더 정확할 수 있지만, 설치된 `codex-auth` 버전과 설정의 영향을 받습니다. 상태 조회가 불안정하면 이 설정을 끄세요. 할당량 및 사용량 표시는 참고용입니다.

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

CodexHub는 OpenAI 또는 ChatGPT 자격 증명을 수집, 저장, 내보내기, 가져오기, 동기화하거나 프록시하지 않습니다. 원격 서비스를 실행하지 않으며, 계정 정보를 CodexHub가 관리하는 서버로 동기화하지 않습니다.

이 저장소에는 자격 증명, 토큰, 계정 레지스트리가 포함되어 있지 않습니다.

계정 전환은 이 Mac에 이미 설정된 계정의 로컬 `codex-auth` 상태를 사용합니다. 전환은 앱 UI에서 사용자가 확인한 뒤 수행됩니다.

`codex-auth`는 CodexHub에 포함되지 않는 외부 도구입니다. CodexHub는 이 Mac에 사용자가 설치한 `codex-auth` 실행 파일을 로컬에서 호출합니다.
