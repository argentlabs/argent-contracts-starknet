# Argent Accounts on StarkNet

_Warning: StarkNet is still in alpha, so is this project. In particular the `argent_account.cairo` and `argent_multisig.cairo` contracts have not been audited yet and should not be used to store significant value._

## Specification

See [Argent Account](contracts/account/src/argent_account.cairo) and [Argent Multisig](contracts/multisig/src/argent_multisig.cairo) for more details.

## Development

### Setup Rust

As explained here https://github.com/starkware-libs/cairo#prerequisites

### Setup project

run

```
make
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

## How to deploy a contract

Make sure you have some eth on the network you plan to deploy.

To deploy a contract you first need to declare it (if it is already declared jump this).

Open your argent wallet:

1. Go to Settings >> Developer settings >> Smart contract development >> Declare smart contract.
2. Pick the json file of your contract (not the abi). Make sure to copy the contract class hash.
3. Select the network and the account with which you'll pay.
4. Hit declare and wait.
5. If you didn't already, you can copy the class hash.

Now that your contract is declared, you can deploy it.  
Open your argent wallet:

1. Go to Settings >> Developer settings >> Smart contract development >> Deploy smart contract.
2. Paste the contract class hash.
3. Select the network, and the account with which you'll pay.
4. Specify a salt or hit generate random.
5. Enable "Unique address" if needed.
6. Hit deploy and wait.

## Test the contracts (Cairo)

```
make test
```

## Test the contracts (JavaScript)

### Install the devnet

User [nvm](https://github.com/nvm-sh/nvm) to manage your Node versions.

Install Python dependencies (run in project root folder)

```
python3.9 -m venv ./venv
source ./venv/bin/activate
brew install gmp
pip install -r requirements.txt
```

For more info check [Devnet instructions](https://0xspaceshard.github.io/starknet-devnet/docs/intro)

Then you should be able to spawn a devnet using makefile:

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
To add or update a contract, have a look at the [`fixtures` makefile target](./Makefile).
