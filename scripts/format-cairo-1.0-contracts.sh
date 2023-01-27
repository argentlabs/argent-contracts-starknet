#!/bin/bash
set -e
cd "$(dirname "$0")/.."

./cairo/bin/cairo-format --recursive contracts/
