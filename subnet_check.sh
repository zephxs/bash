#!/bin/bash
### ping subnet in $1
trap ctrl_c INT
ctrl_c(){ exit 0; }
_LOG(){
LOG_FILE="/tmp/$(basename -s '.sh' $0).log"
local _LEVEL="$1"
local _MESSAGE="$2"
local _TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
printf "[${_TIMESTAMP}] [${_LEVEL}] ${_MESSAGE}\n" >>$LOG_FILE
}
_REZ='\033[0m'
_RDX='\033[1;31m'
_BLX='\033[1;34m'
_GRX='\033[1;32m'
_OK () { echo -e "[${_GRX}OK${_REZ}${@}]" ; }
_KO () { echo -e "[${_RDX}KO${_REZ}${@}]" ; }
_MYECHO(){
_DOTNUM='54'
if [ -z "$1" ]; then echo "<!> need argument"; return 1; fi
_CHAINL=$(echo $@ | wc -c)
_DOTL=$((_DOTNUM - _CHAINL))
i=0
echo -e "${_BLX}#${_REZ} ${@}\c"
while [ "$i" -lt "$_DOTL" ]; do echo -e ".\c"; i=$((i+1)); done
echo -e "\c"
return 0
}

#while (( $# )); do
#  case $1 in
#    -s|--subnet) _SUBNET="$1"; shift 2;;
#    -h|--help) echo "Usage: $0"
#      echo "# check current machine subnet"
#      echo "  -s|--subnet  choose subnet to test [ex: '192.168.1.']"
#      echo "  -h|--help     Show this help"
#      exit 0
#      ;;
#    *) echo "Unknown option: $1"; exit 1 ;;
#  esac
#done


echo -e "${_BLX}############################# Subnet Ping ###############################${_REZ}"
if [ -z "$1" ]; then
  _SUBNET=$(hostname -i |awk -F'.' '{print $1"."$2"."$3"."}')
else
  _SUBNET=$(echo $1 |awk -F'.' '{print $1"."$2"."$3"."}')
fi
for _TESTIP in ${_SUBNET}{10..253} ; do
  _MYECHO "$_TESTIP"
  if ping -4 -w 1 -c 1 -n -q $_TESTIP >/dev/null 2>&1; then
     _KO ":IP already in use"
     _LOG "$_TESTIP" "[PING] Already In Use"
  else
    if host $_TESTIP >/dev/null 2>&1; then
      _KO ":IP already has DNS entry"
      _LOG "$_TESTIP" "[DNS] Already In Use"
    else
      _OK ":IP looks Free"
      _LOG "$_TESTIP" "Free"
    fi
  fi
done
