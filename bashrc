
# ******** http://github.com/raveebhat ********

# Colored PS1 prompt which shows git branch
parse_git_branch() {
  git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}
# Try this export PS1="\u@\h \W\[\033[32m\]\$(parse_git_branch)\[\033[00m\] $ "
export PS1="[\[\e[0;33m\]\w\[\033[32m\]\$(parse_git_branch)\[\033[00m\]]$ "
