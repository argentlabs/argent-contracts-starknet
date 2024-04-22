# Argent Account

## High-Level Specification

The Argent account is a custom multisig (1-of-1, 2-of-2 or 2-of-3) tailored for individuals.

The primary key called the `owner` is typically stored on the user's device. A second key called the `guardian` acts both as a co-validator for typical operations of the wallet, and as the trusted actor that can recover the wallet in case the `owner` key is lost or compromised. In a typical setting the `guardian` key is managed by an off-chain service to enable fraud monitoring (e.g. trusted contacts, daily limits, etc) and recovery.

The user can always opt-out of the guardian service and manage the guardian key himself. Alternatively he/she can add a second `guardian_backup` key to the account that has the same role as the `guardian` and can be used as the ultimate censorship resistance guarantee. The account can only have a `guardian_backup` when the `guardian` is set.

By default the account can execute a sequence of operations such as calling external contracts in a multicall. A multicall will fail if one of the inner call fails. Whenever a function of the account must be called (`change_owner`, `trigger_escape_guardian`, `upgrade`, etc), it should be the only call performed in this multicall.

In addition to the main `__execute__` entry point used by the Starknet protocol, the account can also be called by an external contract via the `execute_from_outside` function to e.g. enable sponsored transactions. The calling contract must provide a valid signature (`owner` and/or `guardian`) for the target execution.

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

## Signer types

There's more information about it in [Signers](./signers_and_signatures.md#Multiple_Signer_Types).
This account restricts the guardian role to only StarknetSigner. Note that the guardian backup supports every type

## Signature format

The information available in [Signatures](./signers_and_signatures.md#Signatures) is also applicable for the argent account.

Additionally, this account also supports providing signatures in a concise way when al signers involved are StarknetSigners

The account will accept the format
[first_signer_r, first_signer_s]

And also
[first_signer_r, first_signer_s, second_signer_r, second_signer_s]

## Change owner signature

To prevent mistakes where someone changes the owner to some key they don't control, the account will require a signature from the new owner as an argument to the `change_owner` function.

New owner should sign the pedersen hash of the array: `[change_owner_selector, chain_id, account_address, old_owner_guid]`

## Outside Execution

See [Outside Execution](./outside_execution.md)

## Sessions

See [Sessions](./sessions.md)

## Upgrades

See [Upgrades](./argen_account_upgrades.md)
