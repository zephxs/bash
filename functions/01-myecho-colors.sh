### colors
_REZ='\e[0m'
_BLK='\033[5m'
_RDX='\e[1;31m'
_BLX='\e[1;34m'
_GRX='\e[1;32m'
_MVX='\e[1;95m'
_BLINK () { echo -e "${_BLK}${@}${_REZ}" ; }
_BLU () { echo -e "${_BLX}${@}${_REZ}" ; }
_RED () { echo -e "${_RDX}${@}${_REZ}" ; }
_GRN () { echo -e "${_GRX}${@}${_REZ}" ; }
_MAV () { echo -e "${_MVX}${@}${_REZ}" ; }
_OK () { echo -e "[${_GRX}OK${_REZ}${@}]" ; }
_KO () { echo -e "[${_RDX}KO${_REZ}${@}]" ; }

_MYECHO () {
### Generate Formatted Output
# Idea from LinuxGuru Bruno V. @R0 ; ]
# v1.2 - added tput cols for controlling line lengh
# v1.1 - added colors
# v1.0 - line lengh added


# base settings
[ -f "$HOME/.myechorc" ] && source $HOME/.myechorc
if [ "$(tput cols)" -lt "84" ]; then
_LINELENGH="$(tput cols)"
fi
[ -z "$_COLORCHOICE" ] && _COLORCHOICE='blue'
_TAG=''
_MSG=''

_USAGE () {
_BLU "Generate options:"
echo -e "	-d|--dot 	= Dot line (default)"
echo -e "${_BLX}#${_REZ} [text] ...........................${_BLK}[/wait]${_REZ}"
echo
echo -e "	-e|--equal 	= space line then equal sign"
echo -e "${_BLX}#${_REZ} [text]                          = ${_BLK}[/wait]${_REZ}"
echo
echo -e "	-p|--print 	= Colorize Text and return"
echo -e "${_BLX}[test text !]${_REZ}"
echo
echo -e "	-t|--title 	= Centered Title"
echo -e "${_BLX}##################${_REZ} [text] ${_BLX}#################${_REZ}"
echo
echo -e "	-l|--line 	= Hashtag colored line"
echo -e "${_BLX}###########################################${_REZ}"
echo
echo -e "	-n|--number XX	= Max Lengh number"
echo
echo -e "	-c|--color xxx	= choose color (default 'blue')"
echo -e "	Available: ${_BLX}'blue' ${_GRX}'green' ${_RDX}'red' ${_MVX}'purple'${_REZ} and also ${_BLK}'blink'${_REZ}"
echo; echo
echo "Exemple: 'myecho \"My Dir\" && pwd'"
echo -e "${_BLX}#${_REZ} My Dir ...................................../mnt/resources"
echo
echo "Exemple: '_MYECHO -n 50 -e \"My IP\" && myip'"
echo -e "${_BLX}#${_REZ} My IP                 = 73.74.38.1"
echo
echo -e "*** ${_BLK}[/wait]${_REZ} means line does not end (scripting purposes)"
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
    if [ -n "$2" ] && [ ${2:0:1} != "-" ] && [[ "$2" = @(blue|green|purple|red|blink) ]]; then
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
  #-*|--*) echo "Flag not recognised.." >&2; _USAGE; return ;;
  *) _MSG="${_MSG}${1}"; shift ;;
  esac
done

[ -z "$_TAG" ] && _TAG='dot'


# set end of dot line @ 2/3 of line lengh
_LINEHALF=$((_LINELENGH/5*3))
_CHAINL=$(echo "${_MSG}" | wc -c)

if [ ! -z "$_COLORCHOICE" ]; then 
  [ "$_COLORCHOICE" = blue ] && _COLOR="${_BLX}"
  [ "$_COLORCHOICE" = green ] && _COLOR="${_GRX}"
  [ "$_COLORCHOICE" = red ] && _COLOR="${_RDX}"
  [ "$_COLORCHOICE" = purple ] && _COLOR="${_MVX}"
  [ "$_COLORCHOICE" = blink ] && _COLOR="${_BLK}"
fi

if [ "$_TAG" = 'dot' ]; then
[ -z "$_MSG" ] && { echo "Missing message.."; _USAGE; }
  _CHAINLENGH=$((_CHAINL + 2))
  _LINE=$((_LINEHALF - _CHAINLENGH))
  echo -e "${_COLOR}#${_REZ} ${_MSG} \c"
  _NVALUE=0
  while [ "$_NVALUE" -lt "$_LINE" ]; do
    echo -e ".\c"
    _NVALUE=$((_NVALUE+1))
  done
  return 0
fi


if [ "$_TAG" = 'equal' ]; then
[ -z "$_MSG" ] && { echo "Missing message.."; _USAGE; }
  _CHAINLENGH=$((_CHAINL + 3))
  _LINE=$((_LINEHALF - _CHAINLENGH));
  echo -e "${_COLOR}#${_REZ} ${_MSG}\c";
  _NVALUE=0;
  while [ "$_NVALUE" -lt "$_LINE" ]; do
      echo -e " \c";
      _NVALUE=$((_NVALUE+1));
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
_NVALUE=0
while [ "$_NVALUE" -lt "$_HTL2" ]; do
 echo -e "${_COLOR}#${_REZ}\c"
 _NVALUE=$((_NVALUE+1))
done
echo -e " ${_COLOR}${_MSG}${_REZ} \c"
_NVALUE=0
while [ "$_NVALUE" -lt "$_HTL3" ]; do
 echo -e "${_COLOR}#${_REZ}\c"
 _NVALUE=$((_NVALUE+1))
done
echo
return 0
fi

if [ "$_TAG" = 'hashtag' ]; then
  echo -e "${_COLOR}\c"
  _NVALUE=0
  while [ "$_NVALUE" -lt "$_LINELENGH" ]; do
    echo -e "#\c"
    _NVALUE=$((_NVALUE+1))
  done
  echo -e "${_REZ}"
  return 0
fi


if [ "$_TAG" = 'print' ]; then
echo -e "${_COLOR}${_MSG}${_REZ}"
fi
}

alias myecho='_MYECHO'
