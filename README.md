<p align="center">
  <img src="Resources/forklift.icns" width="128" height="128" alt="yunsftp icon" />
</p>

<h1 align="center">yunsftp</h1>

<p align="center">
  <strong>광고 없는 깔끔함, 압도적인 반응속도의 macOS 네이티브 듀얼 패널 SFTP 클라이언트</strong><br>
  An ultra-fast, lightweight, ad-free native dual-pane SFTP & file manager for macOS Apple Silicon.
</p>

<p align="center">
  <a href="#-features"><img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue?logo=apple" alt="Platform"></a>
  <a href="#-features"><img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-orange" alt="Apple Silicon"></a>
  <a href="#-features"><img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift" alt="Swift 6"></a>
  <a href="#-tests"><img src="https://img.shields.io/badge/Tests-42%20Passed%20(100%25)-brightgreen" alt="Tests"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/No%20Ads-100%25%20Free-success" alt="100% Free">
</p>

---

<p align="center">
  <img src="docs/assets/screenshot.png" width="900" alt="yunsftp Preview Screenshot" />
</p>

## 💡 About yunsftp

**yunsftp**는 불필요한 광고, 무거운 웹 기반 프레임워크(Electron), 복잡한 구독 결제 없이 **오직 본질인 '빠르고 편한 파일 전송과 관리'에 집중한 오픈소스 macOS 듀얼 패널 SFTP/FTP 클라이언트**입니다.

기존 레거시 Intel(x86_64) 클라이언트(ForkLift 2 등)의 Rosetta 지원 중단 대비 및 시중의 무겁고 광고가 포함된 FTP 도구들을 대체하기 위해, 최신 **Swift 6 + SwiftUI & AppKit**으로 밑바닥부터 100% 네이티브 개발되었습니다.

---

## ⚡️ 비교: 왜 yunsftp 인가요?

| 기능 및 특징 | yunsftp | 레거시 ForkLift 2 | 일반 상용 SFTP 툴 | Electron 기반 FTP |
|:---|:---:|:---:|:---:|:---:|
| **광고 / 유료 구독** | **전혀 없음 (100% 무료)** | 무료 (구버전) | 비싼 월간/연간 구독 | 광고 배너 포함 |
| **아키텍처** | **Apple Silicon (arm64 네이티브)** | Intel (Rosetta 2 의존) | arm64 지원 | 무거운 크로미움 탑재 |
| **시작 속도 및 메모리** | **즉시 실행 (< 0.2초) / 경량** | 보통 | 무거움 | 느림 / 메모리 수백 MB 점유 |
| **듀얼 패널 (Dual-Pane)** | **기본 탑재 (자유 조절)** | 지원 | 일부 지원 | 단일 창 중심 |
| **Finder 단축키 일치** | **완벽 지원 (`Enter` 이름변경, `Cmd+Down` 열기 등)** | 부분 지원 | 독자 키 매핑 | 웹 브라우저 단축키 혼선 |
| **한글/특수문자 경로 호환** | **NFC/NFD 자동 변환 & C-escape 디코딩** | 깨짐 현상 발생 | 한글 분리 현상 발생 가능 | 글자 깨짐 가능 |
| **키체인(Keychain) 연동** | **Apple Security Framework 정합** | 키체인 연동 | 별도 보관함 사용 | 평문 또는 자체 파일 저장 |

---

## ✨ 핵심 기능 (Features)

### 1. 100% 광고 없는 순수 오픈소스 (Ad-Free & Clean)
- 어떠한 광고 배너, 팝업, 텔레메트리(추적 스크립트)도 없습니다.
- 로그인, 계정 등록, 라이선스 키 등록 없이 설치 즉시 무제한 사용 가능합니다.

### 2. 강력하고 직관적인 듀얼 패널 워크플로우 (Dual-Pane Productivity)
- **자유로운 패널 조절**: 좌/우 스플릿 패널 너비 실시간 조절 및 `Tab` 키로 빠른 전환.
- **크로스 패널 파일 복사 및 이동**:
  - `F5`: 다른 패널로 복사 (로컬 복사 / SFTP 다운로드 / SFTP 업로드 자동 판별)
  - `F6`: 다른 패널로 이동 (이동 후 원본 정리)
  - `Drag & Drop`: 패널 간 마우스 드래그, 또는 특정 폴더 위로 드롭 시 하위 폴더 자동 복사 지원
