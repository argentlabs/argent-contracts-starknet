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

## Setup for website with devnet

First start by installing a service allowing to expose localhost to the world (e.g.: ngrok, localtunnel, ...).  
Please note that this service MUST provide an HTTPS connection otherwise webauthn won't work.


Start the devnet using 
```bash
scarb run start-devnet
```

Start your tunneling service exposing port 5173.  
Now take the link given by your service and edit the .env file of the dapp adding `/rpc` at the end:
```
PUBLIC_PROVIDER_URL="[YOU_LINK]/rpc"
```

You can now start the dapp using `yarn dev`. You should now be able to access the dapp using the link provided by the tunneling service.

## Testing

Part of this can't be automated and some manual tests need to be performed.  
Here is the list of everything that needs to be tested (please add more if you find any missing case):

- Test every on every major browser (sorted )
  - [ ] Chrome
  - [ ] Safari
  - [ ] IE (just kidding, Edge)
  - [ ] Firefox
  - [ ] Opera
- Test using every password manager
  - [ ] One password
  - [ ] Chrome integrated password
  - [ ] Apple Keychain
- Test using every device
  - [ ] Apple
  - [ ] Android

Make sure to test every combination of each.

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
