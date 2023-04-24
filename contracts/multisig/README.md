# Argent Multisig on Starknet

_Warning: This project is still in alpha. It has not been audited yet and should not be used to store significant value._

# Overview

This account requires multiple signatures from different parties to authorize any operations. This helps to increase security as the account can still be safe even if one party gets compromised.


The account is controlled by multiple owners (or `signer`), and to generate a valid account signature you need at least some number of owner signatures. The minimum number of owners that need to sign is called the `threshold`.

A valid account signature is just a list of many individual owner signatures. And this account signature can be used to sign a Starknet transaction or be used in the method `is_valid_signature`

Any operation that changes the security parameters, like adding/removing/changing owners, upgrading, or changing the threshold will also require the approval (signature) of some owners (threshold)

## Self-deployment

The account can pay for the tx fee for its own deployment. In this scenario, the multisig only requires the signature of one of the owners.
This allows for better UX. For extra safety, it's recommended to deploy it before depositing large amounts in the account.


## Upgrade
To enable the model to evolve if needed, the implements an `upgrade` method that will replace the implementation. Calling this method, as any other method, requires the approval from a quorum of owners (`threshold`)

