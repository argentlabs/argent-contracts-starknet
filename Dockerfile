# Use the base image
FROM shardlabs/starknet-devnet-rs:038d94612c6b6e51f06dc124bb320085485f588d

# Expose port 5050
EXPOSE 5050

# Set default command to run the container
CMD ["--gas-price", "6000000000", "--data-gas-price", "1", "--timeout", "320", "--seed", "0", "--lite-mode", "--gas-price-fri", "35000000000000", "--data-gas-price-fri", "1", "--initial-balance", "1000000000000000000000000"]
                                                                                                                                                                                                                                                          
