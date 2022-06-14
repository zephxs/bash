### SSH AGENT SESSION LOADER
sshagent-loader () {
# v1.5 - Personal ssh multi session agent 
# set fixed agent socket and default key to load
# set key life time / empty for not setting lifetime
export SSH_AUTH_SOCK="$HOME/.ssh/ssh-agent.sock"
_MYSKEY="$HOME/.ssh/k2"
_TIME="28800"
_MYECHO -t "SSH Agent MultiLoader"

# func to get agent status from ssh-add exit code
_SSHAG () { ssh-add -l 2>/dev/null >/dev/null ; _RES=$? ; }
_SSHAG
while [ "$_RES" -ge 1 ]; do
  case $_RES in
  2)
    ssh-agent -a $SSH_AUTH_SOCK >$HOME/.ssh/.ssh-agent
    _MYECHO "Test SSH agent"
    sleep 0.4 && _SSHAG
    if [ "$_RES" = 2 ]; then
      _KO .NotLoaded && rm -f $SSH_AUTH_SOCK
    elif [ "$_RES" = 1 ]; then
      _OK .Starting && _SSHAG
    fi
    ;;
  1)
    _MYECHO -p "Add Key: '$_MYSKEY' ? [Y/n]"
    read -s -n1
    if [[ "$REPLY" =~ [Yy] ]]; then
      [ -z "$_TIME" ] && ssh-add -q ${_MYSKEY} || ssh-add -q -t $_TIME ${_MYSKEY}
      _SSHAG
    else
      _MYECHO "Loaded SSH keys" && _KO ".None"
      echo && return 0
    fi
    ;;
  *)
    _RED "### Unknown return code.. exit"
    return 0
    ;;
  esac
done

_MYECHO "Test SSH Agent"
[ $_RES = 0 ] && _OK .Running || _KO
_KEY=$(ssh-add -l|awk -F/ '{print $NF}'|awk '{print $1}')
_MYECHO "Loaded SSH keys" && _OK .${_KEY}
echo
echo
}

# set 'sshagent-kill' function to remove key, kill agents linked to our socket if more than one and remove socket


sshagent-kill () {
# v.1.4
# get pid from exported agent
_SSHPID () { awk -F'=|;' '/SSH_AGENT_PID/ {print $2}' <$HOME/.ssh/.ssh-agent ; }
_MYECHO -l
_BLU "### [dont] Kill the ssh-agent !"
_MYECHO "Find Agent pid"
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

_MYECHO "Remove Key"
if ssh-add -D &>/dev/null; then _OK; else _KO ".NoKey"; fi
_MYECHO "Kill Agent"
if ssh-agent -k &>/dev/null; then _OK; else _KO; fi
if [ -e ${SSH_AUTH_SOCK} ]; then
_MYECHO "Remove Socket"
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
echo
}

