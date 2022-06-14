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
_LINELENGH='91'
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
echo
echo -e "-c|--color xxx	= Max Lengh number"
echo -e "Available colors: 'blue' 'green' 'red' and 'purple'"
echo; echo
echo "Exemple: '_MYECHO -n 50 -e \"My IP\" && myip'"
echo -e "${_BLX}#${_REZ} My IP                 = 73.74.38.1"
echo
echo "*** [/wait] means line does not end (scripting purposes)"
return;
}


while (( "$#" )); do
  case "$1" in
  -n|--num) 
    if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
    _LINELENGH="$2"
    shift 2
    else
    echo "Line lengh missing.." >&2; _USAGE; return
    fi
    ;;
  -c|--color) 
	  if [ -n "$2" ] && [ ${2:0:1} != "-" ] && [[ "$2" = @(blue|green|purple|red) ]]; then
    _COLORCHOICE="$2"
    shift 2
    else
    echo "Color unknown.." >&2; _USAGE; return
    fi
    ;;
  -t|--title) _TAG='title'; shift 1 ;;
  -l|--line) _TAG='hashtag'; shift 1 ;;
  -d|--dot) _TAG='dot'; shift 1 ;;
  -e|--equal) _TAG='equal'; shift 1 ;;
  -p|--print) _TAG='print'; shift 1 ;;
  -h|--help) _USAGE; return 1 ;;
  -*|--*) echo "Flag not recognised.." >&2; _USAGE; return ;;
  *) _MSG="${1}"; shift ;;
  esac
done

[ -z "$_TAG" ] && _TAG='dot'

# set end of dot line @ 2/3 of line lengh
_LINEHALF=$((_LINELENGH/3*2))
_CHAINL=$(echo "${_MSG}" | wc -c)

if [ ! -z "$_COLORCHOICE" ]; then 
  [ "$_COLORCHOICE" = blue ] && _COLOR="${_BLX}"
  [ "$_COLORCHOICE" = green ] && _COLOR="${_GRX}"
  [ "$_COLORCHOICE" = red ] && _COLOR="${_RDX}"
  [ "$_COLORCHOICE" = purple ] && _COLOR="${_MVX}"
else	
 _COLOR="${_BLX}"
fi

if [ "$_TAG" = 'dot' ]; then
[ -z "$_MSG" ] && { echo "Missing message.."; _USAGE; }
  _CHAINLENGH=$((_CHAINL + 2))
  _LINE=$((_LINEHALF - _CHAINLENGH))
  echo -e "${_COLOR}#${_REZ} ${_MSG} \c";
  i=0
  while [ "$i" -lt "$_LINE" ]; do
    echo -e ".\c"
    i=$((i+1))
  done
  return 0
fi


if [ "$_TAG" = 'equal' ]; then
[ -z "$_MSG" ] && { echo "Missing message.."; _USAGE; }
  _CHAINLENGH=$((_CHAINL + 3))
  _LINE=$((_LINEHALF - _CHAINLENGH));
  echo -e "${_COLOR}#${_REZ} ${_MSG}\c";
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
_CHAINLENGH=$((_CHAINL + 1))
_HTL=$((_LINELENGH - _CHAINLENGH))
_HTL2=$((_HTL /2))
_HTL3=$((_LINELENGH - _CHAINLENGH - _HTL2))
i=0
while [ "$i" -lt "$_HTL2" ]; do
 echo -e "${_COLOR}#${_REZ}\c"
 i=$((i+1))
done
echo -e " ${_COLOR}${_MSG}${_REZ} \c"
i=0
while [ "$i" -lt "$_HTL3" ]; do
 echo -e "${_COLOR}#${_REZ}\c"
 i=$((i+1))
done
echo
return 0
fi

if [ "$_TAG" = 'hashtag' ]; then
  echo -e "${_COLOR}\c"
  i=0
  while [ "$i" -lt "$_LINELENGH" ]; do
    echo -e "#\c"
    i=$((i+1))
  done
  echo -e "${_REZ}"
  return 0
fi


if [ "$_TAG" = 'print' ]; then
echo -e "${_COLOR}#${_REZ} $_MSG"
fi

}
