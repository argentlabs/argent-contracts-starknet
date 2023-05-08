# Prerequisite

Have [node and npm installed.](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)

# Installation

## Install the devnet

Install python dependencies (Run in project root folder)

```
python3.9 -m venv ./venv
source ./venv/bin/activate
brew install gmp
pip install -r requirements.txt
```

Then you should be able to spawn a devnet using makefile:

```shell
make devnet
```

## Install the project

Install all packages (run in this folder)

```shell
npm install
```

```shell
npm run test
```

You also have access to the linter and a code formatter:
```shell
npm run lint
npm run prettier
```

# Contracts

The [contracts folder](./contracts/) contains all the contracts already deployed (both json and casm).  
To add or update a contract there run the command:

```shell
./cairo/target/release/starknet-compile ./contracts/account tests/contracts/${FILE_NAME}.json --allowed-libfuncs-list-name experimental_v0.1.0

./cairo/target/release/starknet-sierra-compile ./tests/contracts/${FILE_NAME}.json ./tests/contracts/${FILE_NAME}.casm --allowed-libfuncs-list-name experimental_v0.1.0
```
