echo "##############################"
echo "       $(hostname) "
echo "##############################"
echo
echo "####### HARDWARE ######"
echo "### CPU Model: $(lscpu|grep "Model name"|awk -F':            ' '{print $2}')"
echo "### CPU cores: $(lscpu | egrep 'CPU\(s\)\:'|grep -v NUMA|awk -F':                ' '{print $2}')"
echo "### RAM (in Mb):"
free -m|awk '{print $1"\t"$2"\t"$3"\t"$4}'
echo "### Mounts:"
df -h|head -1 && df -h|egrep -i 'root|var|usr|opt|pgdata|pgbackup'|sort
echo
echo "####### NETWORK #######"
_IPG0="$(ip ro sh|grep default|awk '{print $3}')"
_IPG1="$(ip ro sh|grep eth1|grep via|awk '{print $3}'|uniq)"
echo "### ETH0"
egrep 'IPADDR|NETMASK' /etc/sysconfig/network-scripts/ifcfg-eth0
grep GATEWAY /etc/sysconfig/network
echo "### eth0 Gateway Test:"
if [ "$(ip a|grep eth0|grep -v global|awk -F'state ' '{print $2}'|awk '{print $1}')" = 'UP' ]; then
ping -c 1 -w 1 $_IPG0 &> /dev/null && echo "$_IPG0 is reachable" || echo "$_IPG0 is NOT reachable ...KO"
else echo "interface eth0 is DOWN"; fi
if ip a|grep -q eth1; then
echo "### ETH1"
egrep 'IPADDR|NETMASK' /etc/sysconfig/network-scripts/ifcfg-eth1
ip ro sh|grep via|grep eth1
echo "### eth1 Gateway Test:"
if [ "$(ip a|grep eth1|grep -v global|awk -F'state ' '{print $2}'|awk '{print $1}')" = 'UP' ]; then
ping -c 1 -w 1 $_IPG1 &> /dev/null && echo "$_IPG1 is reachable" || echo "$_IPG1 is NOT reachable ...KO"
else echo "interface eth1 DOWN"; fi
fi
echo
echo "####### CONFIGS #######"
echo "### hosts: $(grep $(hostname) /etc/hosts)"
echo "### passwd: $(grep $(hostname) /etc/passwd)"
echo "### primary DNS: $(cat /etc/resolv.conf|grep -A 1 search|grep -v search|awk '{print $2}')"
echo "### primary NTP: $(grep prefer /etc/ntp.conf|awk '{print $2}')"
echo "### Postfix main.cf relayhost: $(grep relayhost /etc/postfix/main.cf |grep -v '#'|awk -F'= ' '{print $2}')"
echo
echo "####### REQUIRED #######"
echo "### Users:"
awk -F':' '$3>=1000 {print $1}' /etc/passwd |egrep -v 'statsys|zabbix|sriffault|ucmdb'
echo "### Sudoers:"
grep prod /etc/sudoers|grep nvL
echo "### Apps:"
yum -C list installed postgresql*-server
echo
