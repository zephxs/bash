#!/usr/bin/env bash
##### Simple Yubikey setup script
### v0.10 - Release + added some comments
### v0.09 - take into account already uploaded Yubico ID
### v0.08 - adapted to French locale
### v0.07 - POC : Factory Reset / Admin PIN / User PIN / Private Key Generation / Yubico Upload csv

# PreCheck 'rbw' > Bitwarden CLI
type rbw >/dev/null 2>&1 || { echo "rbw missing..

# Install 'rbw' before using this script
brew install rbw

# set default config
rbw config show
rbw config set email myemail@my.com
rbw config set sso_id CORPID
rbw config set base_url https://bw.corp.com
rbw config set ui_url https://bw.corp.com

# Set alternate passwd prompt (ex pinentry-mac to have the Gui)
rbw config set pinentry pinentry-mac

# Go to Bitwarden web > Settings > Security > onglet "Keys", then click on "View API Key" to get your client_key_id and client_secret
# Init and sync db
rbw register
rbw sync
rbw unlock

# Show all available entries
rbw ls
"; exit 1; }

### VARS
_USER_PIN='123456' 					# User default PIN
_TMPSCR="$HOME/gpg-check.sh"				# auto generated script used for gpg command-fd
_TMPCSV="$HOME/upload-yubi.csv"				# auto generated csv file
_CARD_SERIAL="$(gpg --card-status | awk -F': ' '/Serial number/ {print $NF}')"
_CARD_VERSION="$(gpg --card-status |awk -F': ' '/Version/ {print $NF}')"
_CARD_MANUFACT="$(gpg --card-status |awk -F': ' '/Manufacturer/ {print $NF}')"
_LOG_FILE="$HOME/$(basename -s '.sh' $0).log"
_VERS="$(awk '/### v/ {print $0; exit}' $(basename $0) |awk '{print $2}')"

# Log func
_LOG(){
# _LOG "WARNING" "message"
local _LEVEL="$1"
local _MESSAGE="$2"
local _TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
printf "[${_TIMESTAMP}] [SN:$_CARD_SERIAL] [${_LEVEL}] ${_MESSAGE}\n" >>$_LOG_FILE
}

# colors and myecho
export _REZ='\033[0m'
export _BLK='\033[5m'
export _RDX='\033[1;31m'
export _BLX='\033[1;34m'
export _GRX='\033[1;32m'
export _MVX='\033[1;95m'
export _ORX='\033[38;5;208m'
_BLINK () { echo -e "${_BLK}${@}${_REZ}" ; }
_BLU () { echo -e "${_BLX}${@}${_REZ}" ; }
_RED () { echo -e "${_RDX}${@}${_REZ}" ; }
_GRN () { echo -e "${_GRX}${@}${_REZ}" ; }
_MAV () { echo -e "${_MVX}${@}${_REZ}" ; }
_ORA () { echo -e "${_ORX}${@}${_REZ}" ; }
_WHT () { echo -e "${_REZ}${@}" ; }
_OK () { echo -e "[${_GRX}OK${_REZ}${@}]" ; }
_KO () { echo -e "[${_RDX}KO${_REZ}${@}]" ; }

_MYECHO(){
_DOTNUM='54'
if [ -z "$1" ]; then echo "<!> need argument"; return 1; fi
_CHAINL=$(echo $@ | wc -c)
_DOTL=$((_DOTNUM - _CHAINL))
i=0
echo -e "${_BLX}#${_REZ} $@\c"
while [ "$i" -lt "$_DOTL" ]; do echo -e " \c"; i=$((i+1)); done
echo -e "= \c"
return 0
}

_BLU "###################### Yubikey tools # $_VERS ######################"
while (( $# )); do
  case $1 in
    -p|--pin) _CHANGE_ADMIN_PIN=1; shift ;;
    -u|--user) _CHANGE_USER=1; shift ;;
    -i|--id) _CHANGE_ID=1; shift ;;
    -r|--rsa) _CHANGE_RSA=1; shift ;;
    -y|--yubico) _PREP_YUBICO=1; shift ;;
    -a|--all) _CHANGE_ADMIN_PIN=1; _CHANGE_ID=1; _CHANGE_RSA=1; _PREP_YUBICO=1; shift ;;
    -w|--with-user) _CHANGE_ADMIN_PIN=1; _CHANGE_USER=1; _CHANGE_ID=1; _CHANGE_RSA=1; _PREP_YUBICO=1; shift ;;
    -R|--reset) _GRN "# Reset Yubikey to factory"
      ykman openpgp reset
      [ "$?" -ne 0 ] && _LOG "ERROR" "Reset aborted.." || _LOG "OK" "Factory Reset done"
      exit 0
      ;;
    -h|--help) echo "Usage:"
      echo "  -p|--pin           Set Default PIN to VPG PIN"
      echo "  -i|--id            Set Card Owner Identity"
      echo "  -u|--user          Set User PIN"
      echo "  -r|--rsa           Generate User Private Key"
      echo "  -y|--yubico        Prepare Yubico ID Upload csv"
      echo "  -a|--all           All Admin settings: VPG PIN + User ID + Private Key + Upload csv [Default]"
      echo "  -w|--with-user     All Admin settings + User Input"
      echo "  -R|--reset         Reset Yubikey to Factory Default"
      echo "  -h|--help          Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Show selected functions + default if no selection
