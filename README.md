# Argent Account on StarkNet

*Warning: StarkNet is still in alpha, so is this project. In particular the `ArgentAccount.cairo` contract has not been audited yet and should not be used to store significant value.*

## High-Level Specification

The account is a 2-of-2 custom multisig where the `signer` key is typically stored on the user's phone and the `guardian` key is managed by an off-chain service to enable fraud monitoring (e.g. trusted contacts, daily limits, etc) and recovery. More specifically, the `guardian` acts both as a co-validator for typical operations of the wallet, and as the trusted actor that can recover the wallet in case the `signer` key is lost or compromised.

The user can always opt-out of the guardian service and manage the guardian key himself. Alternatively he can add a second `guardian_backup` key to the account that has the same role as the `guardian` and can be used as the ultimate censorship resistance guarantee.

Normal operations of the wallet (`execute`, `change_signer`, `change_guardian`, `change_guardian_backup`, `validate_guardian_signature`, `cancel_escape`) require the approval of both parties to be executed.

Each party alone can trigger the `escape` mode (a.k.a. recovery) on the wallet if the other party is not cooperating or lost. An escape takes 7 days before being active, after which the non-cooperating party can be replaced.
The wallet is asymmetric in favor of the `signer` who can override an escape triggered by the guardian.

A triggered escape can always be cancelled with the approval of both parties.

We assume that the `signer` key is backed up such that the probability of the `signer` key being lost should be close to zero.

Under this model we can build a simple yet highly secure non-custodial wallet.

| Action | Signer | Guardian | Comments |
|--------|--------|----------|----------|
| Execute | X | X | |
| Change Signer | X | X | |
| Change Guardian | X | X | |
| Change Guardian Backup | X | X | |
| Trigger Escape Guardian | X | | Can override an escape signer in progress |
| Trigger Escape Signer | | X | Fail if escape guardian in progress |
| Escape Guardian | X | | After security period |
| Escape Signer | | X | After security period |
| Cancel Escape | X | X | |


## Missing Cairo features

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


