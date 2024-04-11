# Multisig Recovery

A multisig account might become unusable if a number of owner keys as lost. For instance, a multisig with 3 owners and threshold of 3 will be unable to perform any transaction if any of the 3 owner loses their keys.

To prevent this scenario, account owner can setup the recovery mechanism, which is turned off by default. To turn it on, owners will define:

- a security period
- an expiration period
- a guardian address

The guardian can be another multisig or any other account on Starknet, the account owners give the guardian the power to trigger escapes at any time, but the owners can still cancel the escape and change/remove the guardian as long as they have enough signatures.

When the recovery is needed. The guardian can submit a transaction to trigger the escape. The transaction needs to be submitted from the address specified when recovery is enabled. In this transaction the guardian will specify how to recover the account. The options are calling one of this four methods on the multisig:

- `replace_signer`
- `change_threshold`
- `add_signers`
- `remove_signers`

Then the security period starts, during this time, the owners can cancel the escape if they don't agree with the guardian.
After the security period, anybody can complete the escape by submitting a second transaction to confirm it. Then, the call enqueued when the escape was triggered will be executed.

If the escape is not executed during the expiration period, the escape can't be executed. A new escape can be triggered if needed
