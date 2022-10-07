# colorize if not set
_BLX="\e[1;34m"
_BLU () { echo -e "${_BLX}${@}${_REZ}" ; }

_REPOROOTFIND () {
# lil fn to search for repo root dirs
if [ -f "$HOME/.reporoot" ]; then 
  _REPOROOT=$(cat $HOME/.reporoot)
else
  cd $HOME
  find /media/ /mnt/ $HOME/ -type d -name .git >.reporoot
  sed -i 's#/.git##g' .reporoot
  _REPOROOT=$(cat $HOME/.reporoot)
fi
}

pullup (){
# pull all repos at once
[ -f "$HOME/.reporoot" ] || _REPOROOTFIND
[ -z "$_REPOROOT" ] || _REPOROOTFIND
_BLU "####################################################"
_BLU "############### Git Pull all rep UP ################"
for _REP in $_REPOROOT; do
 _BLU "### repo = $_REP"
 cd $_REP
 for _BRANCH in $(git branch --list |sed 's/ //g; s/*//'); do
  git checkout $_BRANCH
  git pull && _OK ':updated' || _KO ':update failed'
 done
echo
done
}

### the point is to make commit and sync to backup repo that contain all sub repositories
# $HOME/repos/ contains all working repositories
# $HOME/repos/rep is the backup repo
# rsync is needed to delete files that does not exist anymore
repsync(){
[ -f "$HOME/.reporoot" ] || _REPOROOTFIND
_DESTREPO=$(grep -w rep$ "$HOME/.reporoot")    # My Sync Repo name is 'rep' in this case
_SYNCREPOS=$(cat $HOME/.reporoot | grep -v $_DESTREPO)
_BLU "####################################################"
_BLU "############### Git Sync all rep UP ################"
[ -z "$_DESTREPO" ] && echo "Destination Repository not set.. exiting!" && return 1
[ -z "$_SYNCREPOS" ] && echo "Source Repository not set.. exiting!" && return 1
for _DIR in $_SYNCREPOS; do
 rsync -rqav --delete ${_DIR}/ ${_DESTREPO}/$(basename ${_DIR})/
 cd ${_DESTREPO}/$(basename ${_DIR})
 rm -rf .git README.md LICENSE
done
cd ${_DESTREPO}
git add .
if [ -z "_ORIGREP" ]; then
git commit -m "#Sync=$(date +"%H:%M-%d.%m.%Y")"
else
git commit -m "#Repo=$_ORIGREP #Sync=$(date +"%H:%M-%d.%m.%Y") - $_MSG"
fi
git push
}

# add push and sync to back repo with : gitp "my comment"
gitp (){ 
_MSG=$@
_ORIGREP=$(git remote get-url origin --push |awk -F'/' '{print $NF}' |uniq |sed 's/.git//')
_BLU "####################################################"
_BLU "############### Git Commit and Sync ################"
_BLU "# Repo= $_ORIGREP  # Comment= $_MSG"
git add .; git commit -m "$_MSG"; git push
repsync
}

