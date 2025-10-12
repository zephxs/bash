#!/bin/bash
### Send SSH remote commands
#set +x

### VARS
FILE=$(readlink -f $0)
BASE=$(dirname $FILE)
# Orig param
#OPTION="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=43200"
OPTION="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=43200 -o LogLevel=ERROR"

### sshpass check
type 'sshpass' 2>&1 >/dev/null || { echo "sshpass binary is missing.. Please install before using this tool."; exit 1; }

[ -d "$HOME/logs" ] || mkdir $HOME/logs
_LOG_FILE="$HOME/logs/$(basename -s '.sh' $0).log"
trap ctrl_c INT
ctrl_c(){ exit 0; }

if [ -z "$PASS2" ]; then
  # needs rbw bitwarden cli to get Linux root password
  PASS2=$(rbw get "myroot password")
elif [ -z "$PASS2" ]; then
  read -sp "Input root password: " PASS2
fi

### FUNCTIONS 
_LOG(){
# _LOG "WARNING" "message"
local _LEVEL="$1"
local _MESSAGE="$2"
local _TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
printf "[${_TIMESTAMP}] [${_LEVEL}] ${_MESSAGE}\n" >>$_LOG_FILE
}

function display_help(){
    RET=$1
    echo "[Usage] $0 [OPTIONS OBLIGATOIRES]"
    echo "  Options Obligatoires:"
    echo "  -l | --list     vm-list	"
    echo "  -f | --file     vm-list	"
    echo "  -c | --cmd      command	"
    echo "  --linuxOnly     true/false (optional)	"
    exit $RET
}

_CHECK_IF_VM_EXIST(){
# Logic to check if VM exist and confirm hostname
VMOK=$(echo "$TRI")
}

### OPTIONS
if [[ "$1" =~ ^((-{1,2})([Hh]$|[Hh][Ee][Ll][Pp])|)$ ]]; then
  display_help 0; exit 1
else
  while [[ $# -gt 0 ]]; do
    opt="$1"
    shift;
    current_arg="$1"
    case "$opt" in
      -l|--list) VMLIST="$1"; shift;;
      -f|--file) VMLIST="$(cat $1)"; shift;;
      -F|--force) FORCE="1";;
      -c|--cmd) CMD="$@"; break;;
      -o|--linuxOnly) LINUXONLY="$1"; shift;;
      -h|--help) display_help 0; exit;;
      *) echo "ERROR: Invalid option: \""$opt"\"" >&2
         exit 1;;
    esac
  done
fi

# add server array
declare server=()
for TRI in $VMLIST; do
  _CHECK_IF_VM_EXIST
  [ -z "$VMOK" ] || server+=( "$VMOK" )
  [ "$FORCE" = 1 ] && server+=( "$TRI" )
done

[ -z "${server[*]}" ] && echo "No Server Found.." && exit 1

# OUTPUT
echo -e "\033[34m########################### SSH Command List ##########################\033[0m"
echo "CMD : $CMD"
echo "SRV : ${server[*]}"

if [ -z "$_JENKINS_LOCAL" ]; then
  read -n1 -p "Launch SSH command [Y/n]"
  echo
  [[ "$REPLY" =~ n|no|N|No ]] && exit 0
fi

for SSHCLIENT in "${server[@]}"; do
  echo -e "\033[34m###################### $SSHCLIENT $(date +%H:%M) ######################\033[0m"
  _LOG "$SSHCLIENT" "$CMD"
  sshpass -p "$PASS2" ssh -n "$SSHCLIENT" -l root $OPTION "$CMD" |tee -a $_LOG_FILE
  echo
done
