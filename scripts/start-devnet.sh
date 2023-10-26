#!/bin/bash

if ! command -v starknet-devnet >/dev/null; then
  source ./venv/bin/activate
  if ! command -v starknet-devnet >/dev/null; then
    echo "starknet-devnet is not installed. Please install it and try again." >&2
    echo "Maybe activate your venv using 'source path-to-venv/bin/activate'" >&2
    exit 1
  fi
fi

if nc -z 127.0.0.1 5050; then
  echo "Port is not free"
  exit 1
else
  echo "About to spawn a devnet"
  export STARKNET_DEVNET_CAIRO_VM=rust
  starknet-devnet --cairo-compiler-manifest ./cairo/Cargo.toml --seed 42 --lite-mode --timeout 320 --compiler-args '--add-pythonic-hints --allowed-libfuncs-list-name all'
fi