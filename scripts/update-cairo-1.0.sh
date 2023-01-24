#!/bin/bash
set -e
cd "$(dirname "$0")/.."

rm -rf bin corelib
mkdir -p bin
cd ../cairo
git pull
cp -R corelib ../argent-contracts-starknet/corelib
cargo build --release
cd ./target/release
cp cairo-compile cairo-format cairo-run cairo-test starknet-compile ../../../argent-contracts-starknet/bin
