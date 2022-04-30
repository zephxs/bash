#!/bin/bash
### needs etherwake bin
### to place in PATH on bastion server that can send wol

_SRVLIST='/root/wol-srv'
### list file:
# server1 00:00:11:22:33
# server2 00:11:22:33:33

select _SRV in $(awk '{print $1}' ${_SRVLIST}); do
etherwake $(grep -w $_SRV ${_SRVLIST}|awk '{print $2}')
break
done
