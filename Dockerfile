# Use the base image
FROM shardlabs/starknet-devnet-rs:0.6.0-seed0

# Expose port 5050
EXPOSE 5050

# Set default command to run the container
# Values taken at block 2529608 and ceil them
# l1_data_gas_price: { price_in_fri: '0x8362', price_in_wei: '0x1' },
# l1_gas_price: { price_in_fri: '0x267745a34c04', price_in_wei: '0x4af31412' },
# l2_gas_price: { price_in_fri: '0xb2d05e00', price_in_wei: '0x15c69' },
CMD ["--timeout", "320", "--lite-mode", "--gas-price-fri", "45000000000000", "--data-gas-price-fri", "35000", "--l2-gas-price-fri", "3000000000", "--initial-balance", "1000000000000000000000000"]
