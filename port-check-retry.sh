#!/bin/bash
##### Script to retry port-check.sh every 60 sec 
##### if failed are reported during standard test
### v0.1 - work as expected
#
# PRE-REQUISITES: 
# - nc (netcat from nmap team)
# - telegram-send

# set Variables
_RETRYTIMER="60"
_RETRYPORT=""
_RETRYHOST=""
_RETRYLIST="$HOME/port-check-retry.list"

_RETRYALARM(){
[ -z "$_RETRYHOST" -o -z "$_RETRYPORT" ] && exit
if ! nc -zw1 $_RETRYHOST $_RETRYPORT; then
telegram-send -c alarm "Port Check Warning!
# Host: ${_RETRYFNAME}
# Addr: ${_RETRYHOST}
# Port: ${_RETRYPORT}/tcp still NOT OPEN"
else
telegram-send -c alarm "Port Check Recover!
# Host: ${_RETRYFNAME}
# Addr: ${_RETRYHOST}
# Port: ${_RETRYPORT}/tcp IS RE OPENED !"
sed -i "/$_RETRYHOST/d" $_RETRYLIST
fi
}

# Main
while [ -s "${_RETRYLIST}" ]; do
  sleep $_RETRYTIMER
  while read _RETRYLINE; do
    _RETRYHOST=$(echo $_RETRYLINE |awk -F';' '{print $1}')
    _RETRYPORT=$(echo $_RETRYLINE |awk -F';' '{print $2}')
    _RETRYFNAME=$(echo $_RETRYLINE |awk -F';' '{print $NF}')
    _RETRYALARM
  done < $_RETRYLIST
done
