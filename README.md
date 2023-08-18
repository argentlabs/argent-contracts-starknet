# Argent Accounts on StarkNet

## Specification

See [Argent Account](contracts/account/README.md) and [Argent Multisig](contracts/multisig/README.md) for more details.

## Development

### Setup Rust

As explained here https://github.com/starkware-libs/cairo#prerequisites

### Setup asdf

As explained here https://asdf-vm.com/guide/getting-started.html

### Setup scarb

```shell
asdf plugin add scarb
asdf install
```

### Setup vscode extension (optional)

```
cd cairo/vscode-cairo
sudo npm install --global @vscode/vsce
npm install
vsce package
code --install-extension cairo1*.vsix
cd ../..
```

Then go to the vscode extension setting and fill "Language Server Path" using the path appropriate for your machine

```
/FULL_PATH_TO_THIS_FOLDER/cairo/target/release/cairo-language-server
```

Original docs in case it changes: https://github.com/starkware-libs/cairo/tree/main/vscode-cairo

## Test the contracts (Cairo)

```
scarb test
```

## Test the contracts (JavaScript)

### Install the devnet (run in project root folder)

Use [nvm](https://github.com/nvm-sh/nvm) to manage your Node versions.

Install devnet

```shell
make install-devnet-cairo
```

Install Python dependencies

```shell
python3.9 -m venv ./venv
source ./venv/bin/activate
brew install gmp
pip install -r requirements.txt
```

For more info check [Devnet instructions](https://0xspaceshard.github.io/starknet-devnet/docs/intro)

Then you should be able to spawn a devnet:

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
yarn lint
yarn format
```

### Contract fixtures

The [fixtures folder](./tests/fixtures/) contains pre-compiled contracts used for tests (both json and casm).  
To add or update a contract, have a look at the [`fixtures` makefile target](./Makefile).

### Interface IDs

We support legacy interface IDs for compatibility reasons. But new interfaces IDs will follow [SNIP-5](https://github.com/ericnordelo/SNIPs/blob/feat/standard-interface-detection/SNIPS/snip-5.md#how-interfaces-are-identified)
Tool to calculate the interface ids: https://github.com/ericnordelo/src5-rs

## Release checklist

- Bump version if needed (new deployment in mainnet)
- Setup your .env file with the deployer info and run `yarn deploy` to declare the accounts
- Verify the contracts if possible
- Deploy to as many envs as possible: goerli-1, goerli-2, integration...
- Update the contents of the `deployments` folder with the new addresses
- Tag the commit used for the release (include the same name as in the `deployments` folder for easy tracking)
- Create release in github if needed
- Make this checklist better if you learned something during the process
