#!/bin/bash
echo "##############################"
echo "       $(hostname) "
echo "##############################"
die () {
echo $1
exit 1
}

uname -mrs && cat /etc/redhat-release
if [ "$(ls -A /etc/yum.repos.d|wc -l)" -ne 0 ]; then
echo "### removing old repo files for redhat satellite clients..."
mv -f /etc/yum.repos.d/* /root/
fi
echo "### clean yum and /var..."
yum clean all && rm -rf /var/cache/yum
if mount|grep boot|awk -F'(' '{print $2}'|grep rw; then echo "/boot already in rw"; else
echo "remounting /boot in rw"
mount -o remount,rw /boot
fi
if ! command -v needs-restarting >/dev/null; then
yum install -y yum-utils
fi
yum --disablerepo=centos7.repo1,centos7.repo2 -y update --nogpgcheck && echo "### Update Done !" || die
needs-restarting -r
echo
