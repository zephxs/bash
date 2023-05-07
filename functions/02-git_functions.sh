#############################################################
### Git functions

_REPOROOTFIND () {
### 1.1 - function to search for all repositories to sync
# will create ~/.reporoot file to base future sync on
if [ ! -f "$HOME/.reporoot" ]; then 
  cd $HOME
  find /media/ $HOME/ -type d -name .git 2>/dev/null >$HOME/.reporoot
  sed -i 's#/.git##g' $HOME/.reporoot
  _MYECHO -p "# Found repos:"
  cat $HOME/.reporoot; echo
  read -p "# Edit repos that will sync? " -n 1 -r
  [[ "$REPLY" =~ ^[Yy]$ ]] && vim $HOME/.reporoot
  _REPOROOT=$(cat $HOME/.reporoot)
  echo
fi
}

pullup () {
### 1.3 - pull all repos and all branches at once
[ -f "$HOME/.reporoot" ] && _REPOROOT=$(cat $HOME/.reporoot) || _REPOROOTFIND
_MYECHO -l
_MYECHO -t "Git - Pull all Repos"
echo
for _REP in $_REPOROOT; do
_MYECHO -l
_MYECHO -p "### Repo = $_REP"
 cd $_REP || continue
 for _BRANCH in $(git branch --list |sed 's/ //g; s/*//'); do
  git switch "$_BRANCH"
  # Swap comment on the 2 next lines to suit your needs
  git pull && _OK ":\"$_BRANCH\" branch pull success" || _KO ":\"$_BRANCH\" branch pull failed"
  #git merge --ff-only $_BRANCH && _OK ":\"$_BRANCH\" branch pull success" || _KO ":\"$_BRANCH\" branch pull failed"
 done
echo
done
}

repsync () {
### 2.1 - sync all repos to a backup repo
# here 'rep' is the backup repo (_DESTREPO), and all others repositories will be backed up in its own subfolder 
# rsync is needed to delete files that does not exist anymore
[ -f "$HOME/.reporoot" ] || _REPOROOTFIND
_DESTREPO=$(grep -w rep$ "$HOME/.reporoot")    # My Sync Repo name is 'rep' in this case
_SYNCREPOS=$(cat $HOME/.reporoot | grep -v $_DESTREPO)
_MYECHO -l
_MYECHO -t "Git - Repos Sync"
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
git commit -m "#Repo=$_ORIGREP #Sync=$(date +"%H:%M-%d.%m.%Y") #Msg=$_COMMITMSG"
fi
git push
}

gitp () {
### 1.5 - add push and sync to back repo with : gitp "my comment"
_COMMITMSG=$@
[ -z "$_COMMITMSG" ] && { echo "Commit message missing" && return 1; }
_ORIGREP=$(git remote get-url origin --push |awk -F'/' '{print $NF}' |uniq |sed 's/.git//')
_MYECHO -l
_MYECHO -t "Git - Commit and Sync"
_MYECHO -p "# Repo= $_ORIGREP  # Comment= $_COMMITMSG"
git add .; git commit -m "$_COMMITMSG"; git push
repsync
}

