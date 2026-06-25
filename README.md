# CodexHub

[English](#codexhub) | [한국어](#codexhub-한국어)

CodexHub is a local macOS utility for checking locally configured Codex accounts and switching the active account.

## Features

- View locally configured Codex accounts
- Add, remove, and switch locally stored Codex accounts from the menu bar
- See best-effort local token usage and per-account quota status when available
- Open a lightweight settings panel for status lookup behavior

## Requirements

- macOS 14 or later on Apple Silicon
- Codex CLI available locally as `codex`

CodexHub delegates new sign-ins to the official Codex CLI login flow, then stores the resulting local Codex auth snapshot for account switching.

Add only Codex accounts you own or are authorized to use from the CodexHub account management panel. CodexHub opens the normal Codex browser login flow in an isolated Codex home and saves the account after login completes. Adding an account does not activate it; switch explicitly from the account card when you want to use it. Sharing or storing someone else's credentials is not supported.

If you previously used `codex-auth`, CodexHub reads and writes the same local `accounts/registry.json` and `*.auth.json` account store layout under `CODEX_HOME` or `~/.codex`, so existing stored accounts should appear without reinstalling or invoking `codex-auth`.

## Account Management

- **Add account** opens the official `codex login` flow with file-backed credentials in an isolated temporary `CODEX_HOME`, then stores the resulting auth snapshot in the local account registry.
- **Switch account** replaces the active Codex `auth.json` with the selected stored snapshot, validates it, and restores the previous auth and registry state if validation fails.
- **Remove account** is available only for inactive accounts. Removal deletes the stored auth snapshot and registry entry together, so a failed removal does not leave the registry and snapshot out of sync.
- **Codex app restart** is attempted after a successful switch for `/Applications/Codex.app` / `com.openai.codex` only. ChatGPT is not targeted. CodexHub never force-quits Codex; if Codex shows an interrupt confirmation, CodexHub waits for your choice and cancels the restart if Codex remains open.
- Confirmation overlays use **Cancel** for the non-destructive choice; pressing `Esc` also cancels the overlay.

## Usage and Quota

CodexHub scans local Codex session logs to estimate token usage and uses an account attribution history to split usage by account. Attribution changes only when you explicitly switch accounts or reset the attribution history.

When detailed status lookup is enabled, CodexHub queries `codex app-server --stdio` for quota status. The active account is queried through the current Codex home; inactive accounts are queried through temporary Codex homes created from their stored snapshots. Quota cache entries are stored per account identity, so one account's fallback status does not overwrite another's.

When detailed status lookup is disabled or unavailable, CodexHub falls back to the most recent local session quota status from the resolved Codex home. Quota and usage values are best-effort informational data.

Switch suggestions are off by default. When enabled, CodexHub only shows a prompt; it does not silently switch accounts because quota is low.

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

CodexHub does not increase usage limits, bypass restrictions, or share credentials. Do not use it to bypass OpenAI or organization/school usage limits, policies, or access restrictions. Users are responsible for complying with OpenAI's terms and any applicable workspace, organization, or school policies.

Usage and quota display is informational. When available, CodexHub can show best-effort quota status for the active account and stored inactive accounts, with per-account fallback cache data.

CodexHub stores Codex auth snapshots locally under your Codex home directory, using `CODEX_HOME` when set and `~/.codex` otherwise. Treat `auth.json`, `accounts/registry.json`, and `accounts/*.auth.json` like passwords. CodexHub does not run a remote service or sync account information to a CodexHub-controlled server.

No credentials, tokens, or account registry are bundled with this repository.

Account switching uses local Codex auth snapshots already stored on this Mac. Switching is user-confirmed from the app UI, validated after writing, and rolled back if validation fails.

CodexHub does not require or invoke the external `codex-auth` executable. Its account store remains compatible with the `codex-auth` local format for users who already have stored accounts.

## Security Roadmap

- Move the default credential store to macOS Keychain. Keep codex-auth compatible files only for import/export or a short-lived compatibility cache.

---

# CodexHub 한국어

[English](#codexhub) | [한국어](#codexhub-한국어)

CodexHub는 로컬에 설정된 Codex 계정을 확인하고 활성 계정을 전환할 수 있는 macOS 유틸리티입니다.

## 기능

- 로컬에 설정된 Codex 계정 확인
- 메뉴 막대에서 로컬에 저장된 Codex 계정 추가, 삭제, 전환
- 가능한 경우 로컬 토큰 사용량 및 계정별 할당량 상태 표시
- 상태 조회 동작을 조정할 수 있는 가벼운 설정 패널 제공

## 요구 사항

- Apple Silicon Mac의 macOS 14 이상
- 로컬에서 사용할 수 있는 Codex CLI `codex`

CodexHub는 새 로그인을 공식 Codex CLI 로그인 흐름에 위임한 뒤, 생성된 로컬 Codex 인증 snapshot을 계정 전환용으로 저장합니다.

CodexHub 계정 관리 패널에는 본인이 소유하거나 사용 권한이 있는 Codex 계정만 추가하세요. CodexHub는 격리된 임시 Codex 홈에서 일반 Codex 브라우저 로그인 흐름을 열고, 로그인이 끝나면 해당 계정을 저장합니다. 계정 추가만으로는 활성 계정이 바뀌지 않으며, 사용할 때 계정 카드에서 명시적으로 전환합니다. 타인의 credential 공유나 저장은 지원하지 않습니다.

이전에 `codex-auth`를 사용했다면, CodexHub가 `CODEX_HOME` 또는 `~/.codex` 아래의 같은 로컬 `accounts/registry.json` 및 `*.auth.json` 계정 저장소 레이아웃을 읽고 쓰므로 기존 저장 계정이 별도 재설치나 실행 없이 표시됩니다.

## 계정 관리

- **계정 추가**는 공식 `codex login` 흐름을 파일 기반 인증 저장 방식으로 격리된 임시 `CODEX_HOME`에서 실행한 뒤, 생성된 인증 snapshot을 로컬 계정 registry에 저장합니다.
- **계정 전환**은 활성 Codex `auth.json`을 선택한 저장 snapshot으로 교체하고 검증합니다. 검증에 실패하면 이전 auth와 registry 상태를 복원합니다.
- **계정 삭제**는 비활성 계정에서만 가능합니다. 삭제는 저장된 auth snapshot과 registry 항목을 함께 제거하며, 실패 시 registry와 snapshot이 서로 어긋나지 않도록 복원합니다.
- **Codex 앱 재시작**은 전환 성공 후 `/Applications/Codex.app` 또는 `com.openai.codex`만 대상으로 시도합니다. ChatGPT는 대상에 포함하지 않습니다. CodexHub는 Codex를 강제 종료하지 않으며, Codex가 작업 인터럽트 확인을 표시하면 사용자의 선택을 기다리고 Codex가 계속 열려 있으면 재시작을 취소합니다.
- 확인 overlay의 비파괴 선택지는 **취소**로 표시되며, `Esc` 키도 같은 취소 동작을 수행합니다.

## 사용량 및 할당량

CodexHub는 로컬 Codex session 로그를 스캔해 토큰 사용량을 추정하고, 계정 연결 기록을 이용해 사용량을 계정별로 나눕니다. 계정 연결 기록은 명시적 계정 전환 또는 기록 초기화 시에만 바뀝니다.

상세 상태 조회가 켜져 있으면 CodexHub는 `codex app-server --stdio`로 할당량 상태를 조회합니다. 활성 계정은 현재 Codex 홈으로 조회하고, 비활성 계정은 저장 snapshot으로 만든 임시 Codex 홈을 통해 조회합니다. 할당량 cache는 계정 identity별로 저장되므로 한 계정의 fallback 상태가 다른 계정을 덮어쓰지 않습니다.

상세 상태 조회가 꺼져 있거나 사용할 수 없으면 CodexHub는 resolved Codex 홈의 최근 로컬 session 할당량 상태를 fallback으로 사용합니다. 사용량과 할당량 값은 참고용 best-effort 데이터입니다.

전환 제안은 기본적으로 꺼져 있습니다. 켜더라도 CodexHub는 제안 prompt만 표시하며, 할당량이 낮다는 이유만으로 조용히 계정을 바꾸지 않습니다.

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

CodexHub는 사용 한도를 늘리거나, 제한을 우회하거나, 자격 증명을 공유하지 않습니다. OpenAI 또는 조직/학교의 사용 한도, 정책, 접근 제한을 우회하기 위한 용도로 사용하면 안 됩니다. 사용자는 OpenAI 약관과 적용되는 워크스페이스, 조직, 학교 정책을 준수할 책임이 있습니다.

사용량 및 할당량 표시는 참고용입니다. 가능한 경우 CodexHub는 활성 계정과 저장된 비활성 계정에 대해 계정별 fallback cache를 포함한 최선의 할당량 상태를 표시할 수 있습니다.

CodexHub는 `CODEX_HOME`이 설정되어 있으면 해당 경로를, 없으면 `~/.codex`를 Codex 홈으로 사용해 Codex 인증 snapshot을 로컬에 저장합니다. `auth.json`, `accounts/registry.json`, `accounts/*.auth.json` 파일은 비밀번호처럼 다루세요. CodexHub는 원격 서비스를 실행하지 않으며, 계정 정보를 CodexHub가 관리하는 서버로 동기화하지 않습니다.

이 저장소에는 자격 증명, 토큰, 계정 레지스트리가 포함되어 있지 않습니다.

계정 전환은 이 Mac에 로컬로 저장된 Codex 인증 snapshot을 사용합니다. 전환은 앱 UI에서 사용자가 확인한 뒤 수행되고, 쓰기 후 검증하며, 검증 실패 시 rollback됩니다.

CodexHub는 외부 `codex-auth` 실행 파일을 필요로 하지 않고 호출하지도 않습니다. 다만 기존 저장 계정이 있는 사용자를 위해 `codex-auth` 로컬 저장소 형식과 호환됩니다.

## 보안 Roadmap

- 기본 credential 저장소를 macOS Keychain으로 이전합니다. codex-auth 호환 파일은 import/export 또는 단기 compatibility cache 용도로만 제한합니다.
