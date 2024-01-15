#!/bin/bash
if nc -z 127.0.0.1 5050; then
  echo "Port is not free, devnet might be already running"
  exit 1
else
  echo "Starting Devnet"
  docker run -p 127.0.0.1:5050:5050 shardlabs/starknet-devnet-rs:fa21132c9b395e1902be3a7fad1976cc339d193b --gas-price 36000000000 --timeout 320 --seed 0
fi