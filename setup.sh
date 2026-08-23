#!/usr/bin/env bash

log() {
  echo "$@" >> /tmp/gitpod.log
}

TMPDIR=$(mktemp -d)

CURRENT=$PWD
cd $TMPDIR

HOME=/home/gitpod
for script in ${HOME}/.dotfiles/gitpod/*; do
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
  setup.sh
)
for i in ${files[@]}; do
  sudo rm -rf ${HOME}/.dotfiles/$i
  log "del: ${HOME}/.dotfiles/$i ans: $?"
  sudo rm -rf ${HOME}/$i
  log "del: ${HOME}/$i ans: $?"
done
cd $CURRENT

rm -rf $TMPDIR