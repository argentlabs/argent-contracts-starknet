#!/bin/bash

# Waits for the local devnet to be ready.

set -e # stop the script if any subprocess fails

echo Waiting for devnet to be ready.

result=""
until [[ "$result" == *"Alive"* ]]; do
  result=$(curl http://127.0.0.1:5050/is_alive --silent || true)
  sleep 1
done

echo Devnet ready.
