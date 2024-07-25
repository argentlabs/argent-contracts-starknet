#!/bin/bash
if nc -z 127.0.0.1 5050; then
  echo "Port is not free, devnet might be already running"
  exit 1
else
  echo "Starting Devnet"
  docker run -p 127.0.0.1:5050:5050 shardlabs/starknet-devnet-rs:7fb5a9e446961f12ff7a311a78b92a8f1f7b5e57 --gas-price 36000000000 --data-gas-price 1 --timeout 320 --seed 0
fi
