#!/bin/bash
if nc -z 127.0.0.1 5050; then
  echo "Port is not free, Devnet might be already running"
  exit 1
else
  echo "Starting Devnet"
  docker run -p 127.0.0.1:5050:5050 shardlabs/starknet-devnet-rs:64c425b832b96ba09b49646fe0fbf49862c0fb6d --gas-price 36000000000 --timeout 320 --seed 0
fi