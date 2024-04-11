# Argent Account Upgrade

This documents covers the upgrade process starting with version 0.2.3

In general downgrading is not supported, but it won't always be enforced

Depending on the versions, some upgrades might cancel an ongoing escape, and it might need to be triggered again after the upgrade.
This shouldn't be a security risk since two signatures are needed to perform an upgrade when there's a guardian set.

When upgrading to a version >=0.3.0, it's possible to bundle the upgrade with a multicall. The only restriction is that the multicall can't make any calls to the account

To do that you need to  serialize the calls to perform after the upgrade as `Array<Call>` and pass the serialized calls to `upgrade`.

## Upgrading from v0.2.3.* to >=0.3.0

**⚠️ WARNING ⚠️** It's important to pass some non-empty `calldata` to the upgrade method

The upgrade function on v0.2.3.* looks like
```
func upgrade(implementation: felt, calldata_len: felt, calldata: felt*)
```
if `calldata_len` is 0 it will look like it’s working, but the proxy won’t be removed and account will stop working after Starknet regenesis. So calldata should be at least an empty array

## Upgrading from versions < 0.2.3
You need to upgrade to 0.2.3.1 and then perform another upgrade