- **실시간 프로그레스 바**: 대용량 파일 전송 시 진행률(%), 전송 속도(MB/s), 남은 시간, 전송 상태가 시각적으로 깔끔하게 표시되며 완료 시 자동 종료.

### 3. macOS Finder 친화적 키보드 내비게이션 (Finder Parity)
- **`Enter`**: 파일 이름 변경 (기존 파일명이 기본 입력되어 즉시 수정 가능하며, 긴 파일명도 편안하게 수정할 수 있는 와이드 입력창 제공)
- **`Cmd + Down` 또는 더블클릭**: 폴더 열기 / 파일 기본 프로그램 실행
- **`Backspace` 또는 `Cmd + Up`**: 상위 폴더로 이동
- **`Space`**: 파일 다중 선택 토글 (ON/OFF) — 방향키로 이동하면서 원하는 파일들만 `Space`로 콕콕 집어 선택 가능
- **`Shift + Up / Down`**: 연속 범위 다중 선택 (방향 전환 시 선택 영역이 깔끔하게 축소되는 스마트 컨트랙션 지원)
- **`Cmd + Backspace` / `Ctrl + Backspace`**: 로컬 파일 휴지통 이동 및 SFTP 원격 파일 안전 삭제
- **`Cmd + Shift + N`**: 현재 패널에 즉시 새 폴더 생성
- **`Cmd + K`**: 원격 서버 연결 관리자 팝업 열기
- **가로 스크롤 고무줄 복귀 (Snap-Back)**: 좌우 스크롤 시 화면 밖 여백에 멈추지 않고 네이티브 바운스 효과로 원래 위치로 즉시 스냅백 복귀.
- **인터랙티브 테이블 헤더**: 컬럼 헤더의 텍스트뿐만 아니라 셀 전체 어디를 클릭해도 즉시 정렬, 컬럼 경계선 마우스 호버 시 크기 조절 커서 변경 및 드래그 폭 조절.

### 4. 강력한 SFTP 및 네트워크 안정성
- **한글 및 유니코드 완전 호환**:
  - macOS 자모 분리형(NFD)과 Linux/Synology 완성형(NFC)을 실시간 상호 보정.
  - SFTP 서버에서 `\353\266\200...` 형태로 넘어오는 C-style 8진수/16진수 이스케이프 문자열 자동 감지 및 완벽 복원.
- **포트 번호 서식 정규화**: 포트 입력 시 천 단위 쉼표(`,`)가 들어가지 않는 순수 정수 포맷 (`2222`, `22`).
- **상세 연결 상태 인디케이터**:
  - 초록색 1열 콤팩트 연결 바: 접속 서버명, 프로토콜, 간편 Disconnect 아이콘.
  - 로컬 패널 전용 디바이스 아이콘 제공으로 원격과 로컬의 명확한 시각적 대비.
  - 경로 바(Breadcrumbs)는 가장 하위(현재) 폴더가 먼저 보이도록 우측 정렬되어 긴 경로도 한눈에 파악.
- **안전한 키체인 보관**: Apple `Security.framework`를 통해 SFTP 비밀번호를 macOS 시스템 키체인에 안전하게 암호화 보관.
- **실시간 소켓 진단 (`ConnectionTestService`)**: 연결 관리 창에서 원클릭으로 TCP 포트 핸드셰이크, SSH 배너 수신, 왕복 지연시간(Latency ms) 실시간 측정.

### 5. 기존 ForkLift 2 환경 원클릭 자동 마이그레이션
- 기존에 ForkLift 2를 사용 중이었다면 저장된 즐겨찾기, 북마크, SFTP 접속 정보(`~/.ssh/id_ed25519` 키 매핑 포함), 뷰 설정을 자동으로 감지하여 그대로 불러옵니다.

---

## ⌨️ 키보드 단축키 일람 (Shortcuts)

