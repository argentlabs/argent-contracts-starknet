# About

This technical documentation provides a comprehensive guide to the **Argent Account** and **Argent Multisig** smart contracts, which are secure, customizable smart wallets designed for the Starknet ecosystem. The **Argent Account** is tailored for individual users, offering features like guardians for added security and recovery options, while the **Argent Multisig** is a robust n-of-m multisig implementation that requires multiple signatures to authorize transactions. Both systems leverage Starknet's account abstraction, allowing the accounts to pay for their own transaction fees.

### Key Topics

* **Account Roles**: The distinction between owners and guardians, with guardians providing additional security and recovery options.
* **Escape Process**: A mechanism for recovering accounts if owner keys are lost or if guardians need to be changed.
* **Accurate Estimates**: Methods for simulating transactions to provide accurate gas estimates without requiring real signatures.
* **Upgrades**: Guidelines for safely upgrading account implementations, with warnings about potential risks.
* **Signatures**: Detailed information on signature formats and requirements for different types of transactions.
* **Recovery**: Options for recovering multisig accounts if owner keys are lost, including the use of guardians.

The documentation also includes deployment details, release notes, and references to related files for further reading.&#x20;
