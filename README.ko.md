<p align="center">
  <img src="Resources/app_icon.png" width="112" height="112" alt="yunsftp 아이콘" />
</p>

<h1 align="center">yunsftp</h1>

<p align="center">
  <strong>Apple Silicon Mac을 위한 빠르고 가벼운 네이티브 듀얼 패널 SFTP 클라이언트 겸 파일 관리자.</strong><br>
  무료 오픈소스. 광고도, 계정도, 사용 데이터 수집도 없습니다.
</p>

<p align="center">
  <a href="https://github.com/dohyun-yun/yunsftp/releases/latest"><img src="https://img.shields.io/github/v/release/dohyun-yun/yunsftp?label=Download&color=blue" alt="최신 릴리스"></a>
  <a href="https://github.com/dohyun-yun/yunsftp/actions/workflows/ci.yml"><img src="https://github.com/dohyun-yun/yunsftp/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/dohyun-yun/yunsftp/releases"><img src="https://img.shields.io/github/downloads/dohyun-yun/yunsftp/total?color=success" alt="다운로드 수"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT 라이선스"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · 한국어
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshot-dark.png">
    <img src="docs/assets/screenshot-light.png" width="920" alt="yunsftp: 왼쪽은 SFTP 서버, 오른쪽은 로컬 폴더">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/dohyun-yun/yunsftp/releases/latest"><strong>macOS용 다운로드</strong></a> · macOS 13 이상 · Apple Silicon
</p>

## 왜 yunsftp인가

- **두 패널, 키 하나.** 한쪽은 내 Mac, 다른 쪽은 서버. `F5`로 복사, `F6`으로 이동하고, 드래그 앤 드롭은 양방향·하위 폴더까지 됩니다.
- **Finder와 같은 손맛.** `Return` 이름 변경, `⌘↓` 열기, `Space` 선택 토글, `⌘⇧G` 폴더로 이동, `⌘Z` 되돌리기까지 같은 키가 같은 일을 합니다.
- **한글 파일명이 깨지지 않습니다.** macOS(NFD)와 리눅스 서버(NFC) 사이의 유니코드 정규화를 자동 처리하고, 이름이 겹치면 덮어쓰기 전에 묻고, 서버 파일 삭제도 먼저 확인합니다.
- **설정할 것도, 어딘가로 보내는 것도 없습니다.** 비밀번호는 macOS 키체인에, 서버 키는 `~/.ssh/known_hosts`로 검증합니다. 앱이 스스로 하는 네트워크 요청은 하루 한 번의 GitHub 릴리스 확인(끌 수 있음)뿐입니다.

## 30초 설치

**Homebrew**

```bash
brew tap dohyun-yun/yunsftp
brew trust dohyun-yun/yunsftp          # 최신 Homebrew는 서드파티 tap을 처음 쓸 때 한 번 확인합니다
brew install --cask yunsftp
```

설치 후 아래 첫 실행 단계를 한 번 거치세요(Homebrew 7에는 `--no-quarantine` 옵션이 없습니다). 이후 업데이트는 `brew upgrade --cask yunsftp`로 합니다.

**직접 다운로드**

