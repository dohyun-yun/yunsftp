# Improvement Plan

Status board for the hardening pass. One commit per item. Legend: `[ ]` todo, `[x]` done, `[-]` deferred (reason noted).

## P0 Security

- [x] 1. Host key verification: drop `StrictHostKeyChecking=no` / `UserKnownHostsFile=/dev/null`, use `accept-new` + default known_hosts; friendly "host key changed" error. Reuse SSH sessions via `ControlMaster`.
- [x] 2. Remove opt-in weak algorithms (SHA-1 DH, `+ssh-rsa`); rely on OpenSSH defaults.
- [x] 3. Stop fallback chains on authentication failure (avoid 3x failed logins per operation).
- [x] 4. Escape connection fields before building the Terminal AppleScript (`openSSHTerminal`).
- [x] 5. Confirm before remote delete; remove the `rm -rf` shell fallback.
- [x] 6. Create the askpass helper atomically with `0700` permissions.
- [x] 7. `zip` argument hardening (`--`), fix move-into-self prefix check.

## P1 Public repository hygiene

- [x] 8. Remove ad-hoc `scripts/test_*.swift` (hardcoded personal hosts); remove environment-specific heuristics from migration.
- [x] 9. Remove ForkLift leftovers: duplicate icns/entitlements, legacy keychain/UserDefaults namespaces, queue labels, install.sh legacy removal.
- [x] 10. Unify user-facing strings to English.
- [x] 11. README/User Guide accuracy: platform/Swift versions, test badge, Gatekeeper first-run note, SSH agent note, neutral comparison tone; version read from Info.plist in release script.
- [x] 12. CI (build + test), SECURITY.md, CONTRIBUTING.md, CHANGELOG.md, issue templates, repo topics.

## P2 Features / UX

- [x] 13. Hide unimplemented protocols (FTP/SMB/WebDAV); remove no-op "New Window" command.
- [x] 14. Transfer cancel terminates the running process.
- [x] 15. Consistent "keep both" conflict handling for SFTP upload/download (match local copy behaviour).
- [x] 16. Migration must not overwrite current settings on manual import; `ls` date parsing year rollover.
- [-] 17. Real transfer progress for upload (needs sftp progress parsing or a native SFTP library).
- [-] 18. Settings/Preferences window for `AppSettings` fields.
- [-] 19. Passphrase-protected key support in-app (documented as ssh-agent requirement in item 11).
- [-] 20. Host key fingerprint confirmation UI (item 1 uses trust-on-first-use via `accept-new`).
- [x] 21. Per-connection "Allow legacy SSH algorithms" toggle (off by default) with an actionable error when negotiation fails.
- [x] 22. Purge leaked personal host/port from git history (filter-repo, force-pushed main, branch and tag).

---

# Phase 2: Adoption, UX and polish

Legend as above. Order = execution order.

## A. Release, settings, onboarding

- [x] 23. Release workflow: on `v*` tag build the app, create dmg/zip/checksums and attach to the GitHub Release (signing/notarization steps run only when secrets exist).
- [x] 24. Fix Swift 6 strict-concurrency warnings (ConnectionTestService captured var).
- [x] 25. Settings window: font size, relative dates, visible columns, delete confirmation, terminal app, default legacy-algorithms flag.
- [x] 26. Import hosts from `~/.ssh/config` (and Cyberduck bookmarks if present) with a first-run empty state that offers it.
- [x] 27. List polish: relative dates by default, Perms hidden by default, `Kind` without "Remote" prefix, checkmark only for multi-selection, columns auto-hide in narrow panes.
- [x] 28. Filter field hidden until `Cmd+F`; `Cmd+Shift+G` go-to-path; pane header shows one connection chip (no duplicate breadcrumb root).
- [x] 29. Toolbar: six primary actions + overflow menu, user-customizable, accessibility labels on every icon-only control.
- [x] 30. Sidebar: status dot instead of "ONLINE" pill, hover-only edit button, no truncation at default width.
- [x] 31. Typography and color: system text styles instead of 9–11pt hardcoded sizes; semantic colors; light-mode pass.
- [x] 32. Empty states: first launch, empty folder, connection failure each with a next action.

## B. Transfers and file operations

- [x] 33. Conflict dialog: Replace / Skip / Keep both / Apply to all for local and SFTP transfers.
- [x] 34. Transfer window: queue list, per-item cancel, retry failed, history; batch-scoped cancel tokens replace the global cancel.
- [x] 35. Shared transfer coordinator replacing the nine near-identical copy/move/drop/paste loops.
- [x] 36. Edit remote file in external editor with auto-upload on save (FSEvents watch).
- [x] 37. Undo for local rename / move / trash.
- [x] 38. Remote path bookmarks and recent locations per connection.
- [x] 39. Folder size on demand in Get Info; remote recursive search.
- [x] 40. Update check against GitHub Releases (menu item + startup once a day, opt-out).

## C. Bigger features

- [x] 41. Tabs per pane (`Cmd+T`, `Cmd+W`, `Cmd+Shift+]`).
- [x] 42. Drag remote files out to Finder via file promises.
- [x] 43. Localization: English + Korean String Catalog; `README.ko.md`.
- [x] 44. README restructure: hero, install in 30 seconds, feature grid, trust section, FAQ, roadmap, badges; refreshed light/dark screenshots.
- [x] 45. Native SFTP engine (Citadel / swift-nio-ssh) with automatic OpenSSH fallback and an engine setting; tested end-to-end against a user-space sshd.
- [-] 46. SwiftUI `Table` prototype for the file list — only after 27/28 land; needs a spike to confirm selection behaviour parity.
- [-] 47. Developer ID signing + notarization — owner decided not to pursue for now (workflow supports it if secrets are ever added).
- [x] 48. Homebrew tap `dohyun-yun/homebrew-yunsftp` with the `yunsftp` cask; release workflow bumps it when `TAP_GITHUB_TOKEN` is set.
- [x] 49. Stage downloads/uploads through the app's temp folder so the `sftp` child never has to touch TCC-protected folders (Downloads, Desktop, Documents) directly.
