#!/bin/bash
##### Check domain name Certificate expiration date
### v0.1 - POC

# VARS
_CERTCHECKDOMAIN=""

# FUNCTIONS
_SCRIPTUSAGE(){ echo -e "Usage:\n$(basename $0) -d your.domain.com\n$(basename $0) your.domain.com\n"; }

while (( "$#" )); do
  case "$1" in
  -d|--domain)
    if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
    _CERTCHECKDOMAIN="$2"
    shift 2
    fi
    ;;
  -h|--help)
    _SCRIPTUSAGE
    exit 3
    ;;
  *) _CERTCHECKDOMAIN="${1}"; shift ;;
  esac
done

if [ -z "$_CERTCHECKDOMAIN" ]; then
  echo "Domain not set. Please Enter a domain to test certificate:"
  read -p "# Domain = " _CERTCHECKDOMAIN
fi

_ENDDATE=$(echo | openssl s_client -connect "$_CERTCHECKDOMAIN":443 2>/dev/null | openssl x509 -noout -enddate | awk -F'=' '/=/ {print $2}')


# MAIN
if [ "$(date +'%s')" -gt "$(date  -d "$_ENDDATE" +'%s')" ]; then
  echo "CRITICAL - Certificate for '$_CERTCHECKDOMAIN' is outdated  [End: $_ENDDATE]"
  exit 2
elif [ "$(date +'%s')" -ge "$(date  -d "$_ENDDATE -10days" +'%s')" ]; then
  echo "WARNING - Certificate for '$_CERTCHECKDOMAIN' needs Renewal  [End: $_ENDDATE]"
  exit 1
else
  echo "OK - Certificate for '$_CERTCHECKDOMAIN' does not need renewal  [End: $_ENDDATE]"
  exit 0
fi


