# Argent Account on Starknet

Preliminary work for an Argent Account on Starknet.

## High-Level Specification

The account is a 2-of-2 custom multisig where the `signer` key is typically stored on the user's phone and the `guardian` is an external contract that can validate the signatures of one or more keys. 
The `guardian` acts both as a co-validator for typical operations of the wallet, and as the trusted actor that can recover the wallet in case the `signer` key is lost or compromised.
These two features may have different key requirements (e.g. a single key for fraud monitoring, and a n-of-m setup for 'social' recovery) as encapsulated by the logic of the `guardian` contract.

By default the `guardian` has a single key managed by an off-chain service to enable fraud monitoring (e.g. trusted contacts, daily limits, etc) and recovery. The user can always opt-out of the guardian service and select a `guardian` contract with different key requirements.

Normal operations of the wallet (`execute`, `change_signer`, `change_guardian`, `cancel_escape`) require the approval of both parties to be executed.

Each party alone can trigger the `escape` mode (a.k.a. recovery) on the wallet if the other party is not cooperating or lost. An escape takes 7 days before being active, after which the non-cooperating party can be replaced.
The wallet is always asymmetric in favor of one of the party depending on the `weight` of the `guardian`. The favoured party can always override an escape triggered by the other party.

A triggered escape can always be cancelled with the approval of both parties.

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


