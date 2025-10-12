#!/bin/bash
### Redis Sync server
# v0.4 - Vars for all + check
# v0.3 - clean output
# v0.2 - added checks
# v0.1 - POC

### VARS
while (( "$#" )); do
  case "$1" in
    -m|--master) _REDIS_MASTER="$2"; shift 2;;
    -s|--slave) _REDIS_SLAVE="$2"; shift 2;;
    -sm|--masterpass) _REDISCLI_MASTER="$2"; shift 2;;
    -sp|--slavepass) _REDISCLI_SLAVE="$2"; shift 2;;
    *) echo "Wrong Parameter"; exit 1;;
  esac
done

# checks
[ -z "${_REDIS_MASTER}" -a -z "${_REDIS_SLAVE}" ] && { echo "Servers Vars Not Set.. Exit"; exit 1; }
[ -z "${_REDISCLI_MASTER}" -o -z "${_REDISCLI_SLAVE}" ] && { echo "Password Vars Not Set.. Exit"; exit 1; }

# colors
_REZ='\033[0m'
_RDX='\033[1;31m'
_BLX='\033[1;34m'
_GRX='\033[1;32m'

### FUNCTIONS
# Func to test replication progress
_SYNC_IN_PROGRESS(){ redis-cli -h ${_REDIS_SLAVE} -a ${_REDISCLI_SLAVE} info replication 2>/dev/null |awk -F':' '/master_sync_in_progress/ {print $NF}' ; }

# Func to display server role and keys
_REDIS_SRV_INFO(){
echo -e "${_BLX}# Master: ${_REDIS_MASTER} ${_REZ}\c"
redis-cli -h ${_REDIS_MASTER} -a ${_REDISCLI_MASTER} info replication 2>/dev/null |grep role
redis-cli -h ${_REDIS_MASTER} -a ${_REDISCLI_MASTER} info keyspace 2>/dev/null |grep -v '^#'
echo -e "${_BLX}# Slave: ${_REDIS_SLAVE} ${_REZ}\c"
redis-cli -h ${_REDIS_SLAVE} -a ${_REDISCLI_SLAVE} info replication 2>/dev/null |grep role
redis-cli -h ${_REDIS_SLAVE} -a ${_REDISCLI_SLAVE} info keyspace 2>/dev/null |grep -v '^#'
}

### MAIN
echo -e "${_BLX}############################# Redis Sync ###############################${_REZ}"
_REDIS_SRV_INFO

# Show number of keys of both instances and test if server is in master mode
[[ $(redis-cli -h ${_REDIS_MASTER} -a ${_REDISCLI_MASTER} info replication 2>/dev/null |awk -F':' '/role/ {print $NF}') =~ master ]] || { echo "Redis Master Server is not in Master mode.. exit"; exit 1; }
[[ $(redis-cli -h ${_REDIS_SLAVE} -a ${_REDISCLI_SLAVE} info replication 2>/dev/null |awk -F':' '/role/ {print $NF}') =~ master ]] || { echo "Redis Backup Server is not in Master mode.. exit"; exit 1; }

# Set auth and sync
echo -e "${_GRX}# Startup Sync: ${_REDIS_MASTER} to ${_REDIS_SLAVE}${_REZ}"
redis-cli -h ${_REDIS_SLAVE} -a ${_REDISCLI_SLAVE} config set masterauth ${_REDISCLI_MASTER} 2>/dev/null
redis-cli -h ${_REDIS_SLAVE} -a ${_REDISCLI_SLAVE} slaveof ${_REDIS_MASTER} 6379 2>/dev/null
sleep 15

# wait the end of sync
while [[ $(_SYNC_IN_PROGRESS) =~ 1 ]]; do
  echo "Sync in Progress.."
  sleep 30
done
echo -e "${_GRX}#Done${_REZ}"

# Conf backup server in master mode after sync complete
redis-cli -h ${_REDIS_SLAVE} -a ${_REDISCLI_SLAVE} slaveof no one 2>/dev/null
_REDIS_SRV_INFO
