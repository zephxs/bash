#!/bin/bash
### Ssh agent user wide loader
### Usefull functions like myecho
### and color bash scheme 
# used as .bash_profile 


                                                           
### colors
_REZ="\e[39m"
_RDX="\e[1;31m"
_BLX="\e[34m"                                              
_GRX="\e[32m"
_MVX="\e[95m"
_BLU () { echo -e "${_BLX}${@}${_REZ}" ; }
_RED () { echo -e "${_RDX}${@}${_REZ}" ; }
_GRN () { echo -e "${_GRX}${@}${_REZ}" ; }
_MAV () { echo -e "${_MVX}${@}${_REZ}" ; }
_OK () { echo -e "[${_GRX}OK${_REZ}${@}]" ; }
_KO () { echo -e "[${_RDX}KO${_REZ}${@}]" ; }




### Bourne Again Functions

_DIE () { echo $1; exit 1; }


### PS1 User set for system wide bashrc (>/etc/bashrc) 
# change PS1 var if root (toilet line can be commented or remove as toilet is used for ascii art ^^)
if [ $(id -u) -eq 0 ];
then
    PS1='\[\033[1;30m\][\[\033[1;32m\]\u\[\033[1;30m\]@\[\033[0;34m\]\h\[\033[1;30m\]] \[\033[0;36m\]\w \[\033[1;30m\]#\[\033[0m\]'
    toilet -f smslant --metal "# root user #" && echo
else
    PS1='\[\033[1;30m\][\[\033[1;34m\]\u\[\033[1;30m\]@\[\033[0;35m\]\h\[\033[1;30m\]] \[\033[0;36m\]\w \[\033[1;30m\]$\[\033[0m\]'
    toilet -f smslant --gay "$USER"
fi


### Myecho BV@R
_MYECHO () {
  _DOTNUM=40
  if [ -z "$1" ]; then echo "<!> need argument"; return 1; fi
  _CHAINL=$(echo $@ | wc -c)
  _DOTL=$((_DOTNUM - _CHAINL))
  echo -e "$@\c"
  i=0
  while [ "$i" -lt "$_DOTL" ]; do
    echo -e ".\c"
    i=$((i+1))
  done
  return 0
}



### SSH AGENT SESSION LOADER
_CHKSSH () {
# v1.4

# USER CHOICE
# export fixed agent socket and default key to load with agent
# set key life time in the agent when loading
export SSH_AUTH_SOCK="$HOME/.ssh/ssh-agent.sock"
_MYSKEY="$HOME/.ssh/k2"
_TIME="28800"



# get agent status from ssh-add exit code
_SSHAG () { ssh-add -l 2>/dev/null >/dev/null ; _RES=$? ; }
_SSHAG
while [ "$(echo $_RES)" -ge 1 ]; do
  case $_RES in
  2)
    ssh-agent -a $SSH_AUTH_SOCK >$HOME/.ssh/.ssh-agent
    echo
    _MYECHO "### Test SSH agent "
    sleep 1 && _SSHAG
    if [ "$(echo $_RES)" = 2 ]; then
      _KO .NotLoaded && rm -f $SSH_AUTH_SOCK
    elif [ "$(echo $_RES)" = 1 ]; then
      _OK .Starting && _SSHAG
    fi
    ;;
  1)
    _MYECHO "### Check Keys "
    _KO .none
    _BLU "> Add default ssh key ? [Y/n]"
    read -s -n1
    if [[ "$REPLY" =~ [Yy] ]]; then
      [ -z "$_TIME" ] && ssh-add -q ${_MYSKEY} || ssh-add -t $_TIME ${_MYSKEY}
      _SSHAG
    else
      _MYECHO "### Loaded SSH keys " && _KO
      echo && return 0
    fi
    ;;
  *)
    _RED "### Unknown return code.. exit"
    return 0
    ;;
  esac
done
echo
_BLU "####################################################"
_MYECHO "### Test SSH Agent "
[ $_RES = 0 ] && _OK .Running || _KO
_KEY=$(ssh-add -l|awk -F/ '{print $NF}'|awk '{print $1}')
_MYECHO "### Loaded SSH keys " && _OK .${_KEY}
echo
echo
}
_CHKSSH


# set 'sshagent-kill' function to remove key, kill agents linked to our socket if more than one and remove socket

_SSHPID () { cat $HOME/.ssh/.ssh-agent|grep _PID|awk -F'[=;]' '{print $2}' ; }
sshagent-kill () {
export SSH_AGENT_PID=$(_SSHPID)
_BLU "####################################################"
_BLU "####### ssh-agent Killer"
_MYECHO "### Find Agent pid "
$(_SSHPID) && _OK || _KO
_MYECHO "### Remove Key "
ssh-add -D && _OK || _KO
ssh-agent -k && (_MYECHO "### Kill Agent " _OK) || _KO
_MYECHO "### Remove Socket "
rm -f $SSH_AUTH_SOCK && _OK || _KO
_MAV "### Search remaining agent "
for i in $(ps -u $(id -un)|grep ssh-agent|awk '{print $1}'); do
 ps aux -q $i
    _RED "> kill PID ? [Y/n]"
    read -s -n1
    if [[ "$REPLY" =~ [Yy] ]]; then
    kill -9 $i
    fi
done
}
sshagent-kill-old () {
export SSH_AGENT_PID=$(_SSHPID)
ssh-add -D; ssh-agent -k; rm -f $SSH_AUTH_SOCK
for i in $(ps -u $(id -un)|grep ssh-agent|grep -v grep|awk '{print $1}'); do
kill -9 $i
done
}

