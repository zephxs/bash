### Root directory containing all repositories
_REPOROOT="$HOME/repos"

# colorize if not set
_BLX="\e[1;34m"
_BLU () { echo -e "${_BLX}${@}${_REZ}" ; }

### pull all rep at once
pullup (){
cd $_REPOROOT
_BLU "####################################################"
_BLU "############### Git Pull all rep UP ################"
for _REP in $(ls -d */); do
 _BLU "### repo = $_REP"|tr -d "/"
 cd $_REP
 for _BRANCH in $(git branch --list |sed 's/ //g; s/*//'); do
  git checkout $_BRANCH
  git pull
 done
cd $_REPOROOT && echo
done
}

### the point is to make commit and sync to backup repo that contain all sub repositories
# $HOME/repos/ contains all working repositories
# $HOME/repos/rep is the backup repo
# rsync is needed to delete files that does not exist anymore
repsync(){
_REPOROOT="$HOME/repos"
_DESTREPO='rep'
_BLU "####################################################"
_BLU "############### Git Sync all rep UP ################"
cd $_REPOROOT
if [ -z "$_DESTREPO" ]; then echo "Destination Repository not set.. exiting!"; exit 1; fi
for _DIR in $(ls | grep -v $_DESTREPO); do
 cd $_REPOROOT
 cp -ar $_DIR ${_DESTREPO}/
 rsync -av --delete ${_DIR}/ ${_DESTREPO}/${_DIR}/
 cd ${_DESTREPO}/${_DIR}
 rm -rf .git README.md LICENSE
done
cd ${_REPOROOT}/${_DESTREPO}
git add .
git commit -m "#Repo=$_ORIGREP #Sync=$(date +"%H:%M-%d.%m.%Y") - $_MSG"
git push
}

# add push and sync to back repo with : gitp "my comment"
gitp (){ 
_MSG=$@
_ORIGREP=$(git remote show origin |grep 'URL' |awk -F'/' '{print $NF}' |uniq |sed 's/.git//')
_BLU "####################################################"
_BLU "############### Git Commit and Sync ################"
_BLU "# Repo= $_ORIGREP  # Comment= $_MSG"
git add .; git commit -m "$_MSG"; git push
repsync
}


