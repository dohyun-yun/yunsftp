# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Security
- Verify SSH host keys against `~/.ssh/known_hosts` (`accept-new`) instead of disabling checks.
- Stop enabling SHA-1 key exchange and `ssh-rsa`; use OpenSSH defaults.
- Stop retrying with alternative transports after an authentication failure.
- Shell-quote connection fields before opening Terminal (AppleScript injection).
- Require confirmation before deleting remote files; remove the shell `rm` fallback.
- Create the `SSH_ASKPASS` helper atomically with mode `0700`.

### Changed
- Reuse SSH sessions through `ControlMaster` (faster navigation, single login per server).
- User-facing strings are English only.
- Hide protocols that are not implemented (FTP/SMB/WebDAV).

### Fixed
- `zip` arguments are terminated with `--`; moving `/a/b` into `/a/bc` is no longer rejected.
- Manual ForkLift 2 import no longer overwrites current view settings.

### Removed
- Ad-hoc test scripts and leftovers from the pre-rename project.

## [1.0.0] - 2026-10-19
- Initial public release.
