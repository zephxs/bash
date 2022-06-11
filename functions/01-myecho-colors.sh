### colors
_REZ="\e[0m"
_RDX="\e[1;31m"
_BLX="\e[1;34m"
_GRX="\e[1;32m"
_MVX="\e[1;95m"
_BLU () { echo -e "${_BLX}${@}${_REZ}" ; }
_RED () { echo -e "${_RDX}${@}${_REZ}" ; }
_GRN () { echo -e "${_GRX}${@}${_REZ}" ; }
_MAV () { echo -e "${_MVX}${@}${_REZ}" ; }
_OK () { echo -e "[${_GRX}OK${_REZ}${@}]" ; }
_KO () { echo -e "[${_RDX}KO${_REZ}${@}]" ; }

# ty BV @R0 ; ]
_MYECHO () {
  _DOTNUM=50
  if [ -z "$1" ]; then echo "<!> need argument"; return 1; fi
  _CHAINL=$(echo $@ | wc -c)
  _DOTL=$((_DOTNUM - _CHAINL))
  echo -e "${_BLX}#${_REZ} $@\c";
  i=0
  while [ "$i" -lt "$_DOTL" ]; do
    echo -e ".\c"
    i=$((i+1))
  done
  return 0
}

_GENEQUAL () {
    _DOTNUM=20;
    if [ -z "$1" ]; then
        echo "<!> need argument";
        return 1;
    fi;
    _CHAINL=$(echo $@ | wc -c);
    _DOTL=$((_DOTNUM - _CHAINL));
    echo -e "${_BLX}#${_REZ} $@\c";
    i=0;
    while [ "$i" -lt "$_DOTL" ]; do
        echo -e " \c";
        i=$((i+1));
    done;
    echo -e "= \c"
    return 0
}
