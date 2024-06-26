# Argent Multisig

## High-Level Specification

The Argent Multisig account is a typical n-of-m multisig. It requires multiple signatures from different parties to authorize any operation from the account.

The account is controlled by multiple owners (or `signers`). The number of owners that need to approve an operation is called the `threshold`.

This account leverages account abstraction, so the account can pay for its own transaction fees.

A valid account signature is a list of `threshold` individual owner signatures. This account signature can be used to validate a Starknet transaction or an off-chain message through the `is_valid_signature` method.

Any operation that changes the security parameters of the account, like adding/removing/changing owners, upgrading, or changing the threshold will also require the approval (signature) of `threshold` owners.

By default the account can execute a sequence of operations such as calling external contracts in a multicall. A multicall will fail if one of the inner call fails. Whenever a function of the account must be called (`add_signers`, `remove_signers`, `upgrade`, etc), it should be the only call performed in this multicall.

In addition to the main `__execute__` entry point used by the Starknet protocol, the account can also be called by an external party via the `execute_from_outside` function to e.g. enable sponsored transactions. The calling party must provide a valid account signature for the target execution.

## Signer types

There's more information about it in [Signers](./signers_and_signatures.md#Multiple_Signer_Types).

## Signature format

The information available in [Signatures](./signers_and_signatures.md#Signatures) is also applicable for the argent multisig.
The array provided as a signature must contain exactly `threshold` signatures and every owner can only sign once. Moreover, to simplify processing, the signatures need to be ordered by signer guid, in ascending order.

## Self-deployment

The account can pay the transaction fee for its own deployment. In this scenario, the multisig only requires the signature of one of the owners.
This allows for better UX.

**For extra safety, it's recommended to deploy the account before depositing large amounts in the account**.

## Upgrade

To enable the model to evolve, the account implements an `upgrade` function that will delegate the upgrade to the new class_hash. Calling this method, as any other method, requires the approval from `threshold` owners.

## Outside Execution

See [Outside Execution](./outside_execution.md)

## Recovery

Theres is an opt-in feature to enable recovering lost accounts. See [Multisig Recovery](multisig_recovery.md)
