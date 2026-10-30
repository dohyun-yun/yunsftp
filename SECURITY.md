# Security Policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's private
vulnerability reporting on this repository ("Security" tab → "Report a vulnerability").
You should receive an acknowledgement within 7 days.

## Scope and design notes

yunsftp uses a native SSH/SFTP engine (Citadel on swift-nio-ssh, Apache-2.0) and falls back to
the system OpenSSH binaries (`/usr/bin/ssh`, `sftp`, `scp`) for servers or keys the engine
cannot handle. Both paths verify host keys against `~/.ssh/known_hosts`.

- Host keys are verified against `~/.ssh/known_hosts` with `StrictHostKeyChecking=accept-new`
  (trust on first use). A changed host key aborts the connection.
- Passwords are stored in the macOS Keychain and handed to OpenSSH through a one-shot
  `SSH_ASKPASS` helper created with mode `0700` in the per-user temporary directory and
  deleted after the process exits.
- Cryptographic algorithms are left at the OpenSSH defaults. A per-connection "Allow legacy SSH
  algorithms" toggle (off by default) re-enables SHA-1 key exchange and `ssh-rsa` for devices
  that cannot be updated.
- Remote deletion runs inside the SFTP subsystem only; the app never executes `rm` on the server.

## Supported versions

Only the latest release receives security fixes.
