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
_LINENUMBER=''
_TAG=''

_USAGE () {
_BLU "Generate options:"
echo -e "default 	= Dot line"
echo -e "${_BLX}#${_REZ} [text] .................[/wait]"
echo
echo -e "-e|--equal 	= space line then equal sign"
echo -e "${_BLX}#${_REZ} [text]                = [/wait]"
echo
echo -e "-p|--print 	= Text after one blue Hashtag"
echo -e "${_BLX}#${_REZ} [text]"
echo
echo -e "-t|--title 	= Centered Title"
echo -e "${_BLX}#############${_REZ} [text] ${_BLX}############${_REZ}"
echo
echo -e "-l|--line 	= Hashtag colored line"
echo -e "${_BLX}#################################${_REZ}"
echo
echo -e "-n|--number XX	= Max Lengh number"
echo; echo
echo "Exemple: '_MYECHO -n 50 -e \"My IP\" && myip'"
echo -e "${_BLX}#${_REZ} My IP                 = 73.74.38.1"
echo
echo "*** [/wait] means line does not end (scripting purposes)"
return 1
}


while (( "$#" )); do
  case "$1" in
  -n|--num) 
    if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
    _LINENUMBER="$2"
    shift 2
    else
    echo "Argument missing.." >&2; _USAGE
    fi
    ;;
  -t|--title) _TAG='title'; shift 1 ;;
  -l|--line) _TAG='hashtag'; shift 1 ;;
  -e|--equal) _TAG='equal'; shift 1 ;;
  -p|--print) _TAG='print'; shift 1 ;;
  -h|--help) _USAGE; return 1 ;;
  -*|--*) echo "Flag not recognised.." >&2; _USAGE ;;
  *) _MSG="${1}"; shift ;;
  esac
done
#[ -z "$1" ] && { echo "Missing arguments.."; _USAGE; }
[ -z "$_LINENUMBER" ] && _LINENUMBER=51
[ -z "$_TAG" ] && _TAG='dot'
_LINEHALF=$((_LINENUMBER / 2))
_CHAINL=$(echo "${_MSG}" | wc -c)


#_BLUHTAG (){ echo -e "${_BLX}#${_REZ} $@"; }


if [ "$_TAG" = 'dot' ]; then
[ -z "$_MSG" ] && { echo "Missing message.."; _USAGE; }
  _CHAINLENGH=$((_CHAINL + 2))
  _LINE=$((_LINEHALF - _CHAINLENGH))
  echo -e "${_BLX}#${_REZ} ${_MSG} \c";
  i=0
  while [ "$i" -lt "$_LINE" ]; do
    echo -e ".\c"
    i=$((i+1))
  done
  return 0
fi

if [ "$_TAG" = 'hashtag' ]; then
  echo -e "${_BLX}\c"
  i=0
  while [ "$i" -lt "$_LINENUMBER" ]; do
    echo -e "#\c"
    i=$((i+1))
  done
  echo -e "${_REZ}"
  return 0
fi

if [ "$_TAG" = 'equal' ]; then
[ -z "$_MSG" ] && { echo "Missing message.."; _USAGE; }
  _CHAINLENGH=$((_CHAINL + 3))
  _LINE=$((_LINEHALF - _CHAINLENGH));
  echo -e "${_BLX}#${_REZ} ${_MSG}\c";
  i=0;
  while [ "$i" -lt "$_LINE" ]; do
      echo -e " \c";
      i=$((i+1));
  done;
  echo -e "= \c"
  return 0
fi

if [ "$_TAG" = 'title' ]; then
[ -z "$_MSG" ] && { echo "Missing message.."; _USAGE; }
_CHAINHTL=$(echo "$_MSG" | wc -c)
_CHAINLENGH=$((_CHAINHTL + 1))
_HTL=$((_LINENUMBER - _CHAINLENGH))
_HTL2=$((_HTL / 2))
_HTL3=$((_LINENUMBER - _CHAINLENGH - _HTL2))
i=0
while [ "$i" -lt "$_HTL2" ]; do
 echo -e "${_BLX}#${_REZ}\c"
 i=$((i+1))
done
echo -e " ${_BLX}${_MSG}${_REZ} \c"
i=0
while [ "$i" -lt "$_HTL3" ]; do
 echo -e "${_BLX}#${_REZ}\c"
 i=$((i+1))
done
echo
return 0
fi


if [ "$_TAG" = 'print' ]; then
echo -e "${_BLX}#${_REZ} $_MSG"
fi

}
