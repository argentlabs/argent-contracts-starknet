# Argent Multisig

## High-Level Specification

The Argent Multisig account is a typical n-of-m  multisig that requires multiple signatures from different parties to authorize any operations. This helps to increase security as the account can still be safe even if one party gets compromised.

The account is controlled by multiple owners (or `signer`), and to generate a valid account signature you need at least some number of owner signatures. The minimum number of owners that need to sign is called the `threshold`.

This account leverages account abstraction, so the account can pay for its own transaction fees.

A valid account signature is just a list of many individual owner signatures. This account signature can be used as a Starknet transaction signature or in the `is_valid_signature` method.

Any operation that changes the security parameters, like adding/removing/changing owners, upgrading, or changing the threshold will also require the approval (signature) of enough owners (current threshold).

## Signature format

The account signature is a list of owner signatures. The list must contain exactly `threshold` signatures and every owner can only sign once. Moreover, to simplify processing, the signatures need to be ordered by the owner public key, in ascending order.

## Self-deployment

The account can pay the transaction fee for its own deployment. In this scenario, the multisig only requires the signature of one of the owners.
This allows for better UX.

**For extra safety, it's recommended to deploy the account before depositing large amounts in the account**.

## Upgrade

To enable the model to evolve, the account implements an `upgrade` method that replaces the implementation. Calling this method, as any other method, requires the approval from `threshold` owners.
