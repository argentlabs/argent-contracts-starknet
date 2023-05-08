# Prerequisite

Have [node and npm installed.](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)

# Installation

## Install the devnet

I'd recommend you do that in a virtual env following [this tutorial](https://docs.starknet.io/documentation/getting_started/environment_setup/).

Then you can setup the devnet following [these instructions](https://0xspaceshard.github.io/starknet-devnet/docs/intro).

Then you should be able to spawn a devnet using makefile:

```shell
make devnet
```

## Install the project

Install all packages

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
