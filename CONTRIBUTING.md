# Contributing

Thanks for your interest in yunsftp.

## Development

```bash
git clone https://github.com/dohyun-yun/yunsftp.git
cd yunsftp
swift build
swift test          # integration tests use the local /usr/libexec/sftp-server
./scripts/build_app.sh && ./scripts/install.sh
```

Requirements: Apple Silicon Mac, macOS 14+ at runtime, Xcode 16+ (Swift 6 toolchain) to build.

## Pull requests

- Branch from `main`; one topic per PR.
- Commit messages: `<type>: <subject>` (`feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `ci`), English, imperative, no trailing period.
- Add or update tests for behaviour changes. CI must pass.
- User-facing strings are English. Do not add hardcoded hosts, ports or paths from your own environment.
- Security-sensitive changes (anything under `Services/SFTPService.swift`, `KeychainService.swift`, `TerminalService.swift`) need a short rationale in the PR description.

## Reporting bugs

Use the issue templates. For security issues see [SECURITY.md](SECURITY.md).
