# Use Rust as the base image for building
# TODO When released, revert to prev way of doing things
FROM rust:latest AS builder

# Install dependencies
RUN apt-get update && apt-get install -y git clang cmake libssl-dev pkg-config

# Set working directory
WORKDIR /app

# Clone the repo and checkout a specific commit
RUN git clone https://github.com/0xSpaceShard/starknet-devnet-rs . && \
    git checkout febf11e9c20fa14511a54d157805ac4a7be62d4d

# Build the project explicitly as a binary
RUN cargo build --bin starknet-devnet --release

# Verify the binary exists
RUN ls -lah /app/target/release/

# Create a minimal runtime image
FROM ubuntu:latest

# Set working directory
WORKDIR /app

# Copy the built binary from the builder stage
COPY --from=builder /app/target/release/starknet-devnet /usr/local/bin/starknet-devnet

# Ensure the binary is executable
RUN chmod +x /usr/local/bin/starknet-devnet

# Expose port 5050
EXPOSE 5050

# Set default command to run the container
CMD ["/usr/local/bin/starknet-devnet", "--host", "0.0.0.0", "--seed", "0", "--gas-price", "6000000000", "--data-gas-price", "1", "--timeout", "320", "--lite-mode", "--gas-price-fri", "35000000000000", "--data-gas-price-fri", "1", "--initial-balance", "1000000000000000000000000"]
