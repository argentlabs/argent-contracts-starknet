# Use the base image
FROM shardlabs/starknet-devnet-rs:bab781a018318df51adb20fc60716c8429ee89b0

# Expose port 5050
EXPOSE 5050

# Set default command to run the container
CMD ["--gas-price", "36000000000", "--data-gas-price", "1", "--timeout", "320", "--seed", "0", "--lite-mode", "--gas-price-strk", "36000000000", "--data-gas-price-strk", "1"]
