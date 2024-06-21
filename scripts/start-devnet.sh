#!/bin/bash
if nc -z 127.0.0.1 5050; then
  echo "Port is not free, devnet might be already running"
  exit 1
else
  echo "Starting Devnet"
  docker run -p 127.0.0.1:5050:5050 shardlabs/starknet-devnet-rs:c4185522228f61ba04619151eb5706d4610fb00f --gas-price 36000000000 --data-gas-price 1 --timeout 320 --seed 0
fi
