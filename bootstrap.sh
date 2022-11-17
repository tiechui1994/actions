#!/bin/bash

TMPDIR=$(mktemp -d)

CURRENT=$PWD
cd $TMPDIR
files=(
  .github
  .gitignore
  .dotfiles
  golang
  google
  postfix
  script
  README.md
  bootstrap.sh
)

for script in ~/.dotfiles/.dotfiles/*; do
  echo "exec: $script"
  bash "$script"
done

for i in ${files[@]}; do
  rm -rf ~/.dotfiles/$i
  rm -rf ~/$i
done
cd $CURRENT

rm -rf $TMPDIR