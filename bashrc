# scp protect from echo in .bashrc
[ -z "$PS1" ] && return
#or
[ -t 0 ] || return

 ### Bourne Again Functions

_DIE () { echo $1; exit 1; }


### PS1 User set for system wide bashrc (>/etc/bashrc) 
# change PS1 var if root (toilet line can be commented or remove as toilet is used for ascii art ^^)
#> type toilet >/dev/null || ( echo "... Installing libcaca" && sudo apt install toilet figlet; )
if [ $(id -u) -eq 0 ];
then
    PS1='\[\033[1;30m\][\[\033[1;32m\]\u\[\033[1;30m\]@\[\033[0;34m\]\h\[\033[1;30m\]] \[\033[0;36m\]\w \[\033[1;30m\]#\[\033[0m\]'
    toilet -f smslant --metal "# root user #" && echo
else
    PS1='\[\033[1;30m\][\[\033[1;34m\]\u\[\033[1;30m\]@\[\033[0;35m\]\h\[\033[1;30m\]] \[\033[0;36m\]\w \[\033[1;30m\]$\[\033[0m\]'
    toilet -f smslant --gay "$USER"
fi
