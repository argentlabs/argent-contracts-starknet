# Sessions

Sessions allow dapps to submit transactions on behalf of the user without requiring any user interaction, as long as the transaction to execute follows some restrictions defined when the session is created. This will allow for a better UX in areas such a gaming

This feature is only available to argent account where there's a guardian

Many of these restrictions are guaranteed onchain by the contract but others could rely on the account guardian.

In order to start a session a dapp must generate a key pair (dapp key), and request the account to sign an offchain message with the session parameters.

If the message is signed, then the dapp trigger transaction without user interactions using the session signed in the previous step, plus a guardian and a dapp key signature for every new transaction

![Sessions diagram](session.png)

### Offchain checks by guardian:

- Session expiration
- Anything included in the `Metadata` field

### Onchain checks by the account:

- Methods to call
- Backend and dapp signatures
- Check if session is revoked (see [Session Revocation ](#session-revocation))
- Session expiration: it can only be done with some level precision during validation because of starknet restrictions to timestamps during validation, but the check will be also performed on execution with a more accurate timestamp. This could allow the dapp to perform some gas griefing but it is mitigated by the fact the guardian is also performing the check offchain

### Session revocation:

Session revocation is done via the `revoke_session` function, which accepts the hash of the session request. A SessionRevoked event is emitted once this happens. There is also a view method that can be used, `is_session_revoked` which returns a bool for a given session hash

```
/// Event emitted on revocation
struct SessionRevoked {
  session_hash: felt252,
}

/// Method to revoke a session
fn revoke_session(session_hash: felt252)

/// Method to check is a session is revoked
fn is_session_revoked(session_hash: felt252) -> bool
```

### Examples

There are some examples in typescript about how to use this feature [here](../lib/session/) and [here](../tests-integration/sessionAccount.test.ts)
