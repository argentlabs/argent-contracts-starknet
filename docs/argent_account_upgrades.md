---
icon: chevrons-up
---

# Upgrades

**⚠️ IMPORTANT ⚠️** Make sure you read this document before upgrading you account, as incorrect upgrades can brick the account

This documents covers the upgrade process starting with version 0.2.3

In general downgrading is not supported, but it won't always be enforced onchain

Depending on the versions, some upgrades might cancel an ongoing escape, and it might need to be triggered again after the upgrade. This shouldn't be a security risk since the two roles (owners and guardians) need to sign an upgrade when there's a guardian set.

## Upgrading from v0.2.3.\* to >=0.3.0

**⚠️ IMPORTANT ⚠️** Upgrading from v0.2.3. to any version >=0.4.0 can make the **account unusable** and unable to be recovered which. It will lead to losing funds

The only safe way to upgrade from v0.2.3.\* is to upgrade to **v0.3.1** first, and then perform another upgrade to the desired version.

Upgrading from v0.2.3.\* to v0.3.1 also needs to be done carefully. It's **required** to pass some non-empty `calldata` to the upgrade method

The upgrade function on v0.2.3.\* looks like

```
func upgrade(implementation: felt, calldata_len: felt, calldata: felt*)
```

if `calldata_len` is 0 it will look like it’s working, but the proxy won’t be removed and account will stop working after Starknet regenesis or create other issues. So calldata must be at least an empty array.

Upgrading with `calldata_len = 0` is not supported by Argent and it's not a valid upgrade flow, we cannot guarantee that the account will be recoverable. However, if you upgraded the account to version v0.5.0 using the wrong parameters, it might be possible to recover it by calling the `recovery_from_legacy_upgrade` method using another contract. Please note that this method is not guaranteed to be available in future versions.

After the upgrade to v0.3.1 is done, the account can follow the regular upgrade process to update to the desired version.

## Upgrading from versions < 0.2.3

You need to upgrade to 0.2.3.1 and then perform another upgrade

### Bundle upgrade with multicall

When upgrading to a version >=0.3.0, it's possible to bundle the upgrade with a multicall. The only restriction is that the multicall can't make any calls to the account itself.

To do that you need to serialize the calls to perform after the upgrade as `Array<Call>` and pass the serialized calls to `upgrade`.
