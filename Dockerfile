# Use the base image
FROM shardlabs/starknet-devnet-rs:7fb5a9e446961f12ff7a311a78b92a8f1f7b5e57

# Expose port 5050
EXPOSE 5050

# Set default command to run the container
CMD ["--gas-price", "6000000000", "--data-gas-price", "1", "--timeout", "320", "--seed", "0", "--lite-mode", "--gas-price-strk", "35000000000000", "--data-gas-price-strk", "1", "----initial-balance", "1000000000000000000000000"]
                                                                                                                                                                                                                                                          