# Argent Accounts on Starknet

## Specification

See [Argent Account](./docs/argent_account.md) and [Argent Multisig](./docs/multisig.md) for more details.

## Deployments

See deployed class hashes can be found here for the [Argent Account](./deployments/account.txt), and here for the [Argent Multisig](./deployments/multisig.txt)

Other deployment artifacts are located in [/deployments/](./deployments/)

Find the release notes for all versions in [CHANGELOG](./CHANGELOG.md)

## Development

### Setup
# TODO WE NOW NEED TO INSTALL THE USC, Improve CI + mention how to
We recommend you to install scarb through ASDF. Please refer to [these instructions](https://docs.swmansion.com/scarb/download.html#install-via-asdf).  
Thanks to the [.tool-versions file](./.tool-versions), you don't need to install a specific scarb or starknet foundry version. The correct one will be automatically downloaded and installed.

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

The [fixtures folder](./tests-integration/fixtures/) contains pre-compiled contracts used for tests (both json and casm).

### Interface IDs

For compatibility reasons we support legacy interface IDs. But new interface IDs will follow [SNIP-5](https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-5.md#how-interfaces-are-identified)
Tool to calculate interface IDs: https://github.com/ericnordelo/src5-rs

### Cairo Zero SHA256 contract

The Webauthn signer is designed to work with multiple possible SHA256 implementations. The Cairo Zero variant is implemented at class hash specified as constant in the signer's source code, which can be reproduced using:

```shell
git clone https://github.com/cartridge-gg/cairo-sha256
cd cairo-sha256
git checkout 8d2ae51
git apply ../lib/signers/cairo0-sha256.patch

python3.9 -m venv ./venv
source ./venv/bin/activate
pip install cairo-lang==0.12.1

starknet-compile-deprecated --no_debug_info src/main.cairo > ../tests-integration/fixtures/argent_Sha256Cairo0.contract_class.json

# cleanup and clear whitespace diffs:
deactivate
cd ..
rm -rf cairo-sha256
scarb run format
```

## Release checklist

- Bump version if needed (new deployment in mainnet)
- Set up your .env file with the deployer info and run `scarb run deploy-account` and `scarb run deploy-multisig` to declare the accounts
- Verify the contracts if possible
- Deploy to as many environments as possible: mainnet, sepolia and integration
- Update the contents of the `deployments` folder with the new addresses
- Copy relevant build artifacts from `target/release` to `deployments/artifacts`, include abi file.
- Tag the commit used for the release (include the same name as in the `deployments` folder for easy tracking)
- Create release in GitHub if needed
- Make this checklist better if you learned something during the process