| 단축키 | 동작 | 설명 |
|:---|:---|:---|
| `Space` | **선택 토글 (ON / OFF)** | 방향키로 이동하면서 여러 파일을 개별적으로 선택/해제 |
| `Enter` | **이름 변경 (Rename)** | 기존 파일명이 채워진 상태로 와이드 편집 창 오픈 |
| `Cmd + Down` / 더블클릭 | **열기 (Open)** | 폴더 진입 또는 파일 기본 앱 실행 |
| `Backspace` / `Cmd + Up` | **상위 폴더 (Parent)** | 상위 디렉토리로 이동 |
| `Up` / `Down` | **커서 이동** | 파일 및 폴더 목록 탐색 |
| `Shift + Up / Down` | **범위 선택 (Range)** | 연속 다중 선택 (반대 방향 시 선택 축소) |
| `Tab` | **패널 전환 (Switch Pane)** | 좌측 패널 ↔ 우측 패널 포커스 이동 |
| `Cmd + K` | **연결 관리 (Connections)** | SFTP / FTP 원격 서버 목록 및 연결 창 |
| `F5` | **다른 패널로 복사 (Copy)** | 패널 간 복사, SFTP 다운로드 및 업로드 |
| `F6` | **다른 패널로 이동 (Move)** | 패널 간 이동 (전송 후 원본 삭제) |
| `Cmd + Shift + N` | **새 폴더 (New Folder)** | 현재 디렉토리에 새 폴더 생성 |
| `Cmd + Backspace` | **삭제 (Delete)** | 휴지통 이동 (로컬) / 파일 삭제 (SFTP) |
| `Ctrl + Backspace` | **삭제 (SFTP)** | SFTP 원격 파일 삭제 지원 |
| `Cmd + D` | **복제 (Duplicate)** | 현재 파일 복제본 생성 |
| `Home` / `End` | **처음 / 끝 이동** | 목록의 맨 위 / 맨 아래로 점프 |
| `Esc` | **닫기 (Close)** | 열려 있는 팝업, 시트, 검색창 닫기 |

---

## 🚀 설치 및 실행 (Installation)

### 방법 1. 릴리즈 다운로드 (권장)
[Releases](https://github.com/dohyun-yun/yunsftp/releases) 탭에서 최신 버전의 `yunsftp.app` 또는 `.zip`을 다운로드한 후, `/Applications` 폴더로 드래그하여 설치합니다.

### 방법 2. 소스 코드에서 직접 빌드
최신 Swift 6 툴체인이 설치된 환경에서 원클릭 스크립트로 빌드할 수 있습니다:

```bash
# 1. 저장소 클론
git clone https://github.com/dohyun-yun/yunsftp.git
cd yunsftp

# 2. 릴리즈 빌드 및 /Applications 설치 스크립트 실행
./scripts/build_app.sh

# 3. yunsftp 실행
open /Applications/yunsftp.app
```

> [!NOTE]
> **전체 디스크 접근 권한 (Full Disk Access) 설정**  
> yunsftp와 같은 파일 관리 프로그램은 Mac 시스템 전역(다운로드, 외장 드라이브, 네트워크 드라이브 등)을 자유롭게 탐색하기 위해 최초 1회 전체 디스크 접근 권한이 필요합니다:
> 1. macOS **시스템 설정 (System Settings)** > **개인정보 보호 및 보안 (Privacy & Security)**
> 2. **전체 디스크 접근 권한 (Full Disk Access)** 선택
> 3. **yunsftp**를 찾아 토글 스위치를 **ON**으로 활성화

---

## 🧪 테스트 및 품질 보증 (Automated Tests)

yunsftp는 로컬 파일 시스템과 원격 SFTP 간의 동작 일관성(Parity) 및 UX 인터랙션을 검증하는 총 42개의 자동화 테스트 슈트를 갖추고 있습니다:

```bash
swift test
```

```text
Test Suite 'All tests' passed at 2026-10-18.
Executed 42 tests, with 0 failures (0 unexpected) in 0.412 seconds.
```

- **SFTP & 로컬 기능 패리티 검증**: 파일 복사, 이동, 삭제, 디렉토리 생성, 이름 변경
- **유니코드 및 이스케이프 복원**: NFC 정규화, C-escape 8진수/16진수 문자열 복원
- **UX 인터랙션 검증**: `Space` 개별 선택 토글, `Shift+Arrow` 선택 범위 축소, 포트 번호 콤마 제거 등

---

## 📄 라이선스 (License)

이 프로젝트는 [MIT License](LICENSE)에 따라 자유롭게 사용, 수정, 배포할 수 있습니다.
광고 없이 깨끗한 파일 관리 환경을 지향합니다.
