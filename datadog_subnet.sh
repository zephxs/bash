#!/bin/bash
### Check if IP (only arg) is in Datadogs IP list found here : 'https://ip-ranges.datadoghq.com'
### v0.1 - added prips check, help and colors
### v0.1 - POC

if [ -z "$1" -o $1 = "-h" ]; then
  echo -e "IP address needed as argument, ex:\n    ${0} 192.168.1.119"; echo; exit 1
else
  _IP="$1"
fi

### SETTINGS
# Trap
trap ctrl_c INT
ctrl_c(){ exit 0; }

# Colors
_REZ='\033[0m'
_RDX='\033[1;31m'
_BLX='\033[1;34m'
_GRX='\033[1;32m'
_RED () { echo -e "${_RDX}${@}${_REZ}" ; }
_GRN () { echo -e "${_GRX}${@}${_REZ}" ; }
_BLU () { echo -e "${_BLX}${@}${_REZ}" ; }
_OK () { echo -e "[${_GRX}OK${_REZ}${@}]" ; }
_KO () { echo -e "[${_RDX}KO${_REZ}${@}]" ; }

# Myecho
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

# prips check
type prips >/dev/null 2>&1 || { _RED "Missing tool: 'prips' to check into subnet"; echo "install on mac with: 'brew install prips'"; exit 1; }

### MAIN
_BLU "#################### DataDog IP Check #######################"
_MYECHO "$_IP"
for _DTDADDRESS in $(curl -s -X GET https://ip-ranges.datadoghq.com |jq -r '.synthetics.prefixes_ipv4[]'); do
  for _DTDADDRESSSUB in $(prips $_DTDADDRESS); do
    if [ ${_DTDADDRESSSUB} = ${_IP} ]; then
      _OK ":${_DTDADDRESS}"
      _RED "IP Found in DataDog Ips: DO NOT BLACKLIST"
      echo; exit 0
    fi
  done
done
_KO
_GRN "IP Not Found in Datadog IPs, you can blacklist the IP Addess: $_IP"
echo
