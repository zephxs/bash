#!/usr/bin/env bash
# /usr/local/bin/ai-shell-wrapper
# Version 2026-02 - AI bastion logging + moderate restrictions
# License: free to use; please keep logs intact.

# sshd_config
# Match User aixxx
#   ForceCommand /usr/local/bin/ai-shell-wrapper
#   PermitTTY yes
#   X11Forwarding no
#   AllowTcpForwarding yes
#   PermitTunnel yes

set -euo pipefail
IFS=$'\n\t'

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION - ADJUST TO YOUR RISK PROFILE / REQUIREMENTS
# ──────────────────────────────────────────────────────────────────────────────

readonly LOG_BASE="/var/log/ai-sessions"
readonly MAX_SESSION_DURATION=1800          # 30-minute max per session
readonly MAX_COMMANDS_PER_MIN=120           # basic burst protection

# Explicitly forbidden commands (including via /bin/sh -c, exec, etc.)
readonly BLACKLIST_PATTERNS=(
    '^rm[[:space:]]+-rf[[:space:]]+/*'
    '^dd[[:space:]]+if='
    '^mkfs'
    '^chmod[[:space:]]+777'
    '^chown[[:space:]]+root'
    '^sudo'
    '^su'
    '^passwd'
    '^reboot'
    '^poweroff'
    '^halt'
    '^systemctl.*(start|stop|restart).*'
    '^curl.*http'
    '^wget'
    '^nc[[:space:]]+-e'          # classic reverse shell pattern
    '^bash[[:space:]]+-i'
    '^python[[:space:]]+-c.*(socket|os.system)'
)

# Optional whitelist (if enabled, everything else is denied)
# readonly ALLOWED_COMMANDS_ONLY=true
readonly ALLOWED_COMMANDS_ONLY=false

# Allowed commands when ALLOWED_COMMANDS_ONLY=true
readonly WHITELIST=(
    "uptime" "hostname" "whoami" "id" "pwd" "ls" "cat" "tail" "head" "grep"
    "find" "df" "du" "free" "top" "ps" "netstat" "ss" "ip" "ifconfig"
    "dmesg" "journalctl" "systemctl status"   # read-only
    # Add safe commands your Codex agent should be allowed to run here
)

# ──────────────────────────────────────────────────────────────────────────────
# DO NOT EDIT BELOW UNLESS YOU KNOW WHAT YOU ARE DOING
# ──────────────────────────────────────────────────────────────────────────────

readonly SESSION_USER="$(whoami)"
readonly SESSION_IP="${SSH_CLIENT%% *}"
readonly SESSION_TS="$(date --iso-8601=seconds)"
readonly SESSION_ID="${BASHPID}-${SESSION_IP//./-}"

readonly LOG_DIR="${LOG_BASE}/$(date +%Y-%m)"
readonly TS_FILE="${LOG_DIR}/session-${SESSION_ID}.timing"
readonly LOG_FILE="${LOG_DIR}/session-${SESSION_ID}.typescript"
readonly AUDIT_FILE="${LOG_DIR}/index-${SESSION_TS:0:10}.log"
function trim_cmd() {
    local raw="$1"
    raw="${raw//$'\r'/}"
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"
    printf '%s' "${raw}"
}

mkdir -p "${LOG_DIR}" || { echo "ERROR: unable to create ${LOG_DIR}" >&2; exit 1; }
chmod 750 "${LOG_DIR}"
#chown root: "${LOG_DIR}"  # set group ownership for log readers as needed

# Short banner + session metadata (helps human audit)
{
    echo "═══════════════════════════════════════════════════════════════"
    echo "AI session started at ${SESSION_TS}"
    echo "User        : ${SESSION_USER}"
    echo "Source IP   : ${SESSION_IP}"
    echo "PID         : ${BASHPID}"
    echo "═══════════════════════════════════════════════════════════════"
} >> "${LOG_FILE}"

# Logging index global
echo "${SESSION_TS} | ${SESSION_USER} | ${SESSION_IP} | session- ${SESSION_ID}" >> "${AUDIT_FILE}"

# Command filtering function
function is_command_forbidden() {
    local cmd
    cmd="$(trim_cmd "$1")"

    # Blacklist pattern matching
    for pat in "${BLACKLIST_PATTERNS[@]}"; do
        if [[ ${cmd} =~ ${pat} ]]; then
            echo "COMMAND REJECTED: matched blacklist '${pat}'" >&2
            echo "BLOCKED: ${cmd}" >> "${LOG_FILE}"
            return 0  # forbidden → true
        fi
    done

    if ${ALLOWED_COMMANDS_ONLY:-false}; then
        for allowed in "${WHITELIST[@]}"; do
            if [[ "${cmd}" == "${allowed}" || "${cmd}" =~ ^${allowed}[[:space:]] ]]; then
                return 1  # allowed
            fi
        done
        echo "COMMAND REJECTED: not in whitelist" >&2
        echo "BLOCKED (whitelist): ${cmd}" >> "${LOG_FILE}"
        return 0
    fi

    return 1  # default: allow when not blacklisted
}

