#!/bin/bash
echo "##############################"
echo "       $(hostname) "
echo "##############################"
_USR='userx'
_KEY='ssh-rsa AAAAAXXXX'

if ! id -u "$_USR" >/dev/null 2>&1; then echo "User $_USR Not Found!" && exit 1 ; fi
for i in $(grep ${_USR} /etc/passwd); do
_HOME=$(echo $i|awk -F: '{print $6}') && grep -q "${_KEY}" ${_HOME}/.ssh/authorized_keys || cat >> ${_HOME}/.ssh/authorized_keys <<EOF
$_KEY
EOF
echo "##### Key found/installed for $_USR:" && grep "${_KEY}" ${_HOME}/.ssh/authorized_keys || echo "##### KEY NOT INSTALLED/FOUND"

##### access.conf
_ADDIP='172.2.0.0/24'
for _IPX in $(echo $_ADDIP); do
if grep "^-:${_USR}" /etc/security/access.conf|grep -q $_IPX ; then
echo "##### $_IPX already in access.conf:"
grep $_USR /etc/security/access.conf|grep $_IPX
else
[ -e /etc/security/access.conf-$(date "+%Y-%m-%d") ] || cp /etc/security/access.conf{,-$(date "+%Y-%m-%d")}
sed -i "/^-:${_USR}/  s|$| $_IPX|" /etc/security/access.conf
echo "##### $_IPX added to access.conf for $_USR"
grep $_USR /etc/security/access.conf|grep $_IPX
fi
done
done
