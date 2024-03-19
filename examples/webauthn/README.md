# Argent Webauthn POC

This account is a 1-of-2 multisig account where the signers are a stark key and a webauthn device.

## Setup for testnet

```bash
cp .env.example .env
```

Fill the values in the `.env` file. The deployer account needs at least 0.001 ETH to deploy a few webauthn accounts.

```bash
yarn && yarn dev
```

Open the displayed url in Chrome or Safari.

## Pointers

This demo dapp will:

- [Create a webauthn passkey](./src/routes/+page.svelte#L19) using the brower's native APIs.
- Declare the account contract (if needed).
- [Deploy an account](./src/routes/+page.svelte#L23) with the webauthn passkey as a signer.
- [Send a transaction](./src/routes/+page.svelte#L27) by signing it with the passkey.

Other notes:

- The passkey is created [here](./src/lib/webauthnAttestation.ts#L12).
- Transaction hashes are signed by the passkey [here](./src/lib/webauthnAssertion.ts#L24).
- A high level starknet.js `Signer` implementation is proposed [here](./src/lib/webauthnOwner.ts).
