# Argent Accounts on Starknet

## Specification

See [Argent Account](src/account/README.md) and [Argent Multisig](src/multisig/README.md) for more details.

## Development

### Setup Rust

Please refer to [these instructions](https://docs.cairo-lang.org/getting_started/prerequisites.html).  
You can skip cloning the Cairo repository, as this will be done automatically through the Makefile.  
If you are a developer, we recommend that you install the Cairo extension. You can find it in the vscode Extensions Marketplace by looking for "Cairo 1.0".

### Setup scarb

Refer to this documentation: https://docs.swmansion.com/scarb/download.html#install-via-asdf  
Thanks to the [.tool-versions file](./.tool-versions), you don't need to install a specific scarb version. The correct one will be automatically downloaded and installed.

## Test the contracts (Cairo)

```
scarb test
```

## Test the contracts (JavaScript)

### Install the devnet (run in project root folder)

You should have docker installed in your machine then you can start the devnet by running the following command:

```shell
scarb run start-devnet
```

### Install JS dependencies

Install all packages:

```shell
yarn
```

Run all integration tests:

```shell
scarb run test-ts
```

Run single integration test file (need to run previous command first):

```shell
yarn mocha ./tests/accountEscape.test.ts
```

You also have access to the linter and a code formatter:

```shell
scarb run lint
scarb run format
```

### Contract fixtures

The [fixtures folder](./tests-integrations/fixtures/) contains pre-compiled contracts used for tests (both json and casm).

### Interface IDs

For compatibility reasons we support legacy interface IDs. But new interface IDs will follow [SNIP-5](https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-5.md#how-interfaces-are-identified)
Tool to calculate interface IDs: https://github.com/ericnordelo/src5-rs

## Release checklist

- Bump version if needed (new deployment in mainnet)
- Set up your .env file with the deployer info and run `yarn deploy` to declare the accounts
- Verify the contracts if possible
- Deploy to as many environments as possible: mainnet, goerli, sepolia and integration
- Update the contents of the `deployments` folder with the new addresses
- Copy relevant build artifacts from `target/release` to `deployments/artifacts`
- Tag the commit used for the release (include the same name as in the `deployments` folder for easy tracking)
- Create release in GitHub if needed
- Make this checklist better if you learned something during the process
