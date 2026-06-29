#!/bin/bash
### ssh_command parallel version
# Version 2.02

# Debug mode on
#set -x
# Debug mode off
set +x

#### Load environment ############
FILE=$(readlink -f "$0")
BASE=$(dirname "$FILE")
SSH_OPTIONS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ServerAliveInterval=43200
  -o LogLevel=ERROR
)
PARALLEL=5
SSH_PROXY_USER="root"
REMOTE_PATH=""
SCRIPT_FILE=""
SCRIPT_ARGS=""
declare -a JOB_PIDS=()
declare -a JOB_HOSTS=()
declare -a JOB_TMPFILES=()
declare -a JOB_STATUSES=()

ctrl_c(){
  local pid
  local tmpfile

  echo
  echo "Interrupt received, stopping active SSH jobs..."
  for pid in "${JOB_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${JOB_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  for tmpfile in "${JOB_TMPFILES[@]}"; do
    [ -n "$tmpfile" ] && rm -f "$tmpfile"
  done
  exit 130
}

# Logging + interrupt trap (portable: always on)
[ -d "$HOME/logs" ] || mkdir -p "$HOME/logs"
_LOG_FILE="$HOME/logs/$(basename -s '.sh' "$0").log"
trap ctrl_c INT

#### Functions ###############
_LOG(){
  local _LEVEL="$1"
  local _MESSAGE="$2"
  local _TIMESTAMP
  _TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  printf "[%s] [%s] %s\n" "$_TIMESTAMP" "$_LEVEL" "$_MESSAGE" >>"$_LOG_FILE"
}

display_help(){
  local RET="$1"
  echo "Usage:"
  echo "  $0 (-l|--list \"vm1 vm2\" | -f|--file vm-list.txt) MODE [options]"
  echo
  echo "Modes (choose exactly one):"
  echo "  -c, --cmd COMMAND           Run a remote command"
  echo "  -C, --scp FILE              Upload a local file with scp"
  echo "  -S, --script FILE           Execute a local script remotely with bash"
  echo
  echo "Target selection:"
  echo "  -l, --list HOSTS            Space-separated host list"
  echo "  -f, --file FILE             File containing the host list"
  echo "  -F, --force                 Keep hosts that do not resolve instead of failing"
  echo
  echo "Mode-specific options:"
  echo "  -r, --remotePath PATH       Remote destination path used with -C/--scp"
  echo "  -a, --scriptArgs ARGS       Arguments passed to the remote script"
  echo
  echo "Execution options:"
  echo "  -p, --parallel COUNT        Max concurrent ssh sessions (default: 5)"
  echo "  -s, --sshProxy HOST         Proxy host used as first hop"
  echo "  -u, --sshProxyUser USER     Proxy login user (default: root)"
  echo "  -N, --noask                 Skip local confirmation prompt"
  echo "  -h, --help                  Show this help"
  echo
  echo "Examples:"
  echo "  $0 -l \"vm1 vm2\" -c 'uname -a' -p 10"
  echo "  $0 -f vm-list.txt -C ./agent.rpm -r /tmp -p 5"
  echo "  $0 -l \"vm1 vm2\" -S ./diag.sh -a '--check disk --verbose' -p 5"
  exit "$RET"
}

