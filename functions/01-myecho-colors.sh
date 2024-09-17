### colors
export _REZ='\e[0m'
export _BLK='\033[5m'
export _RDX='\e[1;31m'
export _BLX='\e[1;34m'
export _GRX='\e[1;32m'
export _MVX='\e[1;95m'
export _ORX='\e[38;5;208m'
_BLINK () { echo -e "${_BLK}${@}${_REZ}" ; }
_BLU () { echo -e "${_BLX}${@}${_REZ}" ; }
_RED () { echo -e "${_RDX}${@}${_REZ}" ; }
_GRN () { echo -e "${_GRX}${@}${_REZ}" ; }
_MAV () { echo -e "${_MVX}${@}${_REZ}" ; }
_ORA () { echo -e "${_ORX}${@}${_REZ}" ; }
_WHT () { echo -e "${_REZ}${@}" ; }
_OK () { echo -e "[${_GRX}OK${_REZ}${@}]" ; }
_KO () { echo -e "[${_RDX}KO${_REZ}${@}]" ; }


_MYECHO () {
##### Generate Formatted Output
### v1.3 - removed tput for box without ncurses
# Idea from LinuxGuru Bruno V. @R0 ; ]

local _TAG=''
local _MSG=''

# Length settings: write .myechorc with 2/3 screen lengh by default or "56" if $COLUMNS not set
if [ -f "$HOME/.myechorc" ]; then
  source $HOME/.myechorc
fi

if [ -z "$_LINELENGH" ]; then
  if [ -n "$COLUMNS" ]; then
    echo "_LINELENGH=$((COLUMNS/2))" >$HOME/.myechorc
  else
    echo "_LINELENGH=56" >$HOME/.myechorc
  fi
else
  if [ -n "$COLUMNS" ] && [ "$_LINELENGH" -gt "$COLUMNS" ]; then
    _LINELENGH=$((COLUMNS/2))
  fi
fi

_MYECHO_USAGE () {
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
  -t|--title) local _TAG='title'; shift 1 ;;
  -l|--line) local _TAG='hashtag'; shift 1 ;;
  -d|--dot) local _TAG='dot'; shift 1 ;;
  -e|--equal) local _TAG='equal'; shift 1 ;;
  -b|--blank) local _TAG='blank'; shift 1 ;;
  -s|--start) local _TAG='start'; shift 1 ;;
  -p|--print) local _TAG='print'; shift 1 ;;
  -h|--help) _MYECHO_USAGE; return 1 ;;
  *) local _MSG="${_MSG}${1}"; shift ;;
  esac
done

# Tag default settings
[ -z "$_TAG" ] && local _TAG='equal'

# Color settings
[ -z "$_COLORCHOICE" ] && _COLORCHOICE='blue'
if [ ! -z "$_COLORCHOICE" ]; then 
  case "${_COLORCHOICE}" in
    w*|white) local _COLOR="${_WHT}";;
    b*|blue) local _COLOR="${_BLX}";;
    g*|green) local _COLOR="${_GRX}";;
    r*|red) local _COLOR="${_RDX}";;
    p*|purple) local _COLOR="${_MVX}";;
    o*|orange) local _COLOR="${_ORX}";;
    B|blink) local _COLOR="${_BLK}";;
    *) local _COLOR="${_BLX}";;
  esac
fi

# Set end of dot line @ 3/5 of line lengh
local _LINEHALF=$((_LINELENGH/5*3))
# Get char num
local _CHAINL=$(echo "${_MSG}" | wc -c)

case "${_TAG}" in
  'blank')
    [ -z "$_MSG" ] && { echo "Message missing.."; return; }
    local _CHAINLENGH=$((_CHAINL + 2))
    local _LINE=$((_LINEHALF - _CHAINLENGH))
    echo -e "${_COLOR}#${_REZ} ${_MSG} \c"
    local _NVALUE=0
    while [ "$_NVALUE" -lt "$_LINE" ]; do
      echo -e " \c"
      local _NVALUE=$((_NVALUE+1))
    done
    return 0
    ;;
  'dot')
    [ -z "$_MSG" ] && { echo "Message missing.."; return; }
    local _CHAINLENGH=$((_CHAINL + 2))
    local _LINE=$((_LINEHALF - _CHAINLENGH))
    echo -e "${_COLOR}#${_REZ} ${_MSG} \c"
    local _NVALUE=0
    while [ "$_NVALUE" -lt "$_LINE" ]; do
      echo -e ".\c"
      local _NVALUE=$((_NVALUE+1))
    done
    return 0
    ;;
  'equal')
    [ -z "$_MSG" ] && { echo "Message missing.."; return; }
    local _CHAINLENGH=$((_CHAINL + 3))
    local _LINE=$((_LINEHALF - _CHAINLENGH));
    echo -e "${_COLOR}#${_REZ} ${_MSG}\c";
    local _NVALUE=0;
    while [ "$_NVALUE" -lt "$_LINE" ]; do
      echo -e " \c"
      local _NVALUE=$((_NVALUE+1))
    done
    echo -e "= \c"
    return 0
    ;;
  'title')
    [ -z "$_MSG" ] && { echo "Message missing.."; return; }
    local _CHAINLENGH=$((_CHAINL + 1))
    local _HTL=$((_LINELENGH - _CHAINLENGH))
    local _HTL2=$((_HTL /2))
    local _HTL3=$((_LINELENGH - _CHAINLENGH - _HTL2))
    local _NVALUE=0
    while [ "$_NVALUE" -lt "$_HTL2" ]; do
      echo -e "${_COLOR}#${_REZ}\c"
      local _NVALUE=$((_NVALUE+1))
    done
    echo -e " ${_COLOR}${_MSG}${_REZ} \c"
    local _NVALUE=0
    while [ "$_NVALUE" -lt "$_HTL3" ]; do
      echo -e "${_COLOR}#${_REZ}\c"
      local _NVALUE=$((_NVALUE+1))
    done
    echo
    return 0
    ;;
  'hashtag')
    echo -e "${_COLOR}\c"
    local _NVALUE=0
    while [ "$_NVALUE" -lt "$_LINELENGH" ]; do
      echo -e "#\c"
      local _NVALUE=$((_NVALUE+1))
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
