#!/bin/bash
set -e
cd "$(dirname "$0")/.."

./cairo/bin/cairo-test --starknet --path contracts/argent_account.cairo
