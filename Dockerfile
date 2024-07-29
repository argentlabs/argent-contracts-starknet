# Use the base image
FROM shardlabs/starknet-devnet-rs:ff9ba95dfff92de33605d7137b916546825b5906

# Expose port 5050
EXPOSE 5050

# Set default command to run the container
CMD ["--gas-price", "36000000000", "--data-gas-price", "1", "--timeout", "320", "--seed", "0", "--lite-mode", "--gas-price-strk", "36000000000", "--data-gas-price-strk", "1"]
