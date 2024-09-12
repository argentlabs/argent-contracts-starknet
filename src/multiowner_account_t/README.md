This iterates on the multiowner account to add a configurable threshold for the owners

- Avoiding accidental bricking:
  As opposed to the no threshold version, this account is more likely to get bricked. As a counter measure we could require a fresh signature after addingowners/removingowners/changing_owners/change threshold (only T owner sigs needed, we could skip the guardian sig)

- Recovery
  T owners can trigger the escaping the guardian (debateable decision, see recovery problem)
  Guardian recovering lost account: It will also reset the threshold to one (besides replacing all the owners with 1)

- Concise signatures (for devs and dexes)
  One more restriction, it only works if the threshold is 1

- Sessions
  In order to check if the owners that signed the auth are still them we need to know which owners signed it. There are two options:

  - store owners onchain: more expensive and complex
  - pass the owner guids as part of the signature: breaking change, makes the sessions more dependent on the account, less SNIPable



- MultiOwner Recovery problem
Increasing the threshold doesn't increase the security. For instance let's focus on an account with 2 owners and a threshold of 2

Losing one of the 2 owners means the only way to get hold of the account again is thought recovery. But that means the guardian can take over the account by recovering to the wrong owners and there is nothing the legitimate owner can do about it. In a way this is worse than having a threshold of 1 where losing 1 owner was meaningless.

  There could be a solution to this problem if we allow the other owner of the account to escape the guardian, but for that to happen we would need to allow 1 owner alone (threshold was 2) to trigger the guardian escape. I tried to generalize this approach below.

  NEW ESCAPE MECHANISM:

  This is an attempt to rethink the escape to leverage the extra owners in the account to provide extra safety to the users. Allowing them to control their accounts in some situations where it wasn't possible before. The tradeoff would be a more complex escape mechanism.

  There are two types of escape:

  - escape guardian: was restricted to "removing the guardian" for simplicity, no more escaping to a different guardian
  - escape owner: removes all owners and sets the threshold to 1
    Both can also be triggered by the guardian, the owners or even a mix owners and guardian

  There can be only one pending escape at a time
  Any regular action to manage the account with the normal threshold owner signatures + guardian (if any) will clear any pending escape

  Now let's define the priorities, or when one escape can override another escape

  In general:

  - More owners more certainty
  - Guardian signature is better than no guardian signature
  - Removing the guardian is always more important than replacing the owners

  To translate this into something more formal we can use this. An escape overrides another escape if

  - Contains more owner signatures then the previous escape. The minumum number of owner signature is threshold-1 (min 1). Or fallback to next step if the number of signature is the same
  - Contains a guardian signature when previous escape didn't. Or fallback to next step if they are the same
  - Is removing the the guardian when previous escape was escaping the owners. Allow if they where the same type

  For example with an account with 3 owners and threshold 2 and a guardian this will be all the possibilities sorted by priority

  - 2 owners + guardian (regular transaction, no timelock)
  - 3 owners
  - 2 owners
  - 1 owner + guardian
  - 1 owner
  - guardian

  When the number of owner is 1 it behaves the same as our current model
  In other cases:

  - it adds the possibility to recover account that lost the ability to reach the threshold, even with no guardian
  - allows multiple owners to overpower a bad guardian making the account more censorship resistance

  Some examples:
  threshold: 2, owners: 2, guardian: no
  One owner lost: today this would will be a lost account. But with this new mechanism one owner key can recover

  threshold: 1, owners: 2, guardian: yes
  censoring guardian + one compromised owner: lost with today's approach but can be saved only with new mechanism

  threshold: 2, owners: 2, guardian: yes
  lost owner: guardian can't take over the account (non custodial recovery)
  lost and compromised owner: guardian not incentivized to takeover the account
  censoring guardian + one lost owner: can be saved only with new mechanism
  censoring guardian + one compromised owner: can be saved only with new mechanism

  Drawbacks:

  - More reliance on timelocks. One bad owner can attempt to takeover the account. But maybe not too bad since users should already be monitoring the escapes
  - Complexity: Definitively harder to explain than today's approach. At least it's mostly backwards compatible if we don't want to leverage the new

Edge case
In the unlikely event where one owner is malicious and the guardian is not responsive, we could improve escaping so
2 owners can override a guardian escape triggered by 1 owner
????? what about gas griefing with bad owner?

Breaking changes:

- Added parameter with threshold to these methods:

```
fn constructor(owners: Array<Signer>, threshold: usize, guardian: Option<Signer>)
fn add_owners(owners_to_add: Array<Signer>, new_threshold: usize)
fn remove_owners(owners_to_remove: Array<Signer>, new_threshold: usize)
```

- New function `fn change_threshold(threshold: usize)`
- New events with the threshold
