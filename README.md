# Argent Account on Starknet

Preliminary work for an Argent Account on Starknet.

## High-Level Specification

The account is a 2-of-2 custom multisig where the `signer` key is typically stored on the user's phone and the `guardian` key is managed by an off-chain service to enable fraud monitoring (e.g. trusted contacts, daily limits, etc). The user can always opt-out of the guardian service and manage the `guardian` key himself.

Normal operations of the wallet (`execute`, `change_signer` and `change_guardian`) require both signatures to be executed.

Each party alone can trigger the `escape` mode on the wallet if the other party is not cooperating or lost. An escape takes 7 days before being active, after which the non-cooperating party can be replaced. The wallet is asymmetric in favor of the `signer` who can override an escape triggered by the `guardian`.

A triggered escape can always be cancelled with both signatures.

We assume that the `signer` key is backed up such that the probability of the `signer` key being lost should be close to zero.

Under this model we can build a simple yet highly secure non-custodial wallet.

## Missing Cairo features

- Access to an equivalent of `block.timestamp` to enable timelocks. Currently mocked in the account with the `_block_timestamp` storage variable.
- An upgrade/proxy pattern using an equivalent of `delegatecall` so that the account of a user can evolve over time without changing addresses.
- A mechanism to pay fees.

## Development

### Setup a local virtual env

```
python -m venv ./venv
source ./venv/bin/activate
```

### Install Cairo dependencies
```
brew install gmp
```

```
pip install -r requirements.txt
```

See for more details:
- https://www.cairo-lang.org/docs/quickstart.html
- https://github.com/martriay/nile

### Compile the contracts
```
nile compile
```

### Test the contracts
```
pytest ./test/argent_account.py
```


