#!/bin/bash
##### Check if domain SSL Certificate is revoked by OCSP list
### v0.1 - POC

# VARS
_CERTCHECKDOMAIN=""
_TMPDIR=$(mktemp -d /tmp/cert-check)
_CERTFILE="${_TMPDIR}/fullchain.crt"
_SRVFILE="${_TMPDIR}/server.pem"
_ISSUERFILE="${_TMPDIR}/issuer.crt"

# FUNCTIONS
_SCRIPTUSAGE(){ echo -e "Usage:\n$(basename $0) -d your.domain.com        # Check OCSP certificate for revocation\n$(basename $0) your.domain.com           # Same\n"; }

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

echo -e "\033[1;34m########### $_CERTCHECKDOMAIN ############\033[0m"

# Get Full Chain
openssl s_client -showcerts -connect "$_CERTCHECKDOMAIN":443 </dev/null 2>/dev/null >${_CERTFILE}

# Get server certificate
openssl s_client -showcerts -connect "$_CERTCHECKDOMAIN":443 </dev/null 2>/dev/null |openssl x509 -outform PEM >${_SRVFILE}

# Get issuer certificate
cat $_CERTFILE |awk '/-----BEGIN CERTIFICATE-----/{n++} n==2 {print $0}' >${_ISSUERFILE}
sed -i '1,/-----END CERTIFICATE-----/!d' ${_ISSUERFILE}

# Get OCSP resolver URL
_OCSPURI=$(openssl x509 -in ${_CERTFILE} -noout -text |awk -F'URI:' '/OCSP/ {print $2}')

# Check
echo "OCSP URL: ${_OCSPURI}"
openssl ocsp -issuer ${_TMPDIR}/issuer.crt -cert ${_SRVFILE} -url ${_OCSPURI}

# Cleanup
rm -rf ${_TMPDIR}