1. [최신 릴리스](https://github.com/dohyun-yun/yunsftp/releases/latest)에서 `.dmg`를 받아 `yunsftp.app`을 `/Applications`로 드래그합니다.
2. **첫 실행:** 릴리스는 ad-hoc 서명만 되어 있어(공증 없음) macOS가 첫 실행을 막습니다. `yunsftp.app`을 우클릭 → **열기** → **열기**를 한 번 하거나 아래 명령을 실행하세요.
   ```bash
   xattr -d com.apple.quarantine /Applications/yunsftp.app
   ```
   불안하다면 릴리스 페이지의 `checksums.txt`와 다운로드 파일을 비교해 보세요.
3. **선택:** 외장 드라이브와 보호된 폴더를 매번 허용 없이 열려면 시스템 설정 → 개인정보 보호 및 보안에서 **전체 디스크 접근 권한**을 한 번 켜 주세요.

직접 빌드하려면 [소스에서 빌드](#소스에서-빌드)를 보세요.

## 첫 서버 연결

1. **⌘K**(또는 툴바의 **Connect**)를 눌러 호스트, 사용자, 비밀번호나 키를 입력합니다. 비밀번호는 키체인에 저장할 수 있습니다.
2. `~/.ssh/config`에 서버가 이미 있다면 첫 실행 배너나 연결 관리자의 **Import…**로 한 번에 가져옵니다. Cyberduck, ForkLift 2 북마크도 됩니다.
3. 사이드바에서 연결을 클릭하세요. 자주 가는 폴더는 경로 막대의 ★로 북마크하고, 최근 폴더는 연결의 우클릭 메뉴에 있습니다.

## 할 수 있는 것

| | |
|:--|:--|
| **🗂 듀얼 패널 전송**<br>로컬↔로컬, 로컬↔서버, 서버↔서버 어디로든 복사·이동. 이름이 겹치면 둘 다 유지 / 바꾸기 / 건너뛰기, "모두 적용" 지원. | **📋 전송 창** (`⌘⇧T`)<br>대기열, 진짜로 멈추는 개별 취소, 실패 항목 재시도, 이력. |
| **✏️ 서버 파일을 내 편집기로**<br>원격 파일을 평소 쓰는 편집기로 열면 저장할 때마다 자동 업로드됩니다. | **🔎 서버에서 찾기** (`⌘⇧F`)<br>현재 원격 폴더 아래를 재귀 검색하고 더블클릭으로 바로 이동. |
| **⌨️ Finder 키보드 호환**<br>`Return`, `⌘↓`, `Space`, `⇧↑/↓` 범위 선택, `⌘⇧N`, `⌘⌫`, `⌘F` 필터, `⌘⇧G` 폴더로 이동, `⌘Z` 되돌리기. | **🧰 파일 도구**<br>훑어보기, 폴더 크기를 포함한 정보 보기, chmod, 일괄 이름 변경, 비교·동기화, zip 압축/해제, 터미널·iTerm에서 열기. |
| **🌏 유니코드 제대로**<br>NFC/NFD 정규화와 `ls` 이스케이프 복원으로 `한글 파일.txt`는 어디서나 `한글 파일.txt`입니다. UI는 한국어와 영어를 지원합니다. | **⚙️ 설정** (`⌘,`)<br>상대 날짜, 표시할 열, 글자 크기, 삭제 확인, 터미널 앱, 업데이트 확인. 툴바는 사용자화할 수 있습니다. |
| **🗂 탭** (`⌘T`)<br>패널마다 여러 폴더나 서버를 탭으로. `⌘⇧[` / `⌘⇧]`로 전환, `⌘W`로 닫기. | **📤 Finder로 드래그**<br>원격 파일을 데스크톱, Mail 등 어느 앱에나 끌어다 놓으면 그 자리에서 다운로드됩니다. |

## 보안과 개인정보

- 전송은 시스템 OpenSSH(`sftp`, `ssh`, `scp`)로 수행합니다. 세션을 재사용하므로 한 번 로그인으로 여러 작업을 처리합니다.
- 서버 키는 `~/.ssh/known_hosts`로 검증합니다(최초 접속 시 신뢰). 키가 바뀌면 연결을 중단하고 이유를 알려 줍니다.
- 알고리즘은 OpenSSH 기본값입니다. 오래된 장비를 위한 **레거시 SSH 알고리즘 허용** 스위치는 연결별로 있고 기본은 꺼져 있습니다.
- 비밀번호는 macOS 키체인에 저장되며, `0700` 권한으로 만든 일회용 헬퍼를 통해 OpenSSH에 전달됩니다.
- 서버 파일 삭제는 확인 후 SFTP 안에서만 수행합니다. 서버에서 `rm`을 실행하지 않습니다.
- 암호가 걸린 SSH 키는 먼저 `ssh-agent`에 올려 주세요: `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`
- 보안 문제를 발견하셨나요? [SECURITY.md](SECURITY.md)를 참고하세요.

<details>
<summary><strong>키보드 단축키</strong></summary>

| 단축키 | 동작 |
|:--|:--|
| `Tab` | 활성 패널 전환 |
| `Return` | 이름 변경 |
| `⌘↓` / 더블클릭 | 폴더 열기 / 파일 열기 |
| `⌫` / `⌘↑` | 상위 폴더 |
| `Space` | 포커스된 항목 선택 토글 |
| `⇧↑` / `⇧↓` | 선택 범위 확장·축소 |
| `⌘A` | 모두 선택 |
| `F5` / `F6` | 반대 패널로 복사 / 이동 |
| `⌘C` / `⌘X` / `⌘V` | 복사 / 잘라내기 / 붙여넣기 (Finder와 호환) |
| `⌘⌫` | 휴지통으로 (로컬) / 삭제 (서버, 확인 후) |
| `⌘D` | 복제 |
| `⌘⇧N` | 새 폴더 |
| `⌘F` | 현재 폴더 필터 |
| `⌘⇧F` | 서버에서 찾기 |
| `⌘⇧G` | 폴더로 이동 |
| `⌘Y` | 훑어보기 |
| `⌘I` | 정보 보기 |
| `⌘K` | 연결 관리 |
| `⌘⇧T` | 전송 창 |
| `⌘⇧.` | 숨김 파일 표시 |
| `⌘Z` | 이름 변경·이동·휴지통 되돌리기 (로컬) |
| `Esc` | 필터 닫기, 선택 해제, 시트 닫기 |

</details>

## 자주 묻는 질문

**한글 파일명이 깨지거나 "찾을 수 없음"이 나옵니다.**  
yunsftp는 이름을 NFC로 정규화하고 `ls` 이스케이프를 복원한 뒤 사용하므로 원칙적으로 생기지 않는 문제입니다. 발생하면 서버 종류와 예시 이름을 적어 이슈로 알려 주세요.

**Synology에서 `/volume1`이 아니라 `/`만 보입니다.**  
DSM의 SFTP는 활성화한 공유 폴더로 chroot됩니다. 서버가 보여 주는 루트를 기준으로 쓰시면 되고 북마크도 거기서부터 동작합니다.

**"no matching key exchange method"로 연결이 실패합니다.**  
장비가 SHA-1 알고리즘만 제공하는 경우입니다. 해당 연결을 편집해 **레거시 SSH 알고리즘 허용**을 그 서버에만 켜 주세요.

**앱이 어딘가로 데이터를 보내나요?**  
내 서버로만 보냅니다. 선택 사항인 업데이트 확인은 하루 한 번 `api.github.com/repos/dohyun-yun/yunsftp/releases/latest`를 조회하며 설정에서 끌 수 있습니다.

## 로드맵

진행 상황은 [docs/IMPROVEMENT_PLAN.md](docs/IMPROVEMENT_PLAN.md)에서 추적합니다. 다음 순서는 바이트 단위 진행률과 이어받기를 위한 네이티브 SFTP 엔진, SwiftUI `Table` 기반 파일 목록입니다. 공증은 당분간 계획에 없으며 Homebrew cask와 위의 첫 실행 안내로 설치를 안내합니다.

## 소스에서 빌드

요구 사항: Apple Silicon Mac, Xcode 16 이상(Swift 6 툴체인). 앱 자체는 macOS 13 이상에서 실행됩니다.

```bash
git clone https://github.com/dohyun-yun/yunsftp.git
cd yunsftp
swift test                 # 단위 + 통합 테스트 (로컬 sftp-server 사용)
./scripts/build_app.sh     # build/yunsftp.app, ad-hoc 서명
./scripts/install.sh       # /Applications로 복사
```

`scripts/package_release.sh`가 dmg/zip/checksums를 만들며, `v*` 태그를 푸시하면 CI가 같은 스크립트를 실행합니다.

## 기여

버그 리포트와 PR을 환영합니다. 먼저 [CONTRIBUTING.md](CONTRIBUTING.md)를 읽어 주세요. 요약하면 PR 하나에 주제 하나, 동작 변경에는 테스트, 코드에 개인 환경 값 금지입니다.

## 라이선스

[MIT](LICENSE)
