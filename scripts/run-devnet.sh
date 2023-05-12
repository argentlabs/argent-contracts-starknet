#!/bin/bash

# Starts a local zkSync node and releases control when the RPC endpoint is ready.

set -e # stop the script if any subprocess fails

echo Starting Devnet...

make devnet &

result=""
until [[ "$result" == *"Alive"* ]]; do
	result=$(curl http://127.0.0.1:5050/is_alive \
		--silent \
		|| true)
	sleep 1
done

echo Devnet up and running ready.