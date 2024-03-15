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
_WHT () { echo -e "${_REZ}${@}" ; }
_OK () { echo -e "[${_GRX}OK${_REZ}${@}]" ; }
_KO () { echo -e "[${_RDX}KO${_REZ}${@}]" ; }

_MYECHO () {
##### Generate Formatted Output
### v1.3 - removed tput for box without ncurses
# Idea from LinuxGuru Bruno V. @R0 ; ]

_TAG=''
_MSG=''
if [ -z "$_LINELENGH" -a -f "$HOME/.myechorc" ]; then
  source $HOME/.myechorc
fi

_USAGE () {
_BLU "Generate options:"
echo -e "	-b|--blank 	= Blank line (Default)"
echo -e "${_BLX}#${_REZ} [text]                            ${_BLK}[/wait]${_REZ}"
echo
echo -e "	-d|--dot 	= Dot line"
echo -e "${_BLX}#${_REZ} [text] ...........................${_BLK}[/wait]${_REZ}"
echo
echo -e "	-e|--equal 	= space line and equal"
echo -e "${_BLX}#${_REZ} [text]                          = ${_BLK}[/wait]${_REZ}"
echo
echo -e "	-p|--print 	= Colorize Text and return"
echo -e "${_BLX}[test text !]${_REZ}"
echo
echo -e "	-s|--start 	= Start with colorized hashtag, Text and return"
echo -e "${_BLX}#${_REZ}[test text !]"
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
echo -e "	Available: ${_WHT}'white' ${_BLX}'blue' ${_GRX}'green' ${_RDX}'red' ${_MVX}'purple'${_REZ} and ${_BLK}'blink'${_REZ}"
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
      echo "$2 Line lengh missing.."; return
    fi
    ;;
  -c|--color) 
    if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
      _COLORCHOICE="$2"
      shift 2
    fi
    ;;
  -t|--title) _TAG='title'; shift 1 ;;
  -l|--line) _TAG='hashtag'; shift 1 ;;
  -d|--dot) _TAG='dot'; shift 1 ;;
  -e|--equal) _TAG='equal'; shift 1 ;;
  -b|--blank) _TAG='blank'; shift 1 ;;
  -s|--start) _TAG='start'; shift 1 ;;
  -p|--print) _TAG='print'; shift 1 ;;
  -h|--help) _USAGE; return 1 ;;
  #-*|--*) echo "Flag not recognised.." >&2; _USAGE; return ;;
  *) _MSG="${_MSG}${1}"; shift ;;
  esac
done

# tag settings
[ -z "$_TAG" ] && _TAG='equal'

# Length settings
if [ -z "$_LINELENGH" ]; then
  if [ -n "$COLUMNS" ]; then
    _LINELENGH=$((COLUMNS/2))
  else
    _LINELENGH=56
  fi
else
  if [ -n "$COLUMNS" ] && [ "$_LINELENGH" -gt "$COLUMNS" ]; then
    _LINELENGH=$((COLUMNS/2))
  fi
fi

#  color settings
[ -z "$_COLORCHOICE" ] && _COLORCHOICE='blue'
if [ ! -z "$_COLORCHOICE" ]; then 
  case "${_COLORCHOICE}" in
	  white) _COLOR="${_WHT}";;
	  blue) _COLOR="${_BLX}";;
	  green) _COLOR="${_GRX}";;
	  red) _COLOR="${_RDX}";;
          purple) _COLOR="${_MVX}";;
          blink) _COLOR="${_BLK}";;
          *) _COLOR="${_BLX}";;
  esac
fi

# set end of dot line @ 2/3 of line lengh
_LINEHALF=$((_LINELENGH/5*3))
_CHAINL=$(echo "${_MSG}" | wc -c)

case "${_TAG}" in
  'blank')
  [ -z "$_MSG" ] && { echo "Message missing.."; return; }
  _CHAINLENGH=$((_CHAINL + 2))
  _LINE=$((_LINEHALF - _CHAINLENGH))
  echo -e "${_COLOR}#${_REZ} ${_MSG} \c"
  _NVALUE=0
  while [ "$_NVALUE" -lt "$_LINE" ]; do
    echo -e " \c"
    _NVALUE=$((_NVALUE+1))
  done
  return 0
  ;;
  'dot')
  [ -z "$_MSG" ] && { echo "Message missing.."; return; }
  _CHAINLENGH=$((_CHAINL + 2))
  _LINE=$((_LINEHALF - _CHAINLENGH))
  echo -e "${_COLOR}#${_REZ} ${_MSG} \c"
  _NVALUE=0
  while [ "$_NVALUE" -lt "$_LINE" ]; do
    echo -e ".\c"
    _NVALUE=$((_NVALUE+1))
  done
  return 0
  ;;
  'equal')
  [ -z "$_MSG" ] && { echo "Message missing.."; return; }
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
  ;;
  'title')
  [ -z "$_MSG" ] && { echo "Message missing.."; return; }
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
  ;;
  'hashtag')
  echo -e "${_COLOR}\c"
  _NVALUE=0
  while [ "$_NVALUE" -lt "$_LINELENGH" ]; do
    echo -e "#\c"
    _NVALUE=$((_NVALUE+1))
  done
  echo -e "${_REZ}"
  return 0
  ;;
  'print')
  [ -z "$_MSG" ] && { echo "Message missing.."; return; }
  echo -e "${_COLOR}${_MSG}${_REZ}"
  ;;
  'start')
  [ -z "$_MSG" ] && { echo "Message missing.."; return; }
  echo -e "${_COLOR}#${_REZ} ${_MSG}"
  ;;
esac
}

alias myecho='_MYECHO'
