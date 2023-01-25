#!/bin/bash
set -e
cd "$(dirname "$0")/.."

./cairo/bin/cairo-test --starknet --path contracts/lib.cairo
