#!/bin/bash
set -e
cd "$(dirname "$0")/.."

mkdir -p cairo
if [ ! -d "./cairo/starkware-libs-cairo" ]; then 
	git clone --depth 1 https://github.com/starkware-libs/cairo.git ./cairo/starkware-libs-cairo
else
	cd ./cairo/starkware-libs-cairo
	git pull
	cd ../..
fi

rm -rf ./cairo/{corelib,bin}

cd ./cairo/starkware-libs-cairo
cargo build --release
cp -R ./corelib ../corelib
cp -R ./target/release ../bin