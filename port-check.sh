#!/bin/bash
### Script to check port status and alert if not open
### v0.5 - update & corrections
### v0.4 - added friendly name
### v0.3 - added verbose mode
#
# PRE-REQUISITES: 
# - nc (netcat from nmap team)
# - telegram-send
# - 01-myecho-colors.sh (if verbose mode is enabled)
#
# List (-l|--list) format is comma separated:
# host, port, friendly name
# 10.10.10.10, 22, My Server

# set Variables
_PORT=""
_HOST=""
_LIST="$HOME/port-check.list"
_VERB="true"
_VERS=$(awk '/### v/ {print $2; exit}' $basename $0)

# check if nc is installed
if ! type -P nc &>/dev/null; then
  echo "'nc' not found, exiting.."
  exit 1
fi
# check if telegram-send is installed
if ! type -P telegram-send &>/dev/null; then
  echo "'telegram-send' not found, exiting.."
  exit 1
fi
# check if _MYECHO is present
_CHECKMYECHO(){ 
if ! type -t _MYECHO &>/dev/null;then
  . /etc/profile.d/01-myecho-colors.sh
fi
}

usage_fn(){
echo -e "# Arguments:
    -t|--target                    # Host to test port (accepted as only arg without tag)
    -p|--port                      # Tcp Port
    -n|--no-alarm                  # Do not alert
    -l|--list                      # Use List File (default: ~/port-check.list)
    -q|--quiet                     # No Output (used in script or cron)

# Exemples:
$(basename $0) -p 22 myhost.net     # Check port 22/tcp on myhost.net
$(basename $0) -q -l                # Check list file in quiet mode
$(basename $0) -n -l                # Check list file without alerting"
exit 0
}

while (($#)); do
  case $1 in
    -p|--port) _PORT=$2; shift 2 ;;
    -t|--target) _HOST=$2; shift 2 ;;
    -n|--no-telegram) _ALERT="no"; shift 1 ;;
    -l|--list)
	  if [ "$2" != "" ]; then
	    _LIST=$2; shift 2
	  else
	    [ -f "$_LIST" ] && shift 1 || { echo "File $_LIST not found, exiting.."; exit 1; }
	  fi
	  ;;
    -q|--quiet) _VERB=""; shift 1 ;;
    -h|--help) usage_fn && exit 0 ;;
    -*) usage_fn && exit 1 ;;
    *) _HOST=$1; shift 1 ;;
  esac
done

[ "$_VERB" = "true" ] && _CHECKMYECHO && _MYECHO -t "Port Tester ### $_VERS"


_ALARM(){
[ -z "$_HOST" -o -z "$_PORT" ] && exit
[ -z "$_VERB" ] || _MYECHO "$_FNAME @$_HOST"
if ! nc -zw1 $_HOST $_PORT; then
  [ "$_ALERT" = 'no' ] || telegram-send -c alarm "${_FNAME}

# Port Check Warning!
# IP: ${_HOST}   Port: ${_PORT}/tcp NOT OPEN"
  [ -z "$_VERB" ] || _KO ":${_PORT}/tcp"
else
  [ -z "$_VERB" ] || _OK ":${_PORT}/tcp"
fi
}

# Main
if [ -z "$_HOST" ]; then
  while read _LINE; do
    _HOST=$(echo $_LINE |awk -F';' '{print $1}')
    _PORT=$(echo $_LINE |awk -F';' '{print $2}')
    _FNAME=$(echo $_LINE |awk -F';' '{print $NF}')
    _ALARM
  done < $_LIST
else
  _ALARM
fi

