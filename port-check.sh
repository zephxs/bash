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
_VERB=""
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
echo "# Usage:"
echo "$(basename $0) -p 22 myhost.net     # Check port 22/tcp"
echo "$(basename $0) -v -l                # Check list file (default: $HOME/port-check.list) with verbose output"
echo "$(basename $0) -v -n -l             # Check without alerting"
exit 0
}

while (($#)); do
  case $1 in
    -p|--port) _PORT=$2; shift 2 ;;
    -t|--target) _HOST=$2; shift 2 ;;
    -n|--no-telegram) _ALERT=no; shift 1 ;;
    -l|--list)
	  if [ "$2" != "" ]; then
	    _LIST=$2; shift 2
	  else
	    [ -f "$_LIST" ] && shift 1 || { echo "File $_LIST not found, exiting.."; exit 1; }
	  fi
	  echo "Port List = $_LIST"
	  ;;
    -v|--verbose) _VERB='true'; shift 1 ;;
    -h|--help) usage_fn && exit 0 ;;
    -*) usage_fn && exit 1 ;;
    *) _HOST=$1; shift 1 ;;
  esac
done

[ "$_VERB" = true ] && _CHECKMYECHO && _MYECHO -t "Port Tester ### $_VERS"
# test if host exists
[ -z "$_HOST" ] && usage_fn && exit 1
if ! host $_HOST >/dev/null 2>&1; then
  _MYECHO "Hostname $_HOST" && _KO
  exit 1
fi


_ALARM(){
<<<<<<< HEAD
# test if host exists
[ -z "$_HOST" ] && usage_fn && exit 1
=======
>>>>>>> 3da6418a11fce084b77c57048516b288dbcffc0f
[ -z "$_PORT" ] && usage_fn && exit 1 
[ -z "$_VERB" ] || _MYECHO "$_HOST"
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
    _HOST=$(echo $_LINE |awk -F',' '{print $1}')
    _PORT=$(echo $_LINE |awk -F',' '{print $2}')
    _FNAME=$(echo $_LINE |awk -F',' '{print $NF}')
    _ALARM
  done < $_LIST
else
  _ALARM
fi

