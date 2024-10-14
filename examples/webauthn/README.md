# Argent Webauthn POC

This account is using the ArgentAccount without a guardian. The signature follows the WebAuthn standard.

## Setup for testnet

```bash
cp .env.example .env
```

Fill the values in the `.env` file. The deployer account needs at least 0.001 ETH to deploy a few webauthn accounts.

```bash
yarn && yarn dev
```

Open the displayed url.

## Setup for website with devnet

Start by installing a service that allows you to expose your localhost to the internet (e.g., [Ngrok](https://ngrok.com/docs/getting-started/), Localtunnel, etc.).  
Important: This service must provide an HTTPS connection; otherwise, WebAuthn will not work.

Run the following command to start the devnet:

```bash
scarb run start-devnet
```

Start your tunneling service and configure it to expose port `5173`.  
Copy the URL provided by your tunneling service, append /rpc to the end, and update the .env file of the dApp with this value:

```
PUBLIC_PROVIDER_URL="[YOU_LINK]/rpc"
```

Now, you can start the dApp by running `yarn dev`. You should be able to access the dApp through the link provided by the tunneling service.

## Testing

Some parts of the testing process cannot be automated, so manual testing is required.
Below is a list of scenarios that need to be tested. Please add any additional cases if you find them missing:
Here is the list of everything that needs to be tested (please add more if you find any missing case):

- Test every on every major browser (sorted by most used)
  - [ ] Chrome
  - [ ] Safari
  - [ ] IE (just kidding, Edge)
  - [ ] Firefox
  - [ ] Opera
- Test using every password manager
  - [ ] 1Password
  - [ ] Chrome integrated password
  - [ ] Apple Keychain
- Test the dApp on different device platforms
  - [ ] Apple (iPhone)
  - [ ] Android

Make sure to test various combinations of browsers, password managers, and devices to ensure compatibility across all configurations.

To test the cross-platform part, as the public keys are stored locally (LocalStorage), please fill in the username and the public key field.

## Pointers

This demo dapp will:

- [Create a webauthn passkey](./src/routes/+page.svelte#L19) using the brower's native APIs.
- Declare the account contract (if needed).
- [Deploy an account](./src/routes/+page.svelte#L23) with the webauthn passkey as a signer.
- [Send a transaction](./src/routes/+page.svelte#L27) by signing it with the passkey.

Other notes:

- The passkey is created [here](./src/lib/webauthnAttestation.ts#L12).
- Transaction hashes are signed by the passkey [here](./src/lib/webauthnOwner.ts#L112).
- A high level starknet.js `Signer` implementation is proposed [here](./src/lib/webauthnOwner.ts).
