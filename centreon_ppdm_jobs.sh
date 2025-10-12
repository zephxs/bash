#!/bin/bash
### Get today's meta job activity from PPDM API

# centreon RO pass for checking API
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

# Preset
PPDM_PROD_SERVER='prod-powerprotect'
PPDM_PPROD_SERVER='pprod-powerprotect'
PPDM_DEV_SERVER='dev-powerprotect'
PPDM_SERVERS=()
PPDM_USERNAME='rouser'
PPDM_PASSWORD='xxxxxx'
#PPDM_PASSWORD=$(rbw get "PPDM")
JOBSTATUS=0


while (( $# )); do
  case $1 in
    -p|--prod)
      PPDM_SERVERS+=("$PPDM_PROD_SERVER"); shift;;
    -j|--jn)
      PPDM_SERVERS+=("$PPDM_PPROD_SERVER"); shift;;
    -c|--cp)
      PPDM_SERVERS+=("$PPDM_DEV_SERVER"); shift;;
    -a|--all)
      PPDM_SERVERS=("$PPDM_PROD_SERVER" "$PPDM_PPROD_SERVER" "$PPDM_DEV_SERVER"); shift ;;
    -h|--help) echo "Usage: $0     # Get All PPDM Jobs results"
      echo "  -p|--prod    # Prod only"
      echo "  -d|--dev     # Dev only"
      echo "  -t|--pprod   # PProd only"
      echo "  -a|--all     # All PPDM server"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[ -z "$PPDM_SERVERS" ] && \
PPDM_SERVERS=("$PPDM_PROD_SERVER" "$PPDM_PPROD_SERVER" "$PPDM_DEV_SERVER")

# get proper date format
CHK_DATE=$(date +%Y-%m-%dT00:00:00.000Z)

# Get JOB_GROUP activity
for PPDM_SERVER in ${PPDM_SERVERS[@]}; do
  # Get Token
  TOKEN=$(curl -sk --request POST \
    --url https://${PPDM_SERVER}:8443/api/v2/login \
    --header 'content-type: application/json' \
    --data '{"username":"'${PPDM_USERNAME}'","password":"'${PPDM_PASSWORD}'"}' | jq -r .access_token)

  # Show JOB results
  #echo -n "PPDM: $PPDM_SERVER # "
  curl -X GET -s "https://${PPDM_SERVER}:8443/api/v2/activities?filter=classType%20eq%20%22JOB_GROUP%22%20and%20category%20eq%20%22PROTECT%22%20and%20startTime%20ge%20%22${CHK_DATE}%22" -k --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" |jq '.content[] | "Policiy: \(.protectionPolicy.name), ID: \(.displayId), Assets OK: \(.stateSummaries.ok)/\(.stateSummaries.total), State: \(.state), Status: \(.result.status |select(. != "SKIPPED"))"'

  # Parse all result
  STATE=$(curl -X GET -s "https://${PPDM_SERVER}:8443/api/v2/activities?filter=classType%20eq%20%22JOB_GROUP%22%20and%20category%20eq%20%22PROTECT%22%20and%20startTime%20ge%20%22${CHK_DATE}%22" -k --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" |jq '.content[] | "\(.result.status |select(. != "SKIPPED"))"')

  while read RESULT; do
    echo "$RESULT" | grep -q 'OK' || JOBSTATUS=$((JOBSTATUS+1))
  done <<<$STATE

done
[ $JOBSTATUS -ne 0 ] && exit "$STATE_WARNING" || exit "$STATE_OK"
