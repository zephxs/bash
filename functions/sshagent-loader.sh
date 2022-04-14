### SSH AGENT SESSION LOADER
sshagent-loader () {
# v1.5 - Personal ssh multi session agent 
# set fixed agent socket and default key to load
# set key life time / empty for not setting lifetime
export SSH_AUTH_SOCK="$HOME/.ssh/ssh-agent.sock"
_MYSKEY="$HOME/.ssh/k2"
_TIME="28800"

# func to get agent status from ssh-add exit code
_SSHAG () { ssh-add -l 2>/dev/null >/dev/null ; _RES=$? ; }
_SSHAG
while [ "$_RES" -ge 1 ]; do
  case $_RES in
  2)
    ssh-agent -a $SSH_AUTH_SOCK >$HOME/.ssh/.ssh-agent
    echo
    _MYECHO "### Test SSH agent "
    sleep 1 && _SSHAG
    if [ "$_RES" = 2 ]; then
      _KO .NotLoaded && rm -f $SSH_AUTH_SOCK
    elif [ "$_RES" = 1 ]; then
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

