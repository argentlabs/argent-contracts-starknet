# Use the base image
FROM shardlabs/starknet-devnet-rs:b354ecfe08fb6fbbb9c88e7631a2a74ddefb3965

# Expose port 5050
EXPOSE 5050

# Set default command to run the container
CMD ["--seed", "0", "--gas-price", "6000000000", "--data-gas-price", "1", "--timeout", "320", "--lite-mode", "--gas-price-fri", "35000000000000", "--data-gas-price-fri", "1", "--initial-balance", "1000000000000000000000000"]
