# yunsftp User Guide & Documentation

Welcome to the comprehensive user manual for **yunsftp** — the lightweight, ad-free, high-performance dual-pane SFTP client and file manager built natively for Apple Silicon macOS.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
   - [System Requirements](#system-requirements)
   - [Installation](#installation)
   - [Granting Full Disk Access](#granting-full-disk-access)
2. [Interface Overview](#2-interface-overview)
   - [Dual-Pane Layout](#dual-pane-layout)
   - [Sidebar Navigation](#sidebar-navigation)
   - [Toolbar & Status Banners](#toolbar--status-banners)
3. [Managing Remote Connections](#3-managing-remote-connections)
   - [Adding an SFTP / SSH Connection](#adding-an-sftp--ssh-connection)
   - [Authentication Methods (Password & Key)](#authentication-methods)
   - [Testing Connections & Diagnosing Latency](#testing-connections)
   - [macOS Keychain Integration](#macos-keychain-integration)
   - [Terminal SSH Integration](#terminal-ssh-integration)
4. [File Navigation & Browsing](#4-file-navigation--browsing)
   - [Keyboard Navigation & Finder Parity](#keyboard-navigation--finder-parity)
   - [Breadcrumbs & Path Navigation](#breadcrumbs--path-navigation)
   - [List & Icon Views](#list--icon-views)
   - [Sorting & Column Resizing](#sorting--column-resizing)
   - [Quick Filter & Type-to-Jump](#quick-filter--type-to-jump)
5. [File Transfers & Operations](#5-file-transfers--operations)
   - [Cross-Pane Copying (`F5`)](#cross-pane-copying-f5)
   - [Cross-Pane Moving (`F6`)](#cross-pane-moving-f6)
   - [Drag & Drop (Between Panes & Finder)](#drag--drop)
   - [Live Progress & Speed Metrics](#live-progress--speed-metrics)
   - [Creating Folders & In-Place Rename](#creating-folders--in-place-rename)
   - [Safe Deletion (Trash & Remote Removal)](#safe-deletion)
6. [Keyboard Shortcuts Reference](#6-keyboard-shortcuts-reference)
   - [Disjoint Selection with `Space`](#disjoint-selection-with-space)
   - [Dynamic Range Selection with `Shift + Arrow`](#dynamic-range-selection-with-shift--arrow)
7. [Advanced Tools](#7-advanced-tools)
   - [Batch Multi-File Rename](#batch-multi-file-rename)
   - [Directory Compare & Sync](#directory-compare--sync)
   - [POSIX Permissions Editor (`chmod`)](#posix-permissions-editor-chmod)
   - [Zip Compression & Extraction](#zip-compression--extraction)
8. [Troubleshooting & FAQ](#8-troubleshooting--faq)
   - [Korean & Unicode Filename Handling (NFC / NFD)](#korean--unicode-filename-handling)
   - [C-style Octal/Hex Escape Decoding](#c-style-octalhex-escape-decoding)
   - [Custom Ports & Firewall Settings](#custom-ports--firewall-settings)

---

## 1. Getting Started

### System Requirements
- **Hardware**: Mac with Apple Silicon (M1, M2, M3, M4, or newer).
- **Operating System**: macOS 14.0 (Sonoma), macOS 15.0 (Sequoia), or later.
- **Architecture**: 100% Native 64-bit ARM (`arm64`). Rosetta 2 is **not** required.

### Installation

#### Method A: Pre-built Binary (Recommended)
1. Download the latest release archive (`yunsftp-v1.0.0-macos-arm64.zip`) from [GitHub Releases](https://github.com/dohyun-yun/yunsftp/releases).
2. Unzip the file.
3. Drag `yunsftp.app` to your `/Applications` folder.
4. Launch `yunsftp` from Spotlight, Launchpad, or Finder.

#### Method B: Building from Source
Ensure Xcode 15+ or the Swift 6 command-line tools are installed:
```bash
git clone https://github.com/dohyun-yun/yunsftp.git
cd yunsftp
./scripts/build_app.sh
./scripts/install.sh
open /Applications/yunsftp.app
```

### Granting Full Disk Access
Like Finder, ForkLift, or any system-wide file manager, `yunsftp` needs permission to browse files across your Mac (such as `Downloads`, `Documents`, external hard drives, and network shares).

Because `yunsftp` is signed with a persistent Designated Requirement, you only need to grant permission **once**:
1. Open **System Settings** on your Mac.
2. Navigate to **Privacy & Security** > **Full Disk Access**.
3. Toggle the switch next to **yunsftp** to **ON**.
   *(If `yunsftp` is not in the list, click the `+` button at the bottom and choose `/Applications/yunsftp.app`)*.

---

## 2. Interface Overview

```
+-----------------------------------------------------------------------------+
|  ● ● ●   [yunsftp]                       [View Modes] [Sync] [Info] [Tools]  |
+-------------------+----------------------------+----------------------------+
| Favorites         | [● SFTP Server] [var/www]  | [● Local] [Users/.../yuns] |
|  - Home           |----------------------------+----------------------------+
|  - Documents      | Name       Size  Date      | Name       Size  Date      |
|  - Downloads      | assets      --   Today     | Sources     --   Today     |
|  - Projects       | index.html 8 KB  Today     | Tests       --   Today     |
|                   | server.js 12 KB  Today     | Package.swift 1 KB Today   |
| Connections       |                            | README.md    7 KB Today    |
|  - Web Server     |                            |                            |
|  - Staging        |                            |                            |
|                   |----------------------------+----------------------------+
| Devices           | 1 of 10 items (8 KB)       | 1 of 8 items (1 KB)        |
+-------------------+----------------------------+----------------------------+
```

### Dual-Pane Layout
- **Two Side-by-Side Panes**: Left pane and Right pane can each independently show a local folder or a remote SFTP server.
- **Active Pane Indicator**: The active pane is highlighted with a blue accent border. Keyboard shortcuts apply to whichever pane is currently active.
- **Switching Focus**: Press `Tab` to quickly alternate focus between the left and right panels.

### Sidebar Navigation
- **Favorites**: One-click shortcuts to standard locations (`Home`, `Desktop`, `Documents`, `Downloads`, `Applications`) and custom added folders.
- **Connections**: Lists your configured SFTP, SSH, and FTP servers. Shows live green `ONLINE` badges when connected.
- **Devices**: Shows all mounted drives, external disks, and network shares.

### Toolbar & Status Banners
- **Transfer Status Bar**: Appears dynamically at the top when files are uploading or downloading, displaying live percentages, throughput (MB/s), and progress.
- **Breadcrumb Path Bar**: Right-aligned path hierarchy showing the deepest folder first for immediate orientation.

---

## 3. Managing Remote Connections

Press `Cmd + K` anywhere in the app to open the **Connections Manager**.

### Adding an SFTP / SSH Connection
1. Click the `+` button in the Connections Manager sheet.
2. Enter the connection parameters:
   - **Connection Name**: A friendly label (e.g., `Production Web Server`).
   - **Protocol**: `SFTP (SSH File Transfer Protocol)` or `FTP`.
   - **Server / Host**: Hostname or IP address (e.g., `sftp.example.com` or `192.168.1.100`).
   - **Port**: Port number (e.g., `22` or custom ports like `13622`). Port formatting is strictly numeric without confusing commas.
   - **Username**: Your remote SSH login account.
   - **Initial Path**: Target directory on connection (e.g., `/var/www/html`).

### Authentication Methods
- **Password Authentication**: Enter your password. Check *"Remember in Keychain"* to store it securely in the macOS System Keychain.
- **SSH Private Key Authentication**: Select your key file (e.g., `~/.ssh/id_ed25519` or `~/.ssh/id_rsa`). Passphrase-protected keys are supported.

### Testing Connections
Click the **Test Connection** button inside the editor:
- Performs asynchronous DNS resolution and socket handshake on the target port.
- Verifies OpenSSH server banner and measures round-trip latency in milliseconds (e.g., `Ready! Connected (Latency: 45ms, Server: OpenSSH_8.9)`).

### macOS Keychain Integration
Passwords are never saved in plain text. `yunsftp` utilizes Apple's `Security.framework` (`kSecClassGenericPassword`, identifier `com.finsternis.yunsftp`) to isolate credentials within your encrypted macOS login keychain.

### Terminal SSH Integration
Click the **Open SSH in Terminal** button or right-click any connection in the sidebar to launch an interactive macOS Terminal session pre-authenticated with your configured key and credentials.

---

## 4. File Navigation & Browsing

### Keyboard Navigation & Finder Parity
`yunsftp` preserves macOS Finder muscle memory:
- **`Up` / `Down Arrow`**: Move cursor and select items.
- **`Enter`**: Rename the selected file or folder in-place (pre-filled with the current name).
- **`Cmd + Down` or Double-Click**: Enter folder or open file in macOS default app.
- **`Backspace` or `Cmd + Up`**: Navigate to enclosing parent directory.
- **`Home` / `End`**: Jump to the first or last item in the list.

### Breadcrumbs & Path Navigation
- Click any path component in the top breadcrumb bar to jump straight to that parent folder.
- Double-click the breadcrumb bar or press `Cmd + Shift + G` to enter a raw path manually.

### List & Icon Views
- Toggle between **List View** and **Icon Grid View** using the segmented control in each pane or the shortcut `Cmd + 1` / `Cmd + 2`.

### Sorting & Column Resizing
- Click **anywhere** on a column header (Name, Size, Date Modified, Kind) to sort ascending or descending.
- Hover between column headers to see the resize cursor (`↔`) and drag to adjust column widths. Settings are remembered across app launches.
- Horizontal scrolling features a native **rubber-band bounce snap-back**, preventing stuck whitespace at either edge.

### Quick Filter & Type-to-Jump
- Type characters while browsing to jump immediately to the matching file prefix.
- Use the search bar (`Filter...`) to dynamically filter the current view in real time.

---

## 5. File Transfers & Operations

### Cross-Pane Copying (`F5`)
1. Select one or more files in the active pane.
2. Press `F5` (or click *Copy to Other Pane*).
3. The items are asynchronously transferred into the opposite pane's current directory:
   - **Local → SFTP**: High-speed SFTP upload.
   - **SFTP → Local**: High-speed SFTP download.
   - **Local → Local**: Fast native filesystem copy.

### Cross-Pane Moving (`F6`)
Press `F6` to move files to the opposite pane. Once transfer completes successfully, the source file is safely deleted or moved to Trash.

### Drag & Drop
- **Between Panes**: Drag items directly from one pane and drop them into the other.
- **Into Subfolders**: Drag items over a specific subfolder row in the destination pane — the row highlights and items drop inside that folder.
- **Finder Integration**: Drag files from macOS Finder into any `yunsftp` pane to upload or copy instantly.

### Live Progress & Speed Metrics
During active file transfers, an animated status bar appears at the top:
- Displays filename, percentage, throughput (`MB/s`), and estimated time remaining.
- Automatically dismisses upon clean completion.

### Creating Folders & In-Place Rename
- **New Folder**: Press `Cmd + Shift + N` to create a directory in the current pane (works on both local disks and remote SFTP servers).
- **Rename**: Press `Enter` on any selected item. A spacious in-place rename sheet opens with the original filename pre-filled.

### Safe Deletion
- **Local Files**: Press `Cmd + Backspace` to move selected files to the macOS Trash.
- **Remote SFTP Files**: Press `Cmd + Backspace` or `Ctrl + Backspace` to safely delete remote files after confirmation.

---

## 6. Keyboard Shortcuts Reference

| Shortcut | Action | Description |
|:---|:---|:---|
| `Space` | **Toggle Selection** | Toggle item selection ON/OFF without losing other selections |
| `Enter` | **Rename Item** | In-place rename with current filename pre-filled |
| `Cmd + Down` / Double-Click | **Open / Enter** | Enter folder or open file in default macOS viewer |
| `Backspace` / `Cmd + Up` | **Enclosing Folder** | Go up one directory level |
| `Up` / `Down` | **Navigate** | Move cursor through file list |
| `Shift + Up / Down` | **Range Selection** | Expand range; contracts cleanly when reversing direction |
| `Tab` | **Switch Pane** | Alternate active focus between Left and Right panes |
| `Cmd + K` | **Connections** | Open Remote Connections Manager |
| `F5` | **Copy** | Copy selected items to the opposite pane |
| `F6` | **Move** | Move selected items to the opposite pane |
| `Cmd + Shift + N` | **New Folder** | Create new directory in active pane |
| `Cmd + Backspace` | **Delete / Trash** | Move local files to Trash / delete remote SFTP files |
| `Ctrl + Backspace` | **SFTP Delete** | Alternative remote file deletion |
| `Cmd + D` | **Duplicate** | Create duplicate copy in current folder |
| `Cmd + Shift + .` | **Hidden Files** | Toggle visibility of hidden files (e.g., `.gitignore`) |
| `Home` / `End` | **Jump Top / Bottom**| Jump to first or last item in current view |
| `Esc` | **Close** | Dismiss open sheets, modals, or search fields |

### Disjoint Selection with `Space`
Select multiple non-contiguous files effortlessly:
1. Navigate with the `Up` / `Down` arrow keys.
2. Press `Space` on any file you want to select (it toggles ON).
3. Move to another file and press `Space` again.
4. Press `Space` a second time on any selected file to deselect it.

### Dynamic Range Selection with `Shift + Arrow`
Hold `Shift` while pressing `Up` or `Down` to select a range of items. If you reverse direction, `yunsftp` contracts the selection naturally back to your original anchor point instead of selecting unwanted files.

---

## 7. Advanced Tools

### Batch Multi-File Rename
Select multiple files and select **Batch Rename** from the toolbar:
- Text replacement (e.g., replace `IMG_` with `Photo_`).
- Prefix and suffix additions.
- Numbered sequence generation (`001`, `002`, `003`).
- Case transformations (uppercase, lowercase, title case).
- Live preview showing before-and-after names before applying.

### Directory Compare & Sync
Click the **Compare & Sync** toolbar button to compare directory contents between the Left and Right panes:
- Highlights missing files, newer files, and size differences.
- One-click bidirectional synchronization.

### POSIX Permissions Editor (`chmod`)
Right-click any file or folder and select **Permissions (chmod)**:
- Graphical checkboxes for Read, Write, and Execute across Owner, Group, and Others.
- Live octal calculation (e.g., `755`, `644`).
- Recursive permission application for directories.

### Zip Compression & Extraction
- Select items and choose **Compress to Zip** to create an archive.
- Double-click or right-click any `.zip`, `.tar.gz`, or `.tar` file to extract.

---

## 8. Troubleshooting & FAQ

### Korean & Unicode Filename Handling
**Problem**: Korean characters display as decomposed vowels/consonants (`ㅂㅜㄷㅗㅇㅅㅏㄴ`) or remote operations fail with `No such file or directory`.  
**Solution**: macOS natively uses NFD (Normalization Form D), while Linux servers (Synology, Ubuntu) use NFC (Normalization Form C). `yunsftp` automatically normalizes all paths to NFC via `.precomposedStringWithCanonicalMapping`, ensuring seamless compatibility with any foreign server filesystem.

### C-style Octal/Hex Escape Decoding
**Problem**: Filenames from certain SFTP servers appear as raw escape sequences (e.g., `\353\266\200...`).  
**Solution**: `yunsftp` includes a real-time C-escape parsing engine that automatically detects and decodes 8-bit octal, 16-bit hex, and standard slash escapes into human-readable Unicode text.

### Custom Ports & Firewall Settings
When connecting to SFTP on a non-standard port (e.g. `13622`), `yunsftp` formats the port strictly as integer digits without localization commas (`13622` instead of `13,622`). Ensure your server firewall allows TCP traffic on your designated port.