_CHECK_HOST_RESOLVE(){
  local host="$1" resolved
  # Expand ~/.ssh/config alias to its effective HostName (no connection)
  resolved=$(ssh -G "$host" 2>/dev/null | awk '/^hostname /{print $2; exit}')
  resolved="${resolved:-$host}"
  # IP literal (IPv4) — no resolution needed
  [[ "$resolved" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && return 0
  # Local (/etc/hosts, mDNS) then DNS via nsswitch
  if command -v getent >/dev/null 2>&1; then
    getent hosts "$resolved" >/dev/null 2>&1 && return 0
  fi
  # Fallback: DNS lookup
  if command -v nslookup >/dev/null 2>&1; then
    nslookup "$resolved" >/dev/null 2>&1 && return 0
  fi
  return 1
}

_detect_ssh_identity(){
  # Agent with loaded keys
  if ssh-add -l >/dev/null 2>&1; then
    return 0
  fi
  # Default private key files
  local k
  for k in ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa ~/.ssh/id_rsa ~/.ssh/id_dsa; do
    [ -f "$k" ] && return 0
  done
  # IdentityFile declared in ~/.ssh/config
  if [ -f ~/.ssh/config ] && grep -qi '^[[:space:]]*IdentityFile' ~/.ssh/config 2>/dev/null; then
    return 0
  fi
  return 1
}

_setup_auth(){
  local _pw
  if _detect_ssh_identity; then
    _AUTH_MODE="key"
    echo "Auth: SSH key detected (agent or ~/.ssh)."
    return 0
  fi

  echo "WARNING: no SSH key loaded (no agent keys, no ~/.ssh/id_*). Password fallback." >&2
  if [ -n "${SSHPASS:-}" ]; then
    export SSHPASS
  elif [ -n "${PASS2:-}" ]; then
    export SSHPASS="$PASS2"
  elif [ -z "$NOASK" ]; then
    read -r -s -p "Enter remote password (Ctrl-C to abort): " _pw
    echo
    [ -z "$_pw" ] && { echo "Empty password, aborting." >&2; exit 1; }
    export SSHPASS="$_pw"
  else
    echo "ERROR: no SSH key and --noask set (cannot prompt). Load a key (ssh-add) or set SSHPASS." >&2
    exit 1
  fi

  if ! command -v sshpass >/dev/null 2>&1; then
    echo "ERROR: sshpass required for password auth but not installed. Use SSH keys or install sshpass." >&2
    exit 1
  fi
  _AUTH_MODE="pass"
  echo "Auth: using password (sshpass -e)."
}

append_unique_server(){
  local host="$1"
  local existing

  for existing in "${server[@]}"; do
    [ "$existing" = "$host" ] && return 0
  done
  server+=("$host")
}

require_option_value(){
  local option_name="$1"
  local option_value="$2"

  if [ -z "$option_value" ] || [[ "$option_value" =~ ^- ]]; then
    echo "ERROR: Missing value for $option_name" >&2
    exit 1
  fi
}

require_non_empty_value(){
  local option_name="$1"
  local option_value="$2"

  if [ -z "$option_value" ]; then
    echo "ERROR: Missing value for $option_name" >&2
    exit 1
  fi
}

build_proxy_command(){
  local target_host="$1"
  local remote_command="$2"
  local needs_stdin="${3:-false}"
  local proxy_command="sudo -n ssh -l root"
  local opt

  [ "$needs_stdin" = "true" ] || proxy_command="$proxy_command -n"
  for opt in "${SSH_OPTIONS[@]}"; do
    printf -v proxy_command '%s %q' "$proxy_command" "$opt"
  done
  printf -v proxy_command '%s %q %q' "$proxy_command" "$target_host" "$remote_command"
  printf '%s' "$proxy_command"
}

run_ssh_job(){
  local SSHCLIENT="$1"
  local TMPFILE="$2"
  local proxy_command

  {
    echo -e "\033[34m###################### $SSHCLIENT $(date +%H:%M) ######################\033[0m"
    if [ -n "$SSH_PROXY" ]; then
      _LOG "$SSHCLIENT via $SSH_PROXY" "$CMD"
      proxy_command=$(build_proxy_command "$SSHCLIENT" "$CMD")
      "${_AUTH_PREFIX[@]}" ssh -n "$SSH_PROXY" -l "$SSH_PROXY_USER" "${SSH_OPTIONS[@]}" "$proxy_command"
    else
      _LOG "$SSHCLIENT" "$CMD"
      "${_AUTH_PREFIX[@]}" ssh -n "$SSHCLIENT" "${SSH_OPTIONS[@]}" "$CMD"
    fi
  } >"$TMPFILE" 2>&1
}

build_script_command(){
  local remote_command="bash -s --"

  if [ -n "$SCRIPT_ARGS" ]; then
    remote_command="$remote_command $SCRIPT_ARGS"
  fi

  printf '%s' "$remote_command"
}

run_script_job(){
  local SSHCLIENT="$1"
  local TMPFILE="$2"
  local proxy_command
  local remote_command

  remote_command=$(build_script_command)

  {
    echo -e "\033[34m###################### $SSHCLIENT $(date +%H:%M) ######################\033[0m"
    if [ -n "$SSH_PROXY" ]; then
      _LOG "$SSHCLIENT via $SSH_PROXY" "script $SCRIPT_FILE $SCRIPT_ARGS"
      proxy_command=$(build_proxy_command "$SSHCLIENT" "$remote_command" "true")
      "${_AUTH_PREFIX[@]}" ssh "$SSH_PROXY" -l "$SSH_PROXY_USER" "${SSH_OPTIONS[@]}" "$proxy_command" <"$SCRIPT_FILE"
    else
      _LOG "$SSHCLIENT" "script $SCRIPT_FILE $SCRIPT_ARGS"
      "${_AUTH_PREFIX[@]}" ssh "$SSHCLIENT" "${SSH_OPTIONS[@]}" "$remote_command" <"$SCRIPT_FILE"
    fi
  } >"$TMPFILE" 2>&1
}

run_scp_job(){
  local SSHCLIENT="$1"
  local TMPFILE="$2"
  local remote_target="${SSHCLIENT}:"

  [ -n "$REMOTE_PATH" ] && remote_target="${SSHCLIENT}:${REMOTE_PATH}"

  {
    echo -e "\033[34m###################### $SSHCLIENT $(date +%H:%M) ######################\033[0m"
    _LOG "$SSHCLIENT" "scp $SCP_FILE $remote_target"
    "${_AUTH_PREFIX[@]}" scp "${SSH_OPTIONS[@]}" "$SCP_FILE" "$remote_target"
  } >"$TMPFILE" 2>&1
}

flush_completed_jobs(){
  local idx
  local pid
  local status
  local remaining_pids=()
  local remaining_hosts=()
  local remaining_tmpfiles=()

  for idx in "${!JOB_PIDS[@]}"; do
    pid="${JOB_PIDS[$idx]}"
    if kill -0 "$pid" 2>/dev/null; then
      remaining_pids+=("$pid")
      remaining_hosts+=("${JOB_HOSTS[$idx]}")
      remaining_tmpfiles+=("${JOB_TMPFILES[$idx]}")
      continue
    fi

    wait "$pid"
    status=$?
    cat "${JOB_TMPFILES[$idx]}"
    echo
    cat "${JOB_TMPFILES[$idx]}" >>"$_LOG_FILE"
    JOB_STATUSES+=("${JOB_HOSTS[$idx]}:$status")
    rm -f "${JOB_TMPFILES[$idx]}"
  done

  JOB_PIDS=("${remaining_pids[@]}")
  JOB_HOSTS=("${remaining_hosts[@]}")
  JOB_TMPFILES=("${remaining_tmpfiles[@]}")
}

wait_for_all_jobs(){
  while [ "${#JOB_PIDS[@]}" -gt 0 ]; do
    flush_completed_jobs
    [ "${#JOB_PIDS[@]}" -gt 0 ] && sleep 1
  done
}

#### Options ################

if [[ "$1" =~ ^((-{1,2})([Hh]$|[Hh][Ee][Ll][Pp])|)$ ]]; then
  display_help 0
  exit 1
else
  while [[ $# -gt 0 ]]; do
    opt="$1"
    shift
    case "$opt" in
      -l|--list) require_option_value "$opt" "$1"; VMLIST="$1"; shift ;;
      -f|--file) require_option_value "$opt" "$1"; VMLIST="$(cat "$1")"; shift ;;
      -F|--force) FORCE="1" ;;
      -N|--noask) NOASK="1" ;;
      -p|--parallel) require_option_value "$opt" "$1"; PARALLEL="$1"; shift ;;
      -s|--sshProxy) require_option_value "$opt" "$1"; SSH_PROXY="$1"; shift ;;
      -u|--sshProxyUser) require_option_value "$opt" "$1"; SSH_PROXY_USER="$1"; shift ;;
      -C|--scp) require_option_value "$opt" "$1"; SCP_FILE="$1"; shift ;;
      -S|--script) require_option_value "$opt" "$1"; SCRIPT_FILE="$1"; shift ;;
      -a=*|--scriptArgs=*) require_non_empty_value "${opt%%=*}" "${opt#*=}"; SCRIPT_ARGS="${opt#*=}" ;;
      -a|--scriptArgs) require_non_empty_value "$opt" "$1"; SCRIPT_ARGS="$1"; shift ;;
      -r|--remotePath) require_option_value "$opt" "$1"; REMOTE_PATH="$1"; shift ;;
      -c|--cmd) CMD="$*"; break ;;

      -h|--help) display_help 0; exit ;;
      *) echo "ERROR: Invalid option: \"$opt\"" >&2
         exit 1 ;;
    esac
  done
