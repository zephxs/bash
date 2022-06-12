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
  _DOTNUM=30
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
    _DOTNUM=16;
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

_GENHTAG (){ echo -e "${_BLX}###################################################${_REZ}"; }
_BLUHTAG (){ echo -e "${_BLX}#${_REZ} $@"; }

_GENTITLE () { 
_HTNUM=52
if [ -z "$1" ]; then
 echo "<!> need argument"
 return 1
fi
_CHAINHTL=$(echo $@ | wc -c)
_CHAINHTL2=$((_CHAINHTL + 2))
_HTL=$((_HTNUM - _CHAINHTL2))
_HTL2=$((_HTL / 2))
i=0
while [ "$i" -lt "$_HTL2" ]; do
 echo -e "${_BLX}#${_REZ}\c"
 i=$((i+1))
done
echo -e " ${_BLX}${@}${_REZ} \c"
i=0
while [ "$i" -lt "$_HTL2" ]; do
 echo -e "${_BLX}#${_REZ}\c"
 i=$((i+1))
done
echo
return 0
}
