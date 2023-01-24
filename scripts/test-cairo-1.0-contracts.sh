#!/bin/bash
set -e
cd "$(dirname "$0")/.."

./bin/cairo-test --starknet --path contracts/ArgentAccount.cairo