function run_interactive_shell() {
    local cmd_raw cmd now window_start window_count cmd_count cmd_rc
    local -a argv

    window_start="$(date +%s)"
    window_count=0
    cmd_count=0

    export PS1='[AI-BASTION \u@\h \W]\$ '
    export PATH='/usr/local/ai-safebin:/usr/bin:/bin'  # tightly scoped PATH

    while true; do
        # Read one line (without readline -e, more reliable under script(1))
        read -r -p '$ ' cmd_raw || break
        cmd="$(trim_cmd "${cmd_raw}")"

        [[ -z "${cmd}" ]] && continue

        # Log raw command BEFORE execution
        echo "[$(date +%H:%M:%S)] ${cmd}" >> "${LOG_FILE}"

        # Explicit shell exit handling (before any filtering)
        if [[ "${cmd}" =~ ^(exit|logout|quit)([[:space:]]+[0-9]+)?$ ]]; then
            if [[ "${cmd}" =~ [[:space:]]+([0-9]+)$ ]]; then
                return "${BASH_REMATCH[1]}"
            fi
            return 0
        fi

        # Filtering
        if is_command_forbidden "${cmd}"; then
            echo 'Command denied by security policy.' >&2
            continue
        fi

        # Execute without eval
        IFS=' ' read -r -a argv <<< "${cmd}"
        if (( ${#argv[@]} == 0 )); then
            continue
        fi

        # Deny shell syntax to block policy bypasses (no eval)
        if [[ "${cmd}" =~ [\;\&\|\<\>\`\$\(\)\\\'\"] ]]; then
            echo "COMMAND REJECTED: shell metacharacters are forbidden" >&2
            echo "BLOCKED (metachar): ${cmd}" >> "${LOG_FILE}"
            continue
        fi

        # Per-minute command rate limit
        now="$(date +%s)"
        if (( now - window_start >= 60 )); then
            window_start="${now}"
            window_count=0
        fi
        if (( window_count >= MAX_COMMANDS_PER_MIN )); then
            echo "RATE LIMIT: too many commands in the current minute" >&2
            echo "BLOCKED (rate-limit): ${cmd}" >> "${LOG_FILE}"
            continue
        fi
        (( window_count += 1 ))

        set +e
        "${argv[@]}" 2>&1 | tee -a "${LOG_FILE}"
        cmd_rc=${PIPESTATUS[0]}
        set -e
        if (( cmd_rc != 0 )); then
            echo "COMMAND EXITED: rc=${cmd_rc}" >> "${LOG_FILE}"
        fi

        # Small anti-flood delay
        (( cmd_count += 1 ))
        if (( cmd_count % 10 == 0 )); then
            sleep 0.1
        fi
    done
}

# Trap to log session end
trap '
    echo "═══════════════════════════════════════════════════════════════" >> "${LOG_FILE}"
    echo "Session ended at $(date --iso-8601=seconds)" >> "${LOG_FILE}"
    echo "═══════════════════════════════════════════════════════════════" >> "${LOG_FILE}"
' EXIT

if [[ "${1:-}" == "--inner" ]]; then
    run_interactive_shell
    exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# Main loop - interactive shell with logging
# ──────────────────────────────────────────────────────────────────────────────

echo "+------------------------------------------------------+" >&2
echo "|                  SSH AI BASTION                      |" >&2
echo "+------------------------------------------------------+" >&2
echo "Session active: all actions are logged. Use 'exit' to disconnect." >&2

# Run script(1) to capture EVERYTHING (including vim, less, etc.)
# --flush reduces log loss risk on crash
if command -v timeout >/dev/null 2>&1; then
    exec timeout --foreground "${MAX_SESSION_DURATION}" \
        script \
            --timing="${TS_FILE}" \
            --flush \
            --quiet \
            --command "bash --noprofile --norc \"${BASH_SOURCE[0]}\" --inner" \
            "${LOG_FILE}"
else
    exec script \
        --timing="${TS_FILE}" \
        --flush \
        --quiet \
        --command "bash --noprofile --norc \"${BASH_SOURCE[0]}\" --inner" \
        "${LOG_FILE}"
fi

# If execution reaches here -> unexpected termination
echo "Session terminated unexpectedly" >> "${LOG_FILE}"
exit 1
