# Argent Account on Starknet

Preliminary work for an Argent Account on Starknet.

## High-Level Specification

The account is a 2-of-2 custom multisig where the `signer` key is stored on the user phone and the `guardian` key is typically  managed by an off-chain service to enable fraud monitoring (e.g. trusted contacts or dapps, daily limits, etc). The user can always opt-out of the guardian service and manage the `guardian` key himself.

Normal operations of the wallet (`execute`, `change_signer` and `change_guardian`) require both signatures to be executed.

Each party alone can trigger the `escape` mode on the wallet if the other party is not cooperating, lost, or compromised. An escape takes 7 days before being active. Once the escape is active, the non-cooperating party can be replaced. 

An escape can always be cancelled with the signatures of both the `signer` and the `guardian`.

The `signer` is the real owner of the wallet and can always override an ongoing escape triggered by the `guardian`.

We assume that the `signer` key is backed up such that the probability of the `signer` key being lost should be close to zero.

Under this model we can build a simple yet highly secure wallet non-custodial wallet.

## Development

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


