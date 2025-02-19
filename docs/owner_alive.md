# Owner Alive Signature

## Overview

The "Owner Alive Signature" prevents **accidental bricking** of an account by requesting a recent signature from one of the remaining owners. This prevents from replacing the owner to a key that you don't control making the account unusable.

This signature will be requested when calling the `change_owner` function if both conditions are met:

- The **owner** that signed the transaction is **being removed** (otherwise the actual transaction signature proves the liveliness of the account)
- The account has **no guardians** (otherwise the guardian could be use to recover the account)

Note that there are still some way to brick the account like losing all the owner keys when there are no guardians. And the Owner Alive Signature is not trying to prevent all scenarios, only mitigate the risk of accidental bricking when changing owners

## How to sign an Owner Alive Message

The message to follow this SNIP-12 V1 typed data:

```javascript
{
  StarknetDomain: [
    { name: "name", type: "shortstring" },
    { name: "version", type: "shortstring" },
    { name: "chainId", type: "shortstring" },
    { name: "revision", type: "shortstring" },
  ],
  "Owner Alive": [
    { name: "Owner GUID", type: "felt" },
    { name: "Signature expiration", type: "timestamp" },
  ],
  primaryType: "Owner Alive",
  domain: {
    name: "Owner Alive",
    version: encodeShortString("1"),
    chainId: chainId,
    revision: 1
  },
  message: {
    "Owner GUID": ownerGuid,
    "Signature expiration": signatureExpiration,
  },
}
```

where:

- `ownerGuid` is the GUID of the owner that will sign the message
- `signatureExpiration` is the timestamp of the signature in seconds since the Unix epoch. The signature will be valid until this timestamp, but the timestamp can only be 24h in the future

The message will then be signed by one of the owners that are still valid after the modifications on `change_owner` are applied
