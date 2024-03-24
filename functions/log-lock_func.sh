#!/bin/bash
##### Sample log and lock functions
### v0.3 - Added basename for lock file name

_LOCK(){
_LOCKFILE="/tmp/$(basename -s '.sh' $0).lock"
if [ -e "$_LOCKFILE" ]; then
  _PROCESSID=$(cat ${_LOCKFILE})
  if ps -p $_PROCESSID -o pid= >/dev/null 2>&1; then
    echo "Process is already running.. Exit!"
    exit 1
  fi
fi
echo $$ >$_LOCKFILE
trap 'rm -f "$_LOCKFILE"' EXIT
}

_LOG(){
# _LOG "WARNING" "message"
LOG_FILE="/var/log/myscript.log"
local _LEVEL="$1"
local _MESSAGE="$2"
local _TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
printf "[${_TIMESTAMP}] [${_LEVEL}] ${_MESSAGE}\n" >>$LOG_FILE
}

_DIE(){
_LOG "FAIL" "$1"
rm -f "$_LOCKFILE"
exit 1
}

