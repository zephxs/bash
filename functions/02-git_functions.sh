#############################################################
### Git functions
#

_REPOROOTFIND () {
### 1.1 - function to search for all repositories to sync
# will create ~/.reporoot file to base future sync on
if [ ! -f "$HOME/.reporoot" ]; then 
  cd "$HOME"
  find /media/ "$HOME/" -type d -name .git 2>/dev/null >"$HOME/.reporoot"
  sed -i 's#/.git##g' "$HOME/.reporoot"
  _MYECHO -p "# Found repos:"
  cat "$HOME/.reporoot"; echo
  read -p "# Edit repos that will sync? " -n 1 -r
  [[ "$REPLY" =~ ^[Yy]$ ]] && vim "$HOME/.reporoot"
  echo
fi
}

pullup () {
### Pull all repos and branches at once
### v1.4 - add quiet mode
local _VERS='v1.4'
[ -f "$HOME/.reporoot" ] || _REPOROOTFIND
if [ "$1" != "-q" ]; then
_MYECHO -l
_MYECHO -t "Git - Pull all Repos ### $_VERS"
echo
fi

while IFS= read -r _REP; do
if [ "$1" != "-q" ]; then
_MYECHO -l
_MYECHO -p "### Repo = $_REP"
fi
 cd "$_REP" || continue
 while IFS= read -r _BRANCH; do
  # Swap comment on the 2 next lines to suit your needs
  if [ "$1" != "-q" ]; then
  git switch "$_BRANCH"
  git pull && _OK ":\"$_BRANCH\" branch pull success" || _KO ":\"$_BRANCH\" branch pull failed"
  echo
  else
  git switch "$_BRANCH" >/dev/null 2>&1
  git pull >/dev/null 2>&1
  fi
  #git merge --ff-only "$_BRANCH" && _OK ":\"$_BRANCH\" branch pull success" || _KO ":\"$_BRANCH\" branch pull failed"
 done < <(git branch --format='%(refname:short)')
done < "$HOME/.reporoot"
}

repsync () {
### v2.1 - sync all repos to a backup repo
# here 'rep' is the backup repo (_DESTREPO), and all others repositories will be backed up in its own subfolder 
local _BAKREP='rep'
# rsync is needed to delete files that does not exist anymore
[ -f "$HOME/.reporoot" ] || _REPOROOTFIND
# My Sync Repo name is 'rep' in this case
if grep -qw "$_BAKREP$" "$HOME/.reporoot"; then
  local _DESTREPO=$(grep -w "$_BAKREP$" "$HOME/.reporoot")
else 
  echo "Backup Repo not found.. exiting!" && return 1
fi
_MYECHO -l
_MYECHO -t "Git - Repos Sync"
[ -z "$_DESTREPO" ] && echo "Destination Repository not set.. exiting!" && return 1

while IFS= read -r _DIR; do
 [[ "$_DIR" == "$_DESTREPO" ]] && continue
 rsync -rqav --delete "${_DIR}/" "${_DESTREPO}/$(basename "${_DIR}")/"
 cd "${_DESTREPO}/$(basename "${_DIR}")" || continue
 rm -rf .git README.md LICENSE
done < "$HOME/.reporoot"

cd "$_DESTREPO" || return 1
git add -A
if [ -z "$_ORIGREP" ]; then
git commit -m "#Sync=$(date +"%H:%M-%d.%m.%Y")"
else
git commit -m "#Repo=$_ORIGREP #Sync=$(date +"%H:%M-%d.%m.%Y") #Msg=$_COMMITMSG"
fi
git push
}

gitp () {
## git commit, tag, and push AOI
## v2.1
# Usage:
#   gitp "fix landing anim"
#   gitp -m "fix landing anim"
#   gitp -m "fix landing anim" -v v2.4.1
#   gitp -m "fix landing anim" -v v2.4.1 -b mybackup
#   gitp -h
#
# Options:
#   -m, --message MSG   Commit message (required)
#   -v, --version TAG   Create annotated tag TAG and push it (optional)
#   -b, --backup NAME   Backup repo name; if set and differs from origin, run repsync
#   -h, --help          Show this help

local _COMMITMSG='' _VERSION='' _BAKREP='' _ORIGREP=''

# Single positional arg = commit message shortcut (only when not a flag).
if [ $# = 1 ] && [[ "$1" != -* ]]; then
  _COMMITMSG="$1"
else
  while (( $# )); do
    case $1 in
      -m|--message)
        [ $# -ge 2 ] || { echo "gitp: $1 requires an argument"; return 1; }
        _COMMITMSG="$2"; shift 2 ;;
      -v|--version)
        [ $# -ge 2 ] || { echo "gitp: $1 requires an argument"; return 1; }
        _VERSION="$2"; shift 2 ;;
      -b|--backup)
        [ $# -ge 2 ] || { echo "gitp: $1 requires an argument"; return 1; }
        _BAKREP="$2"; shift 2 ;;
      -h|--help)
        echo "Usage: gitp [-m MSG] [-v TAG] [-b BACKUP]"
        echo "  -m, --message MSG   Commit message (required)"
        echo "  -v, --version TAG   Create + push annotated tag (optional)"
        echo "  -b, --backup NAME   Backup repo name; runs repsync if differs from origin"
        echo "  -h, --help          Show this help"
        return 2 ;;
      -*)
        echo "gitp: Unknown option: $1"; return 1 ;;
      *)
        echo "gitp: Unexpected argument: $1"; return 1 ;;
    esac
  done
fi

[ -z "$_COMMITMSG" ] && { echo "gitp: Commit message missing"; return 1; }

_ORIGREP=$(git remote get-url origin --push 2>/dev/null | awk -F'/' '{print $NF}' | sed 's/\.git$//')
[ -z "$_ORIGREP" ] && { echo "gitp: No 'origin' remote found"; return 1; }

_MYECHO -l
_MYECHO -t "Git - Commit and Sync"

# Stage + commit; bail out if either fails (e.g. nothing to commit, hook fails).
git add -A || { echo "gitp: git add failed"; return 1; }
if [ -z "$_VERSION" ]; then
  _MYECHO -p "# Repo= $_ORIGREP  # Comment= $_COMMITMSG"
  git commit -m "$_COMMITMSG" || { echo "gitp: git commit failed"; return 1; }
  git push || { echo "gitp: git push failed"; return 1; }
else
  _MYECHO -p "# Repo= $_ORIGREP  # Comment= $_VERSION:$_COMMITMSG"
  git commit -m "$_VERSION: $_COMMITMSG" || { echo "gitp: git commit failed"; return 1; }
  # Create tag only after commit succeeds.
  git tag -a "$_VERSION" -m "$_VERSION: $_COMMITMSG" || { echo "gitp: git tag failed"; return 1; }
  # Push commits first; only push tags if that succeeds.
  git push || { echo "gitp: git push failed (tag '$_VERSION' left local)"; return 1; }
  git push --tags || { echo "gitp: git push --tags failed"; return 1; }
fi

# Sync to backup repo if one was given and it differs from origin.
if [ -n "$_BAKREP" ]; then
  [ "$_ORIGREP" = "$_BAKREP" ] || repsync
fi
}
