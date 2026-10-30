<p align="center">
  <img src="Resources/app_icon.png" width="128" height="128" alt="yunsftp icon" style="border-radius: 26px;" />
</p>

<h1 align="center">yunsftp</h1>

<p align="center">
  <strong>An ultra-fast, ad-free, native dual-pane SFTP client and file manager built for Apple Silicon macOS.</strong><br>
  Designed from the ground up with Swift, SwiftUI, and AppKit for maximum speed and simplicity.
</p>

<p align="center">
  <a href="#-features"><img src="https://img.shields.io/badge/Platform-macOS%2013.0%2B-blue?logo=apple" alt="Platform"></a>
  <a href="#-features"><img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-orange" alt="Apple Silicon"></a>
  <a href="#-features"><img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift" alt="Swift 6"></a>
  <a href="https://github.com/dohyun-yun/yunsftp/actions/workflows/ci.yml"><img src="https://github.com/dohyun-yun/yunsftp/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/No%20Ads-100%25%20Free-success" alt="100% Free">
</p>

---

<p align="center">
  <img src="docs/assets/screenshot.png" width="920" alt="yunsftp Preview Screenshot" />
</p>

## 💡 Why yunsftp?

Many file transfer apps today ship as subscriptions, carry ads, or run inside heavy cross-platform runtimes. Older Intel-only tools also face obsolescence as Rosetta 2 is phased out.

**yunsftp** focuses on **fast, lightweight, clutter-free file management**. Built 100% native in **Swift + SwiftUI & AppKit**, it launches in well under a second, uses minimal memory, and gives you classic dual-pane productivity with macOS Finder keyboard parity.

---

## ⚡️ At a Glance

| | yunsftp |
|:---|:---|
| **Price / License** | Free, open source (MIT) |
| **Ads / Tracking** | None. No analytics, accounts or license checks |
| **Architecture** | Native arm64 (Apple Silicon), no Rosetta |
| **Layout** | Side-by-side dual pane with `F5` / `F6` cross-pane copy & move |
| **Keyboard** | Finder parity: `Enter`, `Cmd+Down`, `Space`, `Shift+Arrow` |
| **Unicode paths** | Automatic NFC/NFD normalization and `ls` escape decoding |
| **Credentials** | macOS Keychain via `Security.framework` |
| **Transport** | System OpenSSH (`sftp`/`ssh`/`scp`) with host key verification |

---

## ✨ Key Features

### 1. 100% Free & Open Source (No Ads, No Subscriptions)
- No tracking scripts, no analytics, no account registration, and no license checks.
- Clean and distraction-free interface focused purely on high-performance file management.

### 2. True Dual-Pane Productivity
- **Adjustable Split Views**: Freely resize left and right panes or press `Tab` to switch focus instantly.
- **Cross-Pane Transfers**:
  - `F5`: One-key copy to opposite pane (Local copy, SFTP upload, or SFTP download).
  - `F6`: One-key move to opposite pane.
- **Drag & Drop**: Drag between panes, drop directly into subfolders, or drag from macOS Finder.
- **Live Transfer Metrics**: Animated top banner showing live progress percentage, transfer speed (`MB/s`), and remaining time.

### 3. Finder Keyboard Parity & Precision Selection
- **`Enter`**: In-place inline rename (original filename pre-filled with a spacious editor).
- **`Cmd + Down` or Double-Click**: Enter folder or open file in default macOS app.
- **`Backspace` or `Cmd + Up`**: Enclosing folder navigation.
- **`Space`**: Toggle selection ON/OFF — move with arrow keys and toggle multiple non-contiguous files.
- **`Shift + Up / Down`**: Continuous range selection with smart contraction when reversing direction.
- **`Cmd + Backspace` / `Ctrl + Backspace`**: Move local files to Trash / safely delete remote SFTP files.
- **`Cmd + Shift + N`**: Create new folder in current pane.
- **`Cmd + K`**: Open Remote Connections Manager.
- **Rubber-band Bounce Snap-Back**: Native horizontal scroll bounce that prevents stuck blank space at table margins.
- **Interactive Headers**: Click anywhere on a table header cell to sort; hover on dividers to resize columns.

### 4. Resilient SFTP & Unicode Parity
- **Full NFC / NFD Normalization**: Bridges macOS decomposed Unicode (NFD) and Linux server precomposed Unicode (NFC), preventing `"No such file or directory"` errors on foreign filenames.
- **Real-Time C-Escape Decoding**: Automatically detects and decodes 8-bit octal (`\353\266\200...`) and 16-bit hex escape sequences into clean human-readable Unicode text.
- **Clean Port Formatting**: Strict numeric port handling without localization commas (`2222` instead of `2,222`).
- **Encrypted Keychain Storage**: Stores passwords securely using Apple's `Security.framework`.
- **Host Key Verification**: Server keys are checked against `~/.ssh/known_hosts` (trust-on-first-use). A changed key aborts the connection with instructions.
- **SSH Keys & Agent**: Unencrypted keys work directly. Passphrase-protected keys must be loaded into `ssh-agent` first (`ssh-add --apple-use-keychain ~/.ssh/id_ed25519`).
- **Live Socket Diagnostics (`ConnectionTestService`)**: One-click TCP socket handshake, SSH banner inspection, and millisecond latency test.

