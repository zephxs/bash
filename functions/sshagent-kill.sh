# set 'sshagent-kill' function to remove key, kill agents linked to our socket if more than one and remove socket


sshagent-kill () {
# v.1.3
# get pid from exported agent
_SSHPID () { cat $HOME/.ssh/.ssh-agent|grep _PID|awk -F'[=;]' '{print $2}' ; }
_BLU "####################################################"
_BLU "### [dont] Kill the ssh-agent !"
_MYECHO "### Find Agent pid "
if [ -z "$SSH_AGENT_PID" ]; then
  if [ -z "$(_SSHPID)" ]; then
        _KO ".NotFound"
  else
export SSH_AGENT_PID=$(_SSHPID)
  fi
  if [ ! -z "$SSH_AGENT_PID" ]; then
    if ps aux |grep -v grep|grep -q $SSH_AGENT_PID; then _OK ".pid=$SSH_AGENT_PID"; else _KO ".NotRunning"; fi
  fi
else
  [ "$SSH_AGENT_PID" != "$(_SSHPID)" ] && export SSH_AGENT_PID=$(_SSHPID)
  if ps aux |grep -v grep|grep -q $SSH_AGENT_PID; then _OK ".pid=$SSH_AGENT_PID"; else _KO ".NotRunning"; fi
fi

_MYECHO "### Remove Key "
if ssh-add -D &>/dev/null; then _OK; else _KO ".NoKey"; fi
_MYECHO "### Kill Agent "
if ssh-agent -k &>/dev/null; then _OK; else _KO; fi
if [ -e ${SSH_AUTH_SOCK} ]; then
_MYECHO "### Remove Socket "
  rm -f $SSH_AUTH_SOCK &>/dev/null && _OK
fi
if ps --user $(id -u) -F|grep -v grep|grep -q ssh-agent; then
_MAV "### Search remaining agent for $(id -un)"
for i in $(ps --no-header --user $(id -u) -F|grep -v grep|grep ssh-agent|awk '{print $2}'); do
# cry if root user
  [ $(id -u) -eq 0 ] && _RED "Root user detected, CAUTION.."
# stop if pid not own by user
  ps -p $i -F|grep -v grep|grep ssh-agent|awk '{print $1}'|grep -q $(id -un) || continue
# stop if pid not numeric
  [ "$i" -eq "$i" ] || continue
  _RED "/!\ Check if PID match user ssh agent:"
  ps -p $i -F
  _RED "> kill PID $i ? [Y/n]"
  read -s -n1
  if [[ "$REPLY" =~ [Yy] ]]; then
    kill -9 $i
  fi
done
fi
#this one is just for style ;)
_MYECHO "### Agent Cleanup " && _OK ".Done"
echo
}

