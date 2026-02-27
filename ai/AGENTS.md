# Remote Read-Only SSH Policy (Strict)

## Goal
Use Codex only for read-only remote diagnostics over SSH.

## Connection Profile
- SSH command: `ssh -tt -o BatchMode=yes -o ConnectTimeout=10 user@SERVER`
- Sudo entry method (interactive): `sudo -i`
- Do not use any alternate host/user unless explicitly provided by the user in this thread.

## Default Security Posture
- Deny by default.
- Only commands explicitly allowlisted below may be executed.
- No command composition tricks: forbid `;`, `&&`, `||`, `|`, `$()`, backticks, `>`, `>>`, `<`, heredocs, backgrounding `&`.
- No remote file writes, deletes, edits, permission changes, service changes, package operations, or git push.

## Allowlisted Remote Commands
- `pwd`
- `ls`
- `find`
- `cat`
- `head`
- `tail`
- `less`
- `grep`
- `rg`
- `stat`
- `df`
- `du`
- `free`
- `ps`
- `top -b -n1`
- `ss`
- `netstat`
- `journalctl -n <N>`
- `systemctl status <unit>`
- `uname -a`
- `whoami`
- `id`
- `puppet agent -t` (in the root PATH only, sudo needed. run only if user explicitly asks.)

Anything else is forbidden unless the user explicitly updates this policy.

## Execution Protocol
For each request:
1. State intended command(s) before running.
2. Run only allowlisted command(s).
3. Return:
   - exact command executed
   - key output (trimmed if long)
   - short summary (1-3 lines)
4. If a step is not clearly allowed, stop and ask.

## Explicitly Forbidden Examples
- `rm`, `mv`, `cp`, `chmod`, `chown`
- `sed -i`, `tee` to system paths
- `apt`, `yum`, `dnf`, `brew`, installs/upgrades
- `systemctl restart/start/stop/enable/disable`
- `git push`, config edits, writing under `/etc`, `/var`, `/usr`

## Session Hygiene
- Open session only for the current task; close after completion.
- Do not persist credentials or secrets in files.
- Do not echo OTP/secrets back in the final response.

## Realtime Transparency (Mandatory)
- Before executing any remote command, print: `RUN: <exact command>`
- Use one command at a time (no batching).
- After each command, return output immediately (do not wait for a full plan/result).
- For long-running commands, post progress every 5-10s with latest visible lines.
- On SSH connect, always run and show:
  - `echo CONNECTED && hostname && whoami && date -Is`
- On prompt for secrets (pinentry/YubiKey), immediately notify user and send input back.
- After each step, print: `DONE: <command> (exit=<code>)`