### 5. Automatic Migration from ForkLift 2
- Automatically detects and migrates existing bookmarks, SSH keys (`~/.ssh/id_ed25519`), custom ports, and favorite locations from `com.binarynights.ForkLift2.plist`.

---

## ⌨️ Keyboard Shortcuts Reference

| Shortcut | Action | Description |
|:---|:---|:---|
| `Space` | **Toggle Selection** | Select / deselect individual files while browsing |
| `Enter` | **Rename** | In-place rename with current filename pre-filled |
| `Cmd + Down` / Double-Click | **Open / Enter** | Enter folder or open file in default viewer |
| `Backspace` / `Cmd + Up` | **Parent Folder** | Navigate up one directory level |
| `Up` / `Down` | **Cursor Move** | Browse file and folder list |
| `Shift + Up / Down` | **Range Selection** | Multi-item selection with natural contraction |
| `Tab` | **Switch Pane** | Toggle active focus between Left and Right panes |
| `Cmd + K` | **Connections** | Open Remote Connections Manager |
| `F5` | **Copy** | Copy selected items to opposite pane (Upload/Download) |
| `F6` | **Move** | Move selected items to opposite pane |
| `Cmd + Shift + N` | **New Folder** | Create new folder in active directory |
| `Cmd + Backspace` | **Delete** | Move local items to Trash / delete remote files |
| `Ctrl + Backspace` | **SFTP Delete** | Alternative remote file removal |
| `Cmd + D` | **Duplicate** | Create duplicate copy of selected item |
| `Cmd + Shift + .` | **Hidden Files** | Toggle visibility of hidden dotfiles |
| `Home` / `End` | **Jump Top / Bottom** | Jump to first or last item in current pane |
| `Esc` | **Close** | Dismiss sheets, search bars, or previews |

> 📖 For detailed instructions and workflows, see the complete [User Guide](docs/USER_GUIDE.md).

---

## 🚀 Installation

### Option 1: Download Pre-built Release (Recommended)
Download the latest `.dmg` installer or `.zip` archive from the [Releases](https://github.com/dohyun-yun/yunsftp/releases) page.
- **DMG**: Double-click `yunsftp-<version>-macos-arm64.dmg` and drag `yunsftp.app` to your `/Applications` folder.
- **ZIP**: Unzip `yunsftp-<version>-macos-arm64.zip` and move `yunsftp.app` to `/Applications`.

> [!IMPORTANT]
> **First launch (Gatekeeper)**  
> Releases are ad-hoc signed and not notarized, so macOS blocks the first launch. Either right-click `yunsftp.app` → **Open** → **Open**, or run:
> ```bash
> xattr -d com.apple.quarantine /Applications/yunsftp.app
> ```
> Verify the download against `checksums.txt` on the release page before doing so.

### Option 2: Build from Source
Ensure Xcode 16 or later (Swift 6 toolchain) command-line tools are installed:

```bash
# 1. Clone the repository
git clone https://github.com/dohyun-yun/yunsftp.git
cd yunsftp

# 2. Build release binary and install to /Applications
./scripts/build_app.sh
./scripts/install.sh

# 3. Launch yunsftp
open /Applications/yunsftp.app
```

> [!NOTE]
> **Full Disk Access Setup**  
> To browse system directories, external drives, and network shares without repeated permission prompts, grant Full Disk Access once:
> 1. Open macOS **System Settings** > **Privacy & Security**
> 2. Select **Full Disk Access**
> 3. Toggle **yunsftp** to **ON** *(or add `/Applications/yunsftp.app`)*

---

## 🧪 Automated Testing

Unit and integration tests cover SFTP parity (against the local `sftp-server`), Unicode normalization, security hardening and UI interactions. They run on every push via GitHub Actions:

```bash
swift test
```

- **Parity Verification**: File copy, move, delete, directory creation, and in-place rename across local and SFTP environments.
- **Escape & Unicode Engines**: NFC normalization, octal (`\353...`) and hex string restoration.
- **UX & Interaction Integrity**: `Space` selection toggling, `Shift+Arrow` contraction, and comma-free port inputs.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
Enjoy a clean, fast, and ad-free file management experience on macOS!
