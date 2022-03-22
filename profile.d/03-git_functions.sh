_REPOROOT="$HOME/xtra/admin/repos"
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
_BLU "####################################################"
_BLU "############### Git Sync all rep UP ################"
for _DIR in 'bash' 'ncat-ipset-honeypot' 'priv'; do
cd $_REPOROOT
cp -ar $_DIR rep/
cd rep/$_DIR
rm -rf .git README.md LICENSE
done
cd $_REPOROOT/rep
gitp "Reposync - $date"
}
