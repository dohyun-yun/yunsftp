# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Native SSH/SFTP engine (Citadel / swift-nio-ssh): persistent session per server, byte-level transfer progress, directory listings from the protocol instead of `ls` parsing, known_hosts trust-on-first-use. The OpenSSH transport remains as automatic fallback and can be pinned in Settings → Connections.

### Changed
- Minimum macOS version is now 14 (Sonoma), required by the native engine.

## [1.1.1] - 2026-10-30

### Fixed
- The 1.1.0 release build crashed at launch: the toolchain-generated resource-bundle accessor did not look in `Contents/Resources`. The app now locates its localization bundle itself and falls back to English instead of trapping. CI and the release workflow launch the packaged app once as a smoke test.

## [1.1.0] - 2026-10-30 [YANKED]

_Crashed at launch when built by CI; replaced by 1.1.1._

### Security
- Verify SSH host keys against `~/.ssh/known_hosts` (`accept-new`) instead of disabling checks.
- Stop enabling SHA-1 key exchange and `ssh-rsa`; use OpenSSH defaults.
- Stop retrying with alternative transports after an authentication failure.
- Shell-quote connection fields before opening Terminal (AppleScript injection).
- Require confirmation before deleting remote files; remove the shell `rm` fallback.
- Create the `SSH_ASKPASS` helper atomically with mode `0700`.

### Added
- Settings window (`⌘,`): relative dates, visible columns, font size, delete confirmation, terminal app, legacy algorithms default, update check.
- Import connections from `~/.ssh/config` and Cyberduck bookmarks; first-run welcome banner.
- Conflict dialog (Replace / Keep Both / Skip / Cancel, apply to all) for every transfer kind.
- Transfers window (`⌘⇧T`) with queue, history, per-row cancel and retry; cancels are scoped to their batch.
- Edit remote files in an external editor with automatic upload on save.
- Undo (`⌘Z`) for local rename, move and trash.
- Remote folder bookmarks (★ in the path bar) and recent folders per connection.
- Folder size in Get Info; recursive "Find on Server" (`⌘⇧F`).
- `⌘F` on-demand filter, `⌘⇧G` go to folder, customizable toolbar with a More menu.
- Daily update check against GitHub Releases (opt-out) and a "Check for Updates…" menu item.
- Tabs per pane (`⌘T`, `⌘W`, `⌘⇧[` / `⌘⇧]`).
- Drag remote files straight into Finder or other apps (file promises).
- Korean UI (localized strings tables); English remains the fallback.
- Light/dark documentation screenshots rendered in-process by the demo mode.
- Tag-triggered release workflow with optional Developer ID signing and notarization.
- Per-connection "Allow legacy SSH algorithms" toggle (off by default) for devices that only offer SHA-1 key exchange / `ssh-rsa`.
- CI workflow, SECURITY.md, CONTRIBUTING.md, issue and PR templates, Korean README.
- Homebrew tap (`brew install --cask dohyun-yun/yunsftp/yunsftp`); the release workflow bumps the cask automatically.

### Changed
- Reuse SSH sessions through `ControlMaster` (faster navigation, single login per server).
- User-facing strings are English only.
- Hide protocols that are not implemented (FTP/SMB/WebDAV).

### Fixed
- Downloads are staged in the app's temp folder and moved into place by the app itself, so the `sftp` child process never needs access to Downloads/Desktop/Documents; uploads retry from a staged copy when the child cannot read the source folder.
- Opening a local favourite or device while connected to a server no longer treats it as a remote path; Back returns to the server session.
- `zip` arguments are terminated with `--`; moving `/a/b` into `/a/bc` is no longer rejected.
- Manual ForkLift 2 import no longer overwrites current view settings.

### Removed
- Ad-hoc test scripts and leftovers from the pre-rename project.
- Fallback to the pre-1.0 (unreleased) Keychain and UserDefaults namespaces. Only builds that predate the public 1.0.0 release were affected.

## [1.0.0] - 2026-10-19
- Initial public release.

[Unreleased]: https://github.com/dohyun-yun/yunsftp/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/dohyun-yun/yunsftp/compare/v1.0.0...v1.1.1
[1.0.0]: https://github.com/dohyun-yun/yunsftp/releases/tag/v1.0.0
