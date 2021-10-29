# Argent Account on Starknet

Preliminary work for an Argent Account on Starknet.

<<<<<<< HEAD
## Environment (python)
=======
## High-Level Specification

The account is a 2-of-2 custom multisig where the `signer` key is typically stored on the user phone and the `guardian` key is managed by an off-chain service to enable fraud monitoring (e.g. trusted contacts, daily limits, etc). The user can always opt-out of the guardian service and manage the `guardian` key himself.

Normal operations of the wallet (`execute`, `change_signer` and `change_guardian`) require both signatures to be executed.

Each party alone can trigger the `escape` mode on the wallet if the other party is not cooperating or lost. An escape takes 7 days before being active, after which the non-cooperating party can be replaced. The wallet is asymetric in favor of the `signer` who can override an escape triggered by the `guardian`. 

A triggered escape can always be cancelled with both signatures.

We assume that the `signer` key is backed up such that the probability of the `signer` key being lost should be close to zero.

Under this model we can build a simple yet highly secure non-custodial wallet.

## Missing Cairo features

- Access to an equivallent of `block.timestamp` to enable timelocks. Currently mocked in the account with the `_block_timestamp` storage variable.
- Access to an equivallent of `address(this)` to determine the self address of the account. Currently mocked in the account with the `_self_address` storage variable.
- An upgrade/proxy pattern using an equivallent of `delegatecall` so that the account of a user can evolve over time without changing address.
- A strategy to define the `_L1_address` storage variable as the L1 address that can exit the assets of the account.
- A mechanism to pay fees.

## Development
>>>>>>> a1447738a1b2b5cde2546b2379984a18ee1813f3

### Install Cairo

See https://www.cairo-lang.org/docs/quickstart.html

### Install Nile
```
pip install cairo-nile
```

See https://github.com/martriay/nile for more details.


### Install pytest
```
pip install pytest pytest-asyncio
```

### Compile the contracts
```
nile compile
```

### Test the contracts
```
pytest ./test/argent_account.py
```

## Environment (node)

### Install

```
yarn install
```

## Compile the contracts
```
yarn run compile 
```

### Test the contracts
```
yarn run test
```