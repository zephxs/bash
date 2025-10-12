#!/bin/bash
### Check Observium all devices if statuses are OK
# centreon RO pass for checking API
#PASS hidden in centreon service

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

# Only arg is centreon Observium user password
PASS="$1"
[ -z "$PASS" ] && { echo 'Password not set, input pass as only arg'; exit "$STATE_UNKNOWN"; }

# Get Observium Devices statuses json
_JSON_RESULT=$(curl -su "centreon:$PASS" http://centreon.corp.com/api/v0/devices/)

# check json output
[ "$(echo $_JSON_RESULT |jq >/dev/null; echo $?)" -eq 0 ] || { echo "Output is not Json File.."; exit "$STATE_UNKNOWN"; }

# check if auth succeeded
[ "$(echo $_JSON_RESULT |jq '.status')" = "failed" ] && { echo "Json Query failed, auth seems KO.."; exit "$STATE_UNKNOWN"; }

# Get Devices statuses
_DEVICES_NB="$(echo $_JSON_RESULT |jq -r '.devices[].device_id' |wc -l)"
_DEVICES_OK="$(echo $_JSON_RESULT |jq -r '.devices[] |select(.status_type|contains("ok")) |.device_id'  |wc -l)"

if [ $_DEVICES_NB = $_DEVICES_OK ]; then
    echo "OK - All devices are Up"
    exit "$STATE_OK"
else
    echo "KO - NOT All devices are Up"
    exit "$STATE_WARNING"
fi

