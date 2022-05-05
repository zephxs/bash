#!/bin/bash
_LOGD="/root/blacklist/logs"
_OLDFAILNB=$(cat ${_LOGD}/.failnumber)

# main check
awk '/ 400 / {print $1}; / 404 / {print $1}; / 500 / {print $1}; / 502 / {print $1}' /var/log/nginx/access.log |sort -nu >${_LOGD}/ng-black.ips.tmp
zcat /var/log/nginx/access.log*.gz | awk '/ 400 / {print $1}; / 404 / {print $1}; / 500 / {print $1}; / 502 / {print $1}' | sort -nu >>${_LOGD}/ng-black.ips.tmp
_ACTUALFAILNB=$(cat ${_LOGD}/ng-black.ips.tmp|sort -nu |wc -l)
if [ "$_ACTUALFAILNB" != "$_OLDFAILNB" ]; then
cat ${_LOGD}/ng-black.ips.tmp|sort -nu |wc -l >${_LOGD}/.failnumber
cat ${_LOGD}/ng-black.ips.tmp|sort -nu >${_LOGD}/ng-black.ips
# check if not already in a Blacklist and add to "manual-blacklist" blacklist
for _IP in $(cat ${_LOGD}/ng-black.ips); do
if ! blacklist-check $_IP > /dev/null 2>&1; then
ipset add manual-blacklist "$_IP" && echo "$_IP # blacklisted $(date "+%d-%m-%Y %H:%M:%S")" >> "${_LOGD}/ng-blacklist"
fi
done
fi