[ -z "$_CHANGE_ADMIN_PIN" -a -z "$_CHANGE_ID" -a -z "$_CHANGE_RSA" -a -z "$_CHANGE_USER" -a -z "$_PREP_YUBICO" ] && { _CHANGE_ADMIN_PIN=1; _CHANGE_ID=1; _CHANGE_RSA=1; _PREP_YUBICO=1; }
_BLU "### Settings to apply:"
[ "$_CHANGE_ADMIN_PIN" = 1 ] && _MYECHO "Set Admin PIN" && _OK
[ "$_CHANGE_ID" = 1 ] && _MYECHO "Set Key Owner" && _OK
[ "$_CHANGE_RSA" = 1 ] && _MYECHO "Set Rsa key" && _OK
[ "$_CHANGE_USER" = 1 ] && _MYECHO "Set User PIN" && _OK
[ "$_PREP_YUBICO" = 1 ] && _MYECHO "Prepare Yubico Upload" && _OK
read -n1 -p "Start Yubikey Setting [Y/n] = "
echo
[[ "$REPLY" =~ n|no|N|No ]] && exit 0
_LOG "START" "Yubikey v$_CARD_VERSION  - Serial-number=$_CARD_SERIAL  Manufacturer=$_CARD_MANUFACT"

### CORE FUNCTIONS
_GET_ADMIN_PIN(){
[ -z "$_ADMINVPGPIN" ] && _ADMINVPGPIN="$(rbw get "mdp admin yubikey")"		# Get VPG Admin PIN from BW
# consider if Login data not set, default PIN is set and needs to be updated to VPG passwd
if [ "$(gpg --card-status |awk -F': ' '/^Login data/ {print $NF}')" = '[not set]' -o "$(gpg --card-status |awk -F': ' '/^Login data/ {print $NF}')" = '[non positionné]' ]; then
  _GRN "# Admin PIN set to '12345678'"
  return 3
else
  _ADMIN_PIN="$_ADMINVPGPIN"
  _GRN "# Admin PIN set to 'VPG PIN'"
  return 0
fi
}

_ADMIN_PIN_SETTING(){
_BLU "# Set Admin VPG PIN"
_GET_ADMIN_PIN && { echo; return 0; }
[ -z "$_ADMIN_PIN" ] && _ADMIN_PIN="12345678"
# Basic ykman command to set admin pin
ykman openpgp access change-admin-pin -a "$_ADMIN_PIN" -n "$_ADMINVPGPIN"
[ "$?" -ne 0 ] && _LOG "ERROR" "VPG Admin PIN not set.." || _LOG "OK" "set VPG Admin PIN"
echo
}

_USER_ID(){
[ -z "$_ADMINVPGPIN" ] && _ADMINVPGPIN="$(rbw get "mdp admin yubikey")"		# Get VPG Admin PIN from BW
_BLU "# Set User Identity"
# Only User input for setting User ID // see if needed to be added as script param..
read -p "Name [Prenom] = " _USERNAME
read -p "SURNAME [NOM DE FAMILLE] = " _USERSURNAME
read -p "Identity [AD User] = " _IDENTITY
gpg --command-fd=0 --pinentry-mode=loopback --card-edit <<EOF
admin
login
$_IDENTITY
$_ADMINVPGPIN
lang
french
name
$_USERSURNAME
$_USERNAME
quit
EOF
[ "$?" -ne 0 ] && _LOG "ERROR" "Card User ID not set.." || _LOG "OK" "set Card User ID for $_IDENTITY"
echo
}

