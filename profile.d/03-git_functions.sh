_REPOROOT="$HOME/repos"
# pull all rep at once
pullup (){
cd $_REPOROOT
_BLU "####################################################"
_BLU "############### Git Pull all rep UP ################"
ls -d */ | xargs -I ARGS bash -c "echo \"### repo = ARGS\"|tr -d "/"; cd ARGS; git pull; cd $_REPOROOT && echo"
}

# add n push, ex 'gitp "my comment"'
gitp (){
 git add .
 git commit -m "$@"
 git push
}

repsync(){
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
gitp "Reposync - $(date)"
}
