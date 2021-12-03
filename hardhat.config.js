require("@shardlabs/starknet-hardhat-plugin");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.7.3",
  cairo: {
    venv: "./venv", // use this if you have a local virtualenv like recommended in this README
    // venv: "~/cairo_venv", // or use this if you prefer a global cairo virtualenv
  },
  paths: {
    starknetArtifacts: "starknet-artifacts", // hardhat default: "starknet-artifacts", nile default: "artifacts"
  }
};
