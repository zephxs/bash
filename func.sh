#!/bin/bash
### Ssh agent user wide loader
### Usefull functions like myecho
### and color bash scheme 
# used as .bash_profile 

alias x='ssh-add -D; rm -f $SSH_AUTH_SOCK && exit'
_DIE () { echo $1; exit 1; }
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

                                                           ### colors
_REZ="\e[39m"
_RDX="\e[1;31m"
_BLX="\e[34m"                                              _GRX="\e[32m"
_MVX="\e[95m"
_BLU () { echo -e "${_BLX}${@}${_REZ}" ; }
_RED () { echo -e "${_RDX}${@}${_REZ}" ; }
_GRN () { echo -e "${_GRX}${@}${_REZ}" ; }
_MAV () { echo -e "${_MVX}${@}${_REZ}" ; }
_OK () { echo -e "[${_GRX}OK${_REZ}${@}]" ; }
_KO () { echo -e "[${_RDX}KO${_REZ}${@}]" ; }

_MAV "##################################"
df|grep emul|awk '{print "LocalStorage = #Total="$2" #Free="$4" #Used="$3}'
echo "HomeDir = $HOME"
echo
export SSH_AUTH_SOCK="/data/data/com.termux/files/home/.ssh/zeph.agent.sock"
#rm -f $SSH_AUTH_SOCK
#eval $(ssh-agent)


_CHKSSH () {
#set -x
_SSHAG () { ssh-add -l 2>/dev/null >/dev/null ; _RES=$? ; }
_SSHAG
while [ "$(echo $_RES)" -ge 1 ]; do
  case $_RES in
  2)
    ssh-agent -a $SSH_AUTH_SOCK >/dev/null
    echo
    _MYECHO "### Test SSH agent "
    sleep 1 && _SSHAG
    if [ "$(echo $_RES)" = 2 ]; then
      _KO .NotLoaded && rm -f $SSH_AUTH_SOCK
    elif [ "$(echo $_RES)" = 1 ]; then
      _OK && _SSHAG
    fi
    ;;
  1)
    _MYECHO "### Check Keys "
    _KO .none
    _BLU "> Add K2 ssh key ? [Y/n]"
    read -s -n1
    if [[ "$REPLY" =~ [Yy] ]]; then
      ssh-add -q ~/.ssh/k2
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
_BLU "##################################"
_MYECHO "### Test SSH Agent "
[ $_RES = 0 ] && _OK .Running || _KO
_KEY=$(ssh-add -l|awk -F/ '{print $NF}'|awk '{print $1}')
_MYECHO "### Loaded SSH keys " && _OK .${_KEY}
echo
echo
}
_CHKSSH
