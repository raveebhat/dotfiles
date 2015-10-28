parse_git_branch() {
     git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}
export PS1="\e[1;34m\u\033[00m\]@\e[1;34m\h \[\033[32m\]\W\[\033[33m\]\$(parse_git_branch)\\e[1;34m $ \[\033[38;5;33m\]"

#export PS1="\[\033[38;5;33m\]\u\[$(tput sgr0)\]\[\033[38;5;15m\]@\[$(tput sgr0)\]\[\033[38;5;33m\]\h\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]\[\033[38;5;41m\]\W\[$(tput sgr0)\]$(parse_git_branch)\ \[\033[38;5;15m\]\\$ \[$(tput sgr0)\]"
