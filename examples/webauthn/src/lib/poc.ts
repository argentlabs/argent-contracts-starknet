import { Account, CairoOption, CairoOptionVariant, CallData, hash, uint256 } from "starknet";
import accountCasm from "./argent_ArgentAccount.compiled_contract_class.json";
import accountSierra from "./argent_ArgentAccount.contract_class.json";
import { buf2hex, hex2buf, hexStringToUint8Array } from "./bytes";
import { ArgentSigner } from "./signers";
import { fundAccount, getEthContract, loadDeployer, type ProviderType } from "./starknet";
import { WebauthnAttestation, createWebauthnAttestation, requestSignature } from "./webauthnAttestation";
import { WebauthnOwner } from "./webauthnOwner";

const storageKey = "webauthnAttestation";

export async function cleanLocalStorage() {
  localStorage.removeItem(storageKey);
}

export function printLocalStorage() {
  console.log(getStoredAttestations());
}

function getStoredAttestations(): WebauthnAttestation[] {
  let storedArray = localStorage.getItem(storageKey);
  if (!storedArray) {
    storedArray = "[]";
  }
  const unparsedArray = JSON.parse(storedArray);
  return unparsedArray.map((attestation: any) => {
    attestation.pubKey = hex2buf(attestation.encodedX);
    delete attestation.encodedX;
    attestation.credentialId = hex2buf(attestation.encodedCredentialId);
    delete attestation.encodedCredentialId;
    return attestation;
  });
}

export async function retrievePasskey(
  email: string,
  rpId: string,
  origin: string,
  pubKey: string | undefined,
): Promise<WebauthnOwner | undefined> {
  console.log("retrieving webauthn key for email", email);
  console.log(getStoredAttestations());
  let attestation = getStoredAttestations().find((attestation) => {
    return attestation.email == email;
  });

  if (!attestation) {
    attestation!.email = email;
    attestation!.origin = origin;
    attestation!.rpId = rpId;
    // TODO assert there is a pubkey
    attestation!.pubKey = hexStringToUint8Array(pubKey!);
  }

  try {
    // Backend should provide pubkey
    const credential = await navigator.credentials.get({
      mediation: "optional",
      publicKey: {
        challenge: new Uint8Array(32),
        userVerification: "preferred",
      },
    });
    if (!credential) {
      return undefined;
    }
    // TODO Do some checks against retrieved credential
    return new WebauthnOwner(attestation!, requestSignature);
  } catch (err) {
    return undefined;
  }
}

export async function createOwner(email: string, rpId: string, origin: string): Promise<WebauthnOwner> {
  console.log("creating webauthn key (attestation)...");
  const attestation = await createWebauthnAttestation(email, rpId, origin);

  const encodedCredentialId = buf2hex(attestation.credentialId);
  const encodedX = buf2hex(attestation.pubKey);
  const storedArray = localStorage.getItem(storageKey) || "[]";
  const storedAttestations = JSON.parse(storedArray);
  storedAttestations.push({ email, rpId, origin, encodedX, encodedCredentialId });
  localStorage.setItem(storageKey, JSON.stringify(storedAttestations));
  console.log("created webauthn public key:", buf2hex(attestation.pubKey));
  return new WebauthnOwner(attestation, requestSignature);
}

export async function declareAccount(provider: ProviderType): Promise<string> {
  const deployer = await loadDeployer(provider);

  const { class_hash: accountClassHash, transaction_hash: accountTransactionHash } = await deployer.declareIfNot(
    { casm: accountCasm, contract: accountSierra },
    { maxFee: 1e17 },
  );

  if (accountTransactionHash) {
    const res = await provider.waitForTransaction(accountTransactionHash);
    console.log("account declare transaction", accountTransactionHash, "completed", res);
  }
  return accountClassHash;
}

export async function retrieveAccount(
  classHash: string,
  webauthnOwner: WebauthnOwner,
  provider: ProviderType,
): Promise<Account | undefined> {
  const constructorCalldata = CallData.compile({
    owner: webauthnOwner.signer,
    guardian: new CairoOption(CairoOptionVariant.None),
  });
  const addressSalt = 12n;
  const accountAddress = hash.calculateContractAddressFromHash(addressSalt, classHash, constructorCalldata, 0);
  const account = new Account(provider, accountAddress, new ArgentSigner(webauthnOwner), "1");
  // This fails silently if the account does not exist, which is good enough
  await account.getNonce();
  return account;
}

export async function deployAccount(
  classHash: string,
  webauthnOwner: WebauthnOwner,
  provider: ProviderType,
): Promise<Account> {
  const constructorCalldata = CallData.compile({
    owner: webauthnOwner.signer,
    guardian: new CairoOption(CairoOptionVariant.None),
  });
  const addressSalt = 12n;
  const accountAddress = hash.calculateContractAddressFromHash(addressSalt, classHash, constructorCalldata, 0);

  await fundAccount(accountAddress, 5e14, provider);

  const account = new Account(provider, accountAddress, new ArgentSigner(webauthnOwner), "1");

  console.log("deploying account to address", accountAddress);
  const response = await account.deploySelf({ classHash, constructorCalldata, addressSalt }, { maxFee: 4e14 });
  console.log("waiting for deployment tx", response.transaction_hash);
  await provider.waitForTransaction(response.transaction_hash);
  console.log("deployed");
  return account;
}

export async function transferDust(account: Account, provider: ProviderType): Promise<string> {
  const ethContract = await getEthContract(provider);
  ethContract.connect(account);
  const recipient = 69;
  const amount = uint256.bnToUint256(1);
  const response = await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee: 1e14 });
  return response.transaction_hash;
}
