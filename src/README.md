# Argent Account

## High-Level Specification

The Argent account is a custom multisig (1-of-1, 2-of-2 or 2-of-3) tailored for individuals.

The primary key called the `owner` is typically stored on the user's device. A second key called the `guardian` acts both as a co-validator for typical operations of the wallet, and as the trusted actor that can recover the wallet in case the `owner` key is lost or compromised. In a typical setting the `guardian` key is managed by an off-chain service to enable fraud monitoring (e.g. trusted contacts, daily limits, etc) and recovery.

The user can always opt-out of the guardian service and manage the guardian key himself. Alternatively he/she can add a second `guardian_backup` key to the account that has the same role as the `guardian` and can be used as the ultimate censorship resistance guarantee. The account can only have a `guardian_backup` when the `guardian` is set.

By default the account can execute a sequence of operations such as calling external contracts in a multicall. A multicall will fail if one of the inner call fails. Whenever a function of the account must be called (`change_owner`, `trigger_escape_guardian`, `upgrade`, etc), it should be the only call performed in this multicall.

In addition to the main `__execute__` entry point used by the Starknet protocol, the account can also be called by an external party via the `execute_from_outside` function to e.g. enable sponsored transactions. The calling party must provide a valid signature (`owner` and/or `guardian`) for the target execution.

Normal operations of the wallet (calling external contracts via `__execute__` or `execute_from_outside`, `change_owner`, `change_guardian`, `change_guardian_backup`, `cancel_escape`, `upgrade`) require the approval of the `owner` and a `guardian` to be executed.

Each party alone can trigger the `escape` mode (a.k.a. recovery) on the wallet if the other party is not cooperating or lost. An escape takes 7 days before being active, after which the non-cooperating party can be replaced. The escape expires 7 days after being active.

The wallet is asymmetric in favor of the `owner` who can override an escape triggered by a `guardian`.

A triggered escape can always be cancelled with the approval of the `owner` and a `guardian`.

We assume that the `owner` key is backed up such that the probability of the `owner` key being lost should be close to zero.

Under this model we can build a simple yet highly secure non-custodial wallet.

To enable that model to evolve the account can be upgraded. Upgrading the wallet to a new implementation requires the approval of both the `owner` and a `guardian`. At the end of the upgrade, a call to `execute_after_upgrade` is made on the new implementation of the account to perform some maintenance if needed (e.g. migrate state).

| Action                  | Owner | Guardian | Comments                                 |
| ----------------------- | ----- | -------- | ---------------------------------------- |
| Multicall               | X     | X        |                                          |
| Change Owner            | X     | X        |                                          |
| Change Guardian         | X     | X        |                                          |
| Change Guardian Backup  | X     | X        |                                          |
| Trigger Escape Guardian | X     |          | Can override an escape owner in progress |
| Trigger Escape Owner    |       | X        | Fail if escape guardian in progress      |
| Escape Guardian         | X     |          | After security period                    |
| Escape Owner            |       | X        | After security period                    |
| Cancel Escape           | X     | X        |                                          |
| Upgrade                 | X     | X        |                                          |

# Argent Multisig

## High-Level Specification

The Argent Multisig account is a typical n-of-m multisig. It requires multiple signatures from different parties to authorize any operation from the account.

The account is controlled by multiple owners (or `signers`). The number of owners that need to approve an operation is called the `threshold`.

This account leverages account abstraction, so the account can pay for its own transaction fees.

A valid account signature is a list of `threshold` individual owner signatures. This account signature can be used to validate a Starknet transaction or an off-chain message through the `is_valid_signature` method.

Any operation that changes the security parameters of the account, like adding/removing/changing owners, upgrading, or changing the threshold will also require the approval (signature) of `threshold` owners.

By default the account can execute a sequence of operations such as calling external contracts in a multicall. A multicall will fail if one of the inner call fails. Whenever a function of the account must be called (`add_signers`, `remove_signers`, `upgrade`, etc), it should be the only call performed in this multicall.

In addition to the main `__execute__` entry point used by the Starknet protocol, the account can also be called by an external party via the `execute_from_outside` function to e.g. enable sponsored transactions. The calling party must provide a valid account signature for the target execution.

## Signature format

The account signature is a list of owner signatures. The list must contain exactly `threshold` signatures and every owner can only sign once. Moreover, to simplify processing, the signatures need to be ordered by the owner public key, in ascending order.

## Self-deployment

The account can pay the transaction fee for its own deployment. In this scenario, the multisig only requires the signature of one of the owners.
This allows for better UX.

**For extra safety, it's recommended to deploy the account before depositing large amounts in the account**.

## Upgrade

To enable the model to evolve, the account implements an `upgrade` function that replaces the implementation. Calling this method, as any other method, requires the approval from `threshold` owners.
