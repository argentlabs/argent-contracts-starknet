#!/bin/bash

if ! command -v starknet-devnet >/dev/null; then
  echo "starknet-devnet is not installed. Please install it and try again." >&2
  echo "Maybe start your venv" >&2
  exit 1
fi

if nc -z 127.0.0.1 5050; then
  echo "Port is not free"
  exit 1
else
  echo "About to spawn a devnet"
  export STARKNET_DEVNET_CAIRO_VM=python
  starknet-devnet --cairo-compiler-manifest $INSTALLATION_FOLDER_CARGO --seed 42 --lite-mode --timeout 320
fi
