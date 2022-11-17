#!/usr/bin/bash -I

log() {
  echo "$@" >> /tmp/gitpod.log
}

TMPDIR=$(mktemp -d)

CURRENT=$PWD
cd $TMPDIR
for script in ~/.dotfiles/gitpod/*; do
  log "exec $script"
  bash "$script"
done

files=(
  .github
  .gitignore
  gitpod
  golang
  google
  postfix
  script
  README.md
  bootstrap.sh
)
for i in ${files[@]}; do
  sudo rm -rf ~/.dotfiles/$i
  log "del: ~/.dotfiles/$i ans: $?"
  sudo rm -rf ~/$i
  log "del: ~/$i ans: $?"
done
cd $CURRENT

rm -rf $TMPDIR