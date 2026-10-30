# Improvement Plan

Status board for the hardening pass. One commit per item. Legend: `[ ]` todo, `[x]` done, `[-]` deferred (reason noted).

## P0 Security

- [x] 1. Host key verification: drop `StrictHostKeyChecking=no` / `UserKnownHostsFile=/dev/null`, use `accept-new` + default known_hosts; friendly "host key changed" error. Reuse SSH sessions via `ControlMaster`.
- [x] 2. Remove opt-in weak algorithms (SHA-1 DH, `+ssh-rsa`); rely on OpenSSH defaults.
- [x] 3. Stop fallback chains on authentication failure (avoid 3x failed logins per operation).
- [x] 4. Escape connection fields before building the Terminal AppleScript (`openSSHTerminal`).
- [ ] 5. Confirm before remote delete; remove the `rm -rf` shell fallback.
- [ ] 6. Create the askpass helper atomically with `0700` permissions.
- [ ] 7. `zip` argument hardening (`--`), fix move-into-self prefix check.

## P1 Public repository hygiene

- [ ] 8. Remove ad-hoc `scripts/test_*.swift` (hardcoded personal hosts); remove environment-specific heuristics from migration.
- [ ] 9. Remove ForkLift leftovers: duplicate icns/entitlements, legacy keychain/UserDefaults namespaces, queue labels, install.sh legacy removal.
- [ ] 10. Unify user-facing strings to English.
- [ ] 11. README/User Guide accuracy: platform/Swift versions, test badge, Gatekeeper first-run note, SSH agent note, neutral comparison tone; version read from Info.plist in release script.
- [ ] 12. CI (build + test), SECURITY.md, CONTRIBUTING.md, CHANGELOG.md, issue templates, repo topics.

## P2 Features / UX

- [ ] 13. Hide unimplemented protocols (FTP/SMB/WebDAV); remove no-op "New Window" command.
- [ ] 14. Transfer cancel terminates the running process.
- [ ] 15. Consistent "keep both" conflict handling for SFTP upload/download (match local copy behaviour).
- [ ] 16. Migration must not overwrite current settings on manual import; `ls` date parsing year rollover.
- [-] 17. Real transfer progress for upload (needs sftp progress parsing or a native SFTP library).
- [-] 18. Settings/Preferences window for `AppSettings` fields.
- [-] 19. Passphrase-protected key support in-app (documented as ssh-agent requirement in item 11).
- [-] 20. Host key fingerprint confirmation UI (item 1 uses trust-on-first-use via `accept-new`).