fi

if [ -z "$VMLIST" ]; then
  echo "You must provide --list or --file"
  exit 1
fi

MODE_COUNT=0
[ -n "$CMD" ] && MODE_COUNT=$((MODE_COUNT + 1))
[ -n "$SCP_FILE" ] && MODE_COUNT=$((MODE_COUNT + 1))
[ -n "$SCRIPT_FILE" ] && MODE_COUNT=$((MODE_COUNT + 1))

if [ "$MODE_COUNT" -gt 1 ]; then
  echo "Use only one mode among --cmd, --scp or --script"
  exit 1
fi

if [ "$MODE_COUNT" -eq 0 ]; then
  echo "You must provide --cmd, --scp or --script"
  exit 1
fi

if [ -n "$SCP_FILE" ] && [ ! -f "$SCP_FILE" ]; then
  echo "File not found: $SCP_FILE"
  exit 1
fi

if [ -n "$SCRIPT_FILE" ] && [ ! -f "$SCRIPT_FILE" ]; then
  echo "File not found: $SCRIPT_FILE"
  exit 1
fi

if [ -n "$SCP_FILE" ] && [ -n "$SSH_PROXY" ]; then
  echo "The --scp mode is not supported with --sshProxy"
  exit 1
fi

if ! [[ "$PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
  echo "Parallel value must be a positive integer"
  exit 1
fi

# add reachable hosts to server array
declare -a server=()
for TRI in $VMLIST; do
  if _CHECK_HOST_RESOLVE "$TRI"; then
    append_unique_server "$TRI"
  elif [ "$FORCE" = 1 ]; then
    echo "Host does not resolve: $TRI (forced)" >&2
    append_unique_server "$TRI"
  else
    echo "Host not found: $TRI" >&2
  fi
done

[ -z "${server[*]}" ] && echo "No Server Found.." && exit 1

_setup_auth
if [ "$_AUTH_MODE" = "pass" ]; then
  _AUTH_PREFIX=(sshpass -e)
else
  _AUTH_PREFIX=()
fi

echo -e "\033[34m###################### SSH Command List Parallel ######################\033[0m"
echo "SRV      : ${server[*]}"
echo "PARALLEL : $PARALLEL"
if [ -n "$SCP_FILE" ]; then
  echo "MODE     : scp"
  echo "FILE     : $SCP_FILE"
  echo "DEST     : ${REMOTE_PATH:-remote home directory}"
elif [ -n "$SCRIPT_FILE" ]; then
  echo "MODE     : script"
  echo "SCRIPT   : $SCRIPT_FILE"
  [ -n "$SCRIPT_ARGS" ] && echo "ARGS     : $SCRIPT_ARGS"
else
  echo "MODE     : ssh"
  echo "CMD      : $CMD"
fi
[ -n "$SSH_PROXY" ] && echo "PROXY    : $SSH_PROXY (user: $SSH_PROXY_USER, hop command: sudo -n ssh)"

if [ -z "$NOASK" ]; then
  read -n1 -p "Launch SSH command [Y/n]"
  [[ "$REPLY" =~ n|no|N|No ]] && exit 0
fi
echo

for SSHCLIENT in "${server[@]}"; do
  while [ "${#JOB_PIDS[@]}" -ge "$PARALLEL" ]; do
    flush_completed_jobs
    [ "${#JOB_PIDS[@]}" -ge "$PARALLEL" ] && sleep 1
  done

  TMPFILE=$(mktemp)
  if [ -n "$SCP_FILE" ]; then
    run_scp_job "$SSHCLIENT" "$TMPFILE" &
  elif [ -n "$SCRIPT_FILE" ]; then
    run_script_job "$SSHCLIENT" "$TMPFILE" &
  else
    run_ssh_job "$SSHCLIENT" "$TMPFILE" &
  fi
  JOB_PIDS+=("$!")
  JOB_HOSTS+=("$SSHCLIENT")
  JOB_TMPFILES+=("$TMPFILE")
done

wait_for_all_jobs

FAILED=0
for RESULT in "${JOB_STATUSES[@]}"; do
  STATUS=${RESULT##*:}
  if [ "$STATUS" -ne 0 ]; then
    FAILED=1
    break
  fi
done

echo -e "\033[34m###################### Summary ######################\033[0m"
for RESULT in "${JOB_STATUSES[@]}"; do
  HOST=${RESULT%:*}
  STATUS=${RESULT##*:}
  echo "$HOST : exit=$STATUS"
done

exit "$FAILED"
