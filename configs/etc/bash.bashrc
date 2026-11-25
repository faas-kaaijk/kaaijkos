[[ $- != *i* ]] && return
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'
if [ "$(id -u)" -eq 0 ]; then
    PS1='\[\e[1;36m\]KaaijkOS\[\e[0m\] \[\e[1;31m\]\u\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]# '
else
    PS1='\[\e[1;36m\]KaaijkOS\[\e[0m\] \[\e[1;32m\]\u\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
fi