_RSA_GEN(){
[ -z "$_ADMINVPGPIN" ] && _ADMINVPGPIN="$(rbw get "mdp admin yubikey")"		# Get VPG Admin PIN from BW
_BLU "# Set Private Key"
[ -z "$_USERNAME" ] && _GET_ADMIN_PIN
[ -z "$_USERNAME" ] && _USERNAME="$(gpg --card-status |awk '/^Name of cardholder/ {print $(NF-1)}')"
[ -z "$_USERSURNAME" ] && _USERSURNAME="$(gpg --card-status |awk '/^Name of cardholder/ {print $NF}')"
[ -z "$_IDENTITY" ] && _IDENTITY="$(gpg --card-status |awk '/^Login data/ {print $NF}')"
_USER_FULLNAME="${_USERNAME} ${_USERSURNAME}"
_USER_MAIL="${_IDENTITY}@voyageprive.com"
_COUNT="1"
>$_TMPSCR
# Overkill loop.. as gpg card-edit seems to only require admin PIN when modifying a parameter, do pre check for each algo and prepare script to only input PIN when needed ; ]
for _TMPALGO in $(gpg --card-status |awk -F': ' '/^Key attributes/ {print $NF}'); do
  if [ "$_TMPALGO" = rsa4096 ]; then
     [ "$_COUNT" = 1 ] && echo "
gpg -v --command-fd 0 --pinentry-mode loopback --card-edit <<EOF
admin
key-attr
1
4096" >>$_TMPSCR
     [ "$_COUNT" = 2 ] && echo "1
4096" >>$_TMPSCR
     [ "$_COUNT" = 3 ] && echo "1
4096" >>$_TMPSCR
  else
     [ "$_COUNT" = 1 ] && echo "
gpg -v --command-fd 0 --pinentry-mode loopback --card-edit <<EOF
admin
key-attr
1
4096
$_ADMINVPGPIN" >>$_TMPSCR
     [ "$_COUNT" = 2 ] && echo "1
4096
$_ADMINVPGPIN" >>$_TMPSCR
     [ "$_COUNT" = 3 ] && echo "1
4096
$_ADMINVPGPIN" >>$_TMPSCR
  fi
  _COUNT=$((_COUNT+1))
done
echo "quit" >>$_TMPSCR
bash "$_TMPSCR"
>$_TMPSCR

# Private Key generation. Most tricky part as the input with gpg command-fd (EOF) does not exactly match user driven gpg menus...
_BLU "# Generate Private Key"
echo "gpg --command-fd=0 --pinentry-mode=loopback --card-edit <<EOF
admin
generate
n
$_USER_PIN
0
${_USER_FULLNAME}
${_USER_MAIL}

$_ADMINVPGPIN
O
quit
EOF
" >>${_TMPSCR}
bash "${_TMPSCR}"
rm -f ${_TMPSCR}
# Print key generation result for easy copy-paste to puppet
_GRN "# Public Key = $(ssh-add -l)
# Add in Puppet = $_IDENTITY"
ssh-add -L |awk '{print $2}'
if ssh-add -L  >/dev/null 2>&1; then
  _LOG "OK" "Generate Private Key"
  _LOG "OK" "Public Key: $(ssh-add -L |awk '{print $2}')"
else
  _LOG "ERROR" "Private Key has not been generated.."
fi
_BLU "Utilisateur: $_USER_FULLNAME - Numero Yubico: $_CARD_SERIAL"
echo
}

_USER_SETTING(){
_BLU "Set User PIN"
# Basic ykman command to set user pin
while true; do
  read -sp "PIN = " _USER_PRIVPIN
  echo
  read -sp "PIN = " _USER_PRIVPIN_TMP
  echo
  [ "$_USER_PRIVPIN" = "$_USER_PRIVPIN_TMP" ] && break || echo "Passwords does not match.. Please retry"
done
ykman openpgp access change-pin -P "$_USER_PIN" -n "$_USER_PRIVPIN"
[ "$?" -ne 0 ] && _LOG "ERROR" "User PIN not set.." || _LOG "OK" "User PIN set"
echo
}

_PREPNLOG(){
_FN_OPT="$1"
# csv generation function
rm -f ${_TMPCSV}*
# if slot 1 has already been programmed, generate a random serial to avoid Upload "duplicate error"
if [ "$_FN_OPT" = mod ]; then
  # get actual otp serial ID
  ykman otp yubiotp -f -S -g -G -O ${_TMPCSV}-tmp 1 >/dev/null 2>&1
  _OLD_OTPSERIAL="$(awk -F',' '{print $2}' ${_TMPCSV}-tmp)"
  # mod with randomly generated last 3 characters
  _NEWCHAR="$(rbw generate 56 | tr -dc 'b-lnrt-v' |head -c 3 |tr '[:upper:]' '[:lower:]')"
  _NEW_OTPSERIAL=$(echo "${_OLD_OTPSERIAL%???}${_NEWCHAR}")
  ykman otp yubiotp -f -g -G 1 -P ${_NEW_OTPSERIAL} -O ${_TMPCSV}
else
  ykman otp yubiotp -f -S -g -G 1 -O ${_TMPCSV}
fi
_GRN "Upload CSV available = ${_TMPCSV}"
_GRN "on the Yubico site = https://upload.yubico.com/"
[ "$_FN_OPT" = mod ] && _LOG "OK" "CSV string = $(cat ${_TMPCSV})  #Replaced_Serial=$_OLD_OTPSERIAL" || _LOG "OK" "CSV string = $(cat ${_TMPCSV})"
}

_YUBICO_UPLOAD(){
_BLU "Prepare Yubico OTP Upload"
if [ "$(ykman otp info |awk -F': ' '/Slot 1/ {print $NF}')" = programmed ]; then
  echo "Slot 1 already programmed.."
  read -n1 -p "Reprogram Slot 1 for Yubico Upload ? [Y/n]"
  [[ "$REPLY" =~ n|no|N|No ]] && return 0
  echo
  _PREPNLOG mod
else
  _PREPNLOG
fi
echo
}

### MAIN
[ "$_CHANGE_ADMIN_PIN" = 1 ] && _ADMIN_PIN_SETTING
[ "$_CHANGE_ID" = 1 ] && _USER_ID
[ "$_CHANGE_RSA" = 1 ] && _RSA_GEN
[ "$_CHANGE_USER" = 1 ] && _USER_SETTING
[ "$_PREP_YUBICO" = 1 ] && _YUBICO_UPLOAD

