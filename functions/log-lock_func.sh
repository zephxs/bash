#!/bin/bash
##### Sample log and lock functions
### v0.4 - Fixed quoting, printf format, atomic lock with mkdir

_LOCK(){
_LOCKDIR="/tmp/$(basename -s '.sh' "$0").lock.d"
if ! mkdir "$_LOCKDIR" 2>/dev/null; then
  _PROCESSID=$(cat "${_LOCKDIR}/pid" 2>/dev/null)
  if ps -p "$_PROCESSID" -o pid= >/dev/null 2>&1; then
    echo "Process is already running.. Exit!"
    exit 1
  fi
  # Stale lock — clean up and retry
  rm -rf "$_LOCKDIR"
  if ! mkdir "$_LOCKDIR" 2>/dev/null; then
    echo "Cannot acquire lock.. Exit!"
    exit 1
  fi
fi
echo $$ > "${_LOCKDIR}/pid"
trap 'rm -rf "$_LOCKDIR"' EXIT
}

_LOG(){
# _LOG "WARNING" "message"
local LOG_FILE="/var/log/$(basename -s '.sh' "$0").log"
local _LEVEL="$1"
local _MESSAGE="$2"
local _TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
printf "[%s] [%s] %s\n" "$_TIMESTAMP" "$_LEVEL" "$_MESSAGE" >>"$LOG_FILE"
}

_DIE(){
_LOG "FAIL" "$1"
rm -rf "$_LOCKDIR"
exit 1
}