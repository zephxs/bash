#!/bin/bash
### Get PuppetBoard Infos of all servers

# Puppet Servers
_ALL_SERVERS="puppet.corp.com puppet-dev.corp.com puppet-pprod.corp.com"
declare _MASTER_SERVERS=()

# Color
source ~/01-myecho-colors.sh

# Logs
_LOGFILE="$HOME/logs/puppetboads.log"

_HELPFUNCTION(){
echo -e "### PuppetBoards
# Usage:
-s|--server		# Puppet Server to check
-n|--node		# Puppet agent node to check
-l|--list		# List Puppet servers
-f|--fail               # List only failed agents
"
}

while (( "$#" )); do
  case "$1" in
    -l|--list) _LIST_ONLY='1'; shift;;
    -f|--fail) _FAIL_ONLY='1'; shift;;
    -s|--server)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        _MASTER_SERVERS+=("$2"); shift 2;
      else
        echo "$2 Server missing..";
        return;
      fi
      ;;
    -n|--node)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        _SEARCHNODE="$2"; shift 2;
      else
        echo "$2 Node missing..";
        return;
      fi
      ;;
    -h|--help)
      _HELPFUNCTION
      exit
      ;;
    *) _SRV="$1"; shift
      ;;
  esac;
done

[ "$_LIST_ONLY" = "1" ] && { _MYECHO -t "Puppet Masters"; for i in ${_ALL_SERVERS[@]}; do echo $i; done; exit; }
# Checks
[ -z "${_MASTER_SERVERS[*]}" ] && _MASTER_SERVERS+=("$_ALL_SERVERS")

echo -e "###########################
####### $(date '+%Y-%m-%d %H:%M:%S')
###########################
" >>$_LOGFILE

if [ ! -z "$_SEARCHNODE" ]; then
  for _SERVER in ${_MASTER_SERVERS[@]}; do
    if curl -s -H "Accept: application/json" "http://$_SERVER/nodes" |awk '/status" href/ {print $6}' |grep -q $_SEARCHNODE ; then
      _NODE=$(curl -s -H "Accept: application/json" "http://$_SERVER/nodes" |awk '/status" href/ {print $6}' |grep $_SEARCHNODE |awk -F'/|>|<' '{print $3}')
      _STATUS=$(curl -s -H "Accept: application/json" "http://$_SERVER/nodes" |awk '/status" href/ {print $6}' |grep $_SEARCHNODE |awk -F'/|>|<' '{print $5}')
    _MYECHO "[${_SERVER}] $_NODE"
    [ "$_STATUS" = "UNCHANGED" ] && _OK || _KO ":$_STATUS"
    echo "[${_SERVER}] ${_NODE} : ${_STATUS}" >>${_LOGFILE}
    fi
  done
exit 0
fi

# Main
for _SERVER in ${_MASTER_SERVERS[@]}; do
_NODENUMBER=$(curl -s -H "Accept: application/json" "http://$_SERVER/nodes" |grep '\/node\/' |wc -l |awk '{print $1}')
  _MYECHO -l; _MYECHO -t "$_SERVER"
  curl -s -H "Accept: application/json" "http://$_SERVER/nodes" |awk '/status" href/ {print $6}' |awk -F'/|>|<' '{print $3" "$5}' | while read _NODE _STATUS; do
    if [ -z "$_FAIL_ONLY" ]; then
    _MYECHO "$_NODE"
    [ "$_STATUS" = "UNCHANGED" ] && _OK || _KO ":$_STATUS"
    echo "[${_SERVER}] ${_NODE} : ${_STATUS}" >>${_LOGFILE}
    else
    [ "$_STATUS" = "UNCHANGED" ] || { _MYECHO "$_NODE" && _KO ":$_STATUS"; echo "[${_SERVER}] ${_NODE} : ${_STATUS}" >>${_LOGFILE}; }
    fi
  done
  _MYECHO -d "Total Nodes" && echo "$_NODENUMBER"
  echo "[${_SERVER}] TOTAL NODES : $_NODENUMBER" >>${_LOGFILE}
done
