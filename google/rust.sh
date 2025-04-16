#!/usr/bin/env bash

 curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.80.0 && source $HOME/.cargo/env \
  rustup --version; \
  cargo --version; \
  rustc --version;
