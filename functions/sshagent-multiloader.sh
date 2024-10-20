#!/bin/bash

sshagent-loader () {
### v2.0 - Local ssh multi session agent 
# added scan .ssh folder and load multiple keys at once
# set fixed agent socket and default key to load
# set key life time / empty for not setting lifetime
# handle forwarded agent
#local _MYSKEY="$HOME/.ssh/k2"
local _SETKEY=""
local _TIME="28800"
local _VERS='v2.0'
unset _SSHKARRAY
unset _LOADEDKEYS

_MYECHO -t "SSH Agent MultiSession ### $_VERS"

### FUNCTIONS
# function to get agent status from ssh-add exit code
_SSHAGENTCHECK (){ ssh-add -l >/dev/null 2>&1; _LOADRESULT=$?; }
_EXPORTAGENT (){ export SSH_AUTH_SOCK="$HOME/.ssh/ssh-agent.sock"; }

_KEYLOADER(){
# Scan .ssh folder, check if file is ssh key, and set array with choosen keys
[ -z "${_SETKEY}" ] || { _SSHKARRAY+=($_SETKEY) && return 0; }
_LOADEDKEYS=$(ssh-add -l |awk '{print $3}')
_MYECHO "Scan '$HOME/.ssh/'" && _OK
for _SSHKEY in $(find $HOME/.ssh/ -maxdepth 1 -type f |grep -Ev '.pub|ssh-agent|known|config|env|authorized'); do 
  echo "${_LOADEDKEYS}" | grep -q "$_SSHKEY" && continue
  ssh-keygen -l -f $_SSHKEY >/dev/null 2>&1 || continue
  _MYECHO "Add Key= $_SSHKEY ? [Y/n]"
  read -s -n 1
  [ "$REPLY" = 'n' ] && _KO && continue
  _SSHKARRAY+=($_SSHKEY)
  _OK
done
_MYECHO -c "purple" -p "Keys to load: ${_SSHKARRAY[*]}"
}

_PRELOADER(){
# set default socket to use
  [ -e "$SSH_AUTH_SOCK" ] && rm -f "$SSH_AUTH_SOCK"
  ssh-agent -a "$SSH_AUTH_SOCK" >$HOME/.ssh/.ssh-agent
  _MYECHO -e "Test SSH agent"
  sleep 0.3 && _SSHAGENTCHECK
  if [ "$_LOADRESULT" = 2 ]; then
    _KO ':NotLoaded' && rm -f "$SSH_AUTH_SOCK"
    return 1
  elif [ "$_LOADRESULT" = 1 ]; then
    _OK ':Starting' && _SSHAGENTCHECK
  fi
}

_AGENTLOADER(){
# load keys to agent
for _MYSKEY in "${_SSHKARRAY[@]}"; do
  _MYECHO -p "Loading Key= '$_MYSKEY'"
  [ -z "$_TIME" ] && ssh-add -q "${_MYSKEY}" || ssh-add -q -t "$_TIME" "${_MYSKEY}"
done
_SSHAGENTCHECK
}

### Base checks and setup
# chmod .ssh if not already user only readable, as we will store our agent here
[ -d "$HOME/.ssh" ] || mkdir -p $HOME/.ssh
[ "$(stat -c '%a %n' $HOME/.ssh)" = 700 ] || chmod 700 $HOME/.ssh

# test agent and setup
[ -z "$SSH_AUTH_SOCK" ] && _EXPORTAGENT
_SSHAGENTCHECK

### MAIN
# Act accordingly to 'ssh-add' exit code
while [ "$_LOADRESULT" -ge 1 ]; do
  case $_LOADRESULT in
  2) # Agent not loaded
    _EXPORTAGENT
    _PRELOADER
    ;;
  1) # Agent is loaded
    _KEYLOADER
    _AGENTLOADER
    ;;
  *) # exit on any other output code
    _MYECHO -c red -p "# Unknown return code.. exit"
    return 1
    ;;
  esac
done

# if reached, Agent is loaded with a key
_MYECHO "Test SSH Agent"
[ "$_LOADRESULT" = 0 ] && _OK ':Running' || _KO
_LOADEDKEYS=$(ssh-add -l |awk '{print $3}' |tr "\n" " ")
_MYECHO "Loaded SSH keys" && _OK ":${_LOADEDKEYS}"
_MYECHO -p "Load new Key ? [yN]"
read -s -n1
if [[ "$REPLY" =~ [Yy] ]]; then
  _KEYLOADER
  _AGENTLOADER
  _LOADEDKEYS=$(ssh-add -l |awk '{print $3}' |tr "\n" " ")
  _MYECHO "Loaded SSH keys" && _OK ":${_LOADEDKEYS}"
fi
_MYECHO "SSH Agent" && _OK ":Loaded"
}


# set 'sshagent-kill' function to remove key, kill agents linked to our socket if more than one and remove socket
sshagent-kill () {
# v.1.4
# get pid from exported agent
_SSHPID () { awk -F'=|;' '/SSH_AGENT_PID/ {print $2}' <$HOME/.ssh/.ssh-agent ; }
_BLU "### [dont] Kill the ssh-agent !"
_MYECHO "Find Agent pid"
if [ -z "$SSH_AGENT_PID" ]; then
  if [ -z "$(_SSHPID)" ]; then
    _KO ":NotFound"
  else
    export SSH_AGENT_PID=$(_SSHPID)
  fi
  if [ ! -z "$SSH_AGENT_PID" ]; then
    if ps aux |grep -q $SSH_AGENT_PID; then _OK ":pid=$SSH_AGENT_PID"; else _KO ":NotRunning"; fi
  fi
else
  [ "$SSH_AGENT_PID" != "$(_SSHPID)" ] && export SSH_AGENT_PID=$(_SSHPID)
  if ps aux |grep -q $SSH_AGENT_PID; then _OK ":pid=$SSH_AGENT_PID"; else _KO ":NotRunning"; fi
fi
_MYECHO "Remove Key"
if ssh-add -D &>/dev/null; then _OK; else _KO ":NoKey"; fi
_MYECHO "Kill Agent"
if ssh-agent -k &>/dev/null; then _OK; else _KO; fi
if [ -e ${SSH_AUTH_SOCK} ]; then
  _MYECHO "Remove remaining Socket"
  shred -zvu $SSH_AUTH_SOCK &>/dev/null && _OK || _KO
fi
if ps --user $(id -u) -F|grep -v grep|grep -q ssh-agent; then
_MAV "### Search remaining agent for $(id -un)"
for _PROCESSID in $(ps --no-header --user $(id -u) -F|grep -v grep|grep ssh-agent|awk '{print $2}'); do
  # cry if root user
  [ $(id -u) -eq 0 ] && _RED "Root user detected, CAUTION.."
  # stop if pid not own by user
  ps -p $_PROCESSID -F|grep -v grep|grep ssh-agent|awk '{print $1}'|grep -q $(id -un) || continue
  # stop if pid not numeric
  [[ "$_PROCESSID" =~ ^[0-9]+$ ]] || continue
  _RED "/!\ Check if PID match user ssh agent:"
  ps -p $i -F
  _RED "> kill PID $i ? [Y/n]"
  read -s -n1
  if [[ "$REPLY" =~ [Yy] ]]; then
    kill -9 $i
  fi
done
# unset ssh vars
rm -f $HOME/.ssh/.ssh-agent &>/dev/null
unset $SSH_AUTH_SOCK
unset $SSH_AGENT_PID
fi
echo
}

