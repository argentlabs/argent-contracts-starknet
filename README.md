# Argent Account on StarkNet

_Warning: StarkNet is still in alpha, so is this project. In particular the `ArgentAccount.cairo` contract has not been audited yet and should not be used to store significant value._

## High-Level Specification

The account is a 2-of-2 custom multisig where the `signer` key is typically stored on the user's phone and the `guardian` key is managed by an off-chain service to enable fraud monitoring (e.g. trusted contacts, daily limits, etc) and recovery. More specifically, the `guardian` acts both as a co-validator for typical operations of the wallet, and as the trusted actor that can recover the wallet in case the `signer` key is lost or compromised.

The user can always opt-out of the guardian service and manage the guardian key himself. Alternatively he/she can add a second `guardian_backup` key to the account that has the same role as the `guardian` and can be used as the ultimate censorship resistance guarantee.

Normal operations of the wallet (`execute`, `changeSigner`, `changeGuardian`, `changeGuardianBackup`, `validateGuardianSignature`, `cancelEscape`) require the approval of both parties to be executed.

Each party alone can trigger the `escape` mode (a.k.a. recovery) on the wallet if the other party is not cooperating or lost. An escape takes 7 days before being active, after which the non-cooperating party can be replaced.
The wallet is asymmetric in favor of the `signer` who can override an escape triggered by the guardian.

A triggered escape can always be cancelled with the approval of both parties.

We assume that the `signer` key is backed up such that the probability of the `signer` key being lost should be close to zero.

Under this model we can build a simple yet highly secure non-custodial wallet.

To enable that model to evolve if needed, the account is implemented as a proxy delegating all calls to a target implementation. Upgrading the wallet to a new implementation requires the approval of both the `signer` and a `guardian`.

| Action                  | Signer | Guardian | Comments                                  |
| ----------------------- | ------ | -------- | ----------------------------------------- |
| Execute                 | X      | X        |                                           |
| Change Signer           | X      | X        |                                           |
| Change Guardian         | X      | X        |                                           |
| Change Guardian Backup  | X      | X        |                                           |
| Trigger Escape Guardian | X      |          | Can override an escape signer in progress |
| Trigger Escape Signer   |        | X        | Fail if escape guardian in progress       |
| Escape Guardian         | X      |          | After security period                     |
| Escape Signer           |        | X        | After security period                     |
| Cancel Escape           | X      | X        |                                           |
| Upgrade                 | X      | X        |                                           |

## Development

### Setup Rust

As explained here https://github.com/starkware-libs/cairo#prerequisites

### Setup project

run

```
make install
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

Install all packages (run in this folder `cd tests`)

```shell
yarn
```

```shell
yarn test
```

You also have access to the linter and a code formatter:

```shell
yarn lint
yarn format
```

### Contract fixtures

The [contracts folder](./contracts/) contains all the contracts already deployed (both json and casm).  
To add or update a contract there run the command:

```shell
./cairo/target/release/starknet-compile ./contracts/account tests/contracts/${FILE_NAME}.json --allowed-libfuncs-list-name experimental_v0.1.0

./cairo/target/release/starknet-sierra-compile ./tests/contracts/${FILE_NAME}.json ./tests/contracts/${FILE_NAME}.casm --allowed-libfuncs-list-name experimental_v0.1.0
```
