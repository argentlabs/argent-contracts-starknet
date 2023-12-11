#!/bin/bash
if nc -z 127.0.0.1 5050; then
  echo "Port is not free, devnet might be already running"
  exit 1
else
  echo "Starting Devnet"
  docker run -p 127.0.0.1:5050:5050 shardlabs/starknet-devnet-rs:78527decb3f76c4c808fa35f46228557af3df385 --gas-price 36000000000 --timeout 320 --seed 0
fi