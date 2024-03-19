# Use the base image
FROM shardlabs/starknet-devnet-rs:fa1238e8039a53101b5d2d764d3622ff0403a527

# Expose port 5050
EXPOSE 5050

# Set default command to run the container
CMD ["--gas-price", "36000000000", "--data-gas-price", "1", "--timeout", "320", "--seed", "0"]
