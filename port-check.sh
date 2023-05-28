#!/bin/bash
### Script to check port status and alert if not open
### v0.3 - added verbose mode
### v0.2 - added list support
### v0.1 - 2012-10-03 - Initial version
# PRE-REQUISITES: nc (netcat from nmap team), telegram-send, and 01-myecho-colors.sh
# For using list (--list), format is: host port
# and option -l | --list must be placed at the end of the command line as it accept argument or autosetting

# get script version
_VERS=$(awk '/### v/ {print $0; exit}' $basename $0 |awk '{print $2}')

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

_USAGE(){
echo "Test port status"
echo "$(basename $0) -p 22 -t myhost.net     # Check port 22/tcp"
echo "$(basename $0) -v -l                   # Check list file (default: $HOME/port-check.list) with verbose output"
exit 0
}

# set Variables
_PORT="8140"
_HOST="10.10.10.6"
_LIST="$HOME/port-check.list"
_VERB=""

while (($#)); do
  case $1 in
    -p|--port) _PORT=$2; shift 2 ;;
    -t|--target) _HOST=$2; shift 2 ;;
    -l|--list)
	  if [ "$2" != "" ]; then
	    _LIST=$2; shift 2
	  else
	    [ -f "$_LIST" ] && shift 1 || { echo "File $_LIST not found, exiting.."; exit 1; }
	  fi
	  ;;
    -v|--verbose) _VERB='true'; shift 1 ;;
    -h|--help) _USAGE && exit 0 ;;
    *) _USAGE && exit 1 ;;
  esac
done

[ "$_VERB" = true ] && _CHECKMYECHO && _MYECHO -t "Port Tester ### $_VERS"

_ALARM(){
[ -z "$_PORT" ] && _USAGE && exit 1
[ -z "$_HOST" ] && _USAGE && exit 1
if ! nc -zw1 $_HOST $_PORT; then
  telegram-send -c alarm "[WARNING - ${_HOST}]
  # Port: ${_PORT}/tcp NOT OPEN"
  [ -z "$_VERB" ] || _MYECHO "${_HOST}" && _KO ":${_PORT}/tcp"
else
  [ -z "$_VERB" ] || _MYECHO "${_HOST}" && _OK ":${_PORT}/tcp"
fi
}

# Main
if [ -f "$_LIST" ]; then
  while read _HOST _PORT; do
    _ALARM
  done < $_LIST
else
  _ALARM
fi

