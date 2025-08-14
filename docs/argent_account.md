---
icon: user-shield
---

# Argent Account

The Argent account is a custom multisig tailored for individuals.

There are two main roles, the owners and the guardians. The **owners** represent keys controlled by the user. The account must have at least one owner. The **guardians** are optional and can be used to add an extra layer of security.

## Account with no guardians

When the account has no guardians, it behaves like a 1-of-N multisig. The account requires **one owner signature** for any operation.

## Account with guardians

When the account has at least one guardian, it requires **one owner** signature **AND one guardian** signature (unless calling [escape methods](argent_account_escape.md#escape-methods)).

The guardian keys are not typically managed by the user directly, but by a 3rd party which the user trusts (the trust only extends to some degree as the guardian alone can't control the account)

Guardians provide the following **advantages**:

* Allow to recover the account if the owner **keys are lost** (see Escape Process below)
* Protect the account against **compromised owners keys** (for instance the user entering their private keys in a phishing website)
* **Fraud prevention**: The guardian can request extra confirmations if some transaction seems suspicious

### Escape Process (Recovery)

* Allows the guardians to recover the account if the owner keys are lost. Without the guardians, the account would be lost if the owner keys are lost.
* Allows the owners to remove or change the guardians if they are not cooperating. Bringing censorship resistance to the account

See more about the escape process in [Escape Process](argent_account_escape.md)

### Admin calls

The account can **call itself** to perform admin operations like changing the owners, upgrading to a new implementation, setting up guardians, escape... When the account is calling itself, it must be the **only call** performed in this multicall or the transaction will be rejected.

## Signer types

Multiple signer types are allowed for both owners and guardians.

There's more information about it in [**Signer Types**](signers_and_signatures.md#multiple-signer-types).

## Signature format

* **Regular transactions**:
  * Account has no guardians: The account expects a signature from one of the owners
  * Account with guardians: The account require a signature from one of the owners and one from one of the guardians. Owner signature goes first.
*   **Escape transactions**:

    For transactions calling `trigger_escape_guardian`, `trigger_escape_owner`, `escape_guardian`, `escape_owner` (See [Escape Methods](argent_account_escape.md#escape-methods)), the account expects a signature from one party only.

Depending on the above the account receives signatures from one or two signers. The account accepts two formats for the combined signature:

### Standard Format (Recommended)

The final signature is serialized as an `Array<SignerSignature>` (even if there's only one signer)

Here's an example of a regular transaction for an account **without guardians**:

```
0x000001 // number of signatures in the array (1, owner only)
         // First Signer Signature from the owner
0x000000 // Owner signature type (0x0 means Starknet)
0xAAAAAA // owner pubkey
0xAAA001 // owner signature r
0xAAA002 // owner signature s
```

Here is an example of a regular transaction with **guardians**:

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

More details in [**Signatures**](signers_and_signatures.md#signatures)

### Concise Format

Besides the format specified above, the argent account also supports concise signatures if these two conditions are met:

* There is only one owner and it's a StarknetSigner
* There is no guardian or there's only one guardian and it's a StarknetSigner

**⚠️** The use of concise signatures is **discouraged** as they will stop working more than one owner or guardian is added to the account

The format of the concise signatures is the following:

`[single_owner_r, single_owner_s]`,

`[single_guardian_r, single_guardian_s]` or

`[single_owner_r, single_owner_s, single_guardian_r, single_guardian_s]`

The first format is intended to help the account be compatible with dev tools and will be supported.

The last two formats are deprecated and likely to be removed in future versions

## Accurate Estimates

The argent multisig can do accurate estimates for transactions with Signers that use significant resources during validations. This also supports accurate estimates for sessions.

See [Accurate Estimates](accurate_estimates.md) for more information.

## Outside Execution

Allows meta-transactions by leveraging offchain signatures

See [Outside Execution](outside_execution.md)

## Sessions

Sessions allow dapps to submit transactions on behalf of the user without requiring any user interaction, as long as the transaction to execute follows some restrictions defined when the session is created. This will allow for a better UX in areas such a gaming

See [Sessions](sessions.md)

## Upgrades

See [Upgrades](argent_account_upgrades.md)

**⚠️** Make sure you read this document before upgrading you account, as incorrect upgrades can brick the account

## Owner Alive Signature

To prevent from accidentally bricking the account by changing the owner to some key they don't control, the account will require a signature in the `change_owner` function. See [Owner Alive Signature](owner_alive.md) for more information.

## Release Notes

Find the Argent Account Release notes [here](CHANGELOG_argent_account.md)

## Deployments

Deployed class hashes can be found here for the [Argent Account](../deployments/account.txt)

Other deployment artifacts are located in [/deployments/](../deployments/)
