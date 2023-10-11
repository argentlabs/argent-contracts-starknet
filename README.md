# Argent Accounts on Starknet

## Specification

See [Argent Account](contracts/account/README.md) and [Argent Multisig](contracts/multisig/README.md) for more details.

## Development

### Setup Rust

Please refer to [these instructions](https://docs.cairo-lang.org/getting_started/prerequisits.html).  
You can skip cloning the Cairo repository, as this will be done automatically through the Makefile.  
If you are a developer, we recommend that you install the Cairo extension. You can find it in the vscode Extensions Marketplace by looking for "Cairo 1.0".

### Setup project

run

```shell
make
```

## Test the contracts (Cairo)

```shell
make test
```

## Test the contracts (JavaScript)

### Install the devnet

We advise that you use [nvm](https://github.com/nvm-sh/nvm) to manage your Node versions.

Install Python dependencies (run in project root folder)

```shell
python3.9 -m venv ./venv
source ./venv/bin/activate
brew install gmp
pip install -r requirements.txt
```

For more info check [Devnet instructions](https://0xspaceshard.github.io/starknet-devnet/docs/intro)

Then you should be able to spawn a devnet by running the following make command:

```shell
make devnet
```

### Install JS dependencies

Install all packages:

```shell
yarn
```

Run all integration tests:

```shell
make test-integration
```

Run single integration test file (need to run previous command first):

```shell
yarn mocha ./tests/accountEscape.test.ts
```

You also have access to the linter and a code formatter:

```shell
yarn lint
yarn format
```

### Contract fixtures

The [fixtures folder](./tests/fixtures/) contains pre-compiled contracts used for tests (both json and casm).  
To add or update a contract, have a look at the [`fixtures` Makefile target](./Makefile).

### Interface IDs

For compatibility reasons we support legacy interface IDs . But new interface IDs will follow [SNIP-5](https://github.com/ericnordelo/SNIPs/blob/feat/standard-interface-detection/SNIPS/snip-5.md#how-interfaces-are-identified)
Tool to calculate interface IDs: https://github.com/ericnordelo/src5-rs

## Release checklist

- Bump version if needed (new deployment in mainnet)
- Set up your .env file with the deployer info and run `yarn deploy` to declare the accounts
- Verify the contracts if possible
- Deploy to as many environments as possible: mainnet, goerli-1, goerli-2 or integration
- Update the contents of the `deployments` folder with the new addresses
- Copy relevant build artifacts from `target/release` to `deployments/artifacts`
- Tag the commit used for the release (include the same name as in the `deployments` folder for easy tracking)
- Create release in GitHub if needed
- Make this checklist better if you learned something during the process
