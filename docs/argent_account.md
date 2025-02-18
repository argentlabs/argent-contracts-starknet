# Argent Account

## High-Level Specification

The Argent account is a custom multisig tailored for individuals.

There are two main roles, the owners and the guardians. The account must have at least one owner. The guardians are optional.
The owner represent keys controlled but the user. And the guardians acts both as a co-validators for typical operations of the wallet, and as trusted actors that can recover the wallet in case the `owner` keys are lost or compromised. The guardians key is not typically managed by the owner directly, but by a 3rd party which the owner trusts.

By default the account can execute a sequence of operations such as calling external contracts in a multicall. A multicall will fail if one of the inner call fails. Whenever a function of the account must be called (`change_owner`, `trigger_escape_guardian`, `upgrade`, etc), it should be the only call performed in this multicall.

In addition to the main `__execute__` entry point used by the Starknet protocol, the account can also be called by an external contract via the `execute_from_outside` function to e.g. enable sponsored transactions. The calling contract must provide a valid signature (`owner` and/or `guardian`) for the target execution.

Normal operations of the wallet (calling external contracts via `__execute__` or `execute_from_outside`, `reset_owners`, `reset_guardians`, `cancel_escape`, `upgrade`) require the approval of one `owner` and one `guardian` (if the account has any)

One role (owner or guardian) alone can also trigger the `escape` mode (a.k.a. recovery) on the wallet if the other role is not cooperating or lost. You need to wait for the security period to elapse before the escape is active. Then the non-cooperating role can be replaced. If another security period elapses where the escape is not completed, it will expire. The default security period is 7 days but it can be defined by the user.

The wallet is asymmetric in favor of the owners who can override an escape triggered by a guardian.

A triggered escape can always be cancelled with the approval of one `owner` and one `guardian`.

We assume that one `owner` key is backed up such that the probability of the `owner` key being lost should be close to zero.

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

Adding multiple guardians can also be used as the as the ultimate censorship resistance guarantee.

## Signer types

There's more information about it in [Signers](./signers_and_signatures.md#Multiple_Signer_Types).

## Signature format

- Regular transactions:
    * Account has no guardians: the account expects a signature from one of the owners
    * Account with guardians: The account require a signature from one of the owners and one from one of the guardians. Owner signature goes first.
- Escape transactions: In accounts with guardians. Accounts that are triggered by just one owner or one signer.
    * Calling `trigger_escape_guardian` or `escape_guardian` Requires a signature from just one of the owners
    * Calling `trigger_escape_owner` or `escape_owner` Requires a signature from just one of the guardians

Depending on the above the account receives signatures from one or two signers. The account accepts two formats for the combined signature:

### Recommended Format
The information available in [Signatures](./signers_and_signatures.md#Signatures) is also applicable for the argent account. The first signature is the owner and the second one is the guardian (if the account has any guardian)

Here's an example of a regular transaction for an account without guardians:

```
0x000001 // number of signatures in the array (1, owner only)
         // First Signer Signature from the owner
0x000000 // Owner signature type (0x0 means Starknet)
0xAAAAAA // owner pubkey
0xAAA001 // owner signature r
0xAAA002 // owner signature s
```

Here is an example of a regular transaction with one owner and one guardian:

```
0x000002 // number of signatures in the array (2, one from the owner and one from the guardian)
         // First Signer Signature from the owner
0x000000 // Owner signature type (0x0 means Starknet)
0xAAAAAA // owner pubkey
0xAAA001 // owner signature r
0xAAA002 // owner signature s
         // Second signature is the guardian 
0x000000 // Guardian signature type (0x0 means Starknet)
0xBBBBBB // guardian pubkey
0xBBB001 // guardian signature r
0xBBB002 // guardian signature s
```

### Concise Format

Besides the format specified here, the argent account also supports concise signatures if these two conditions are met:

- There is only one owner and it's a StarknetSigner
- There is no guardian or there's only one guardian and it's a StarknetSigner

**⚠️** The use of concise signatures is **discouraged** as they will stop working more than one owner or guardian is added to the account

The format of the concise signatures is the following:
`[signer_r, signer_s]`

And also
`[single_owner_r, single_owner_s, single_guardian_r, single_guardian_s]`

## Accurate Estimates

The argent multisig can accurate estimates for transactions with Signers that use significant resources during validations. This also supports accurate estimates for sessions. See [Accurate Estimates](./accurate_estimates.md) for more information.

## Owner Alive Signature

To prevent from accidentally bricking the account by changing the owner to some key they don't control, the account will require a signature in the `change_owner` function. See [Owner Alive Signature](./owner_alive.md) for more information.

## Outside Execution

See [Outside Execution](./outside_execution.md)

## Sessions

See [Sessions](./sessions.md)

## Upgrades

See [Upgrades](./argen_account_upgrades.md)
