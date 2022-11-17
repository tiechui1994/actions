#!/bin/bash

TMPDIR=$(mktemp -d)

CURRENT=$PWD

cd $TMPDIR
for script in ~/.dotfiles/.dotfiles/*; do
  bash "$script"
done
cd $CURRENT

rm -rf $TMPDIR