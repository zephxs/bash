### Root directory containing all repositories
_REPOROOT="$HOME/repos"

### pull all rep at once
pullup (){
cd $_REPOROOT
_BLU "####################################################"
_BLU "############### Git Pull all rep UP ################"
ls -d */ | xargs -I ARGS bash -c "echo \"### repo = ARGS\"|tr -d "/"; cd ARGS; git pull; cd $_REPOROOT && echo"
}

### the point is to make commit and sync to backup repo that contain all sub repositories
# $HOME/repos/ contains all working repositories
# $HOME/repos/rep is the backup repo
repsync(){
_REPOROOT="$HOME/repos"
_DESTREPO='rep'
_BLU "####################################################"
_BLU "############### Git Sync all rep UP ################"
cd $_REPOROOT
for _DIR in $(ls | grep -v $_DESTREPO); do
cd $_REPOROOT
cp -ar $_DIR ${_DESTREPO}/
cd ${_DESTREPO}/${_DIR}
rm -rf .git README.md LICENSE
done
cd ${_REPOROOT}/${_DESTREPO}
git add .
git commit -m "#Sync=$(date +"%H:%M-%d.%m.%Y") #Rep=$_ORIGREP - $_MSG"
git push
}

# add push and sync to back repo with : gitp "my comment"
gitp (){ 
_BLU "####################################################"
_BLU "############### Git Commit and Sync ################"
_MSG=$@
git add .; git commit -m "$_MSG"; git push
_ORIGREP=$(git remote show origin |grep 'Fetch URL' |awk -F'/' '{print $NF}' |sed 's/.git//')
_MSG=$_MSG / 
_ORIGREP=$_ORIGREP /
repsync
}

