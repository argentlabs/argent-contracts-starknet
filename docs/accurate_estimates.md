# Accurate Estimates

When sending a transaction to the network, the sender needs to provide gas limits. These limits are typically calculated by simulating the transaction first and adding some overhead to account for gas price fluctuations and resource usage variations.

## The Problem

There are two common approaches to transaction simulation, each with drawbacks:

1. **Skip Validation**: Using the `SKIP_VALIDATE` flag allows to simulate without signatures by skipping the validation phase. This  results in low estimates and it can lead to failed transactions if the overhead is not enough to cover the validation work. The error can happen frequently when the resources uses for validations are higher, for instance to validate Webauthn Signers, or multisigs with a high threshold.

2. **Real Signatures**: While more accurate, using real signatures for estimation is problematic because:
   - It might require user interaction (WebAuthn, hardware wallets)
   - Signatures may need need to be requested from multiple parties
   - Signing transactions not meant for submission poses security risks

## The Solution

Therefore, the argent accounts implement a solution to provide an accurate estimate without having to use the real signatures. The clients use the a different transaction version for simulation (`0x100000000000000000000000000000000` + the real transaction version) And provide a mock signature. This way, the smart contract knows it's just a simulation and will do its best to consume the same resources as if the transaction was valid. The mock signature still need to indicate real account signers with with a valid format, but the actual value signed is not checked.

There are some examples that can serve as reference here:

- [accountEstimates.test.ts](../tests-integration/account/accountEstimates.test.ts)
- [sessionAccount.test.ts](../tests-integration/session/sessionAccount.test.ts)
