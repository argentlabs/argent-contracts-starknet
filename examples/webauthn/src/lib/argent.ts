import { Account, CairoOption, CairoOptionVariant, CallData, Contract, hash, uint256 } from "starknet";
import casm from "./argent_ArgentAccount.compiled_contract_class.json";
import sierra from "./argent_ArgentAccount.contract_class.json";
import { buf2hex } from "./bytes";
import { fundAccount, loadContract, loadDeployer, randomKeyPair, type KeyPair, type ProviderType } from "./starknet";
import { sha256 } from "./webauthnAssertion";
import { createWebauthnAttestation } from "./webauthnAttestation";
import { WebauthnOwner, webauthnSigner } from "./webauthnOwner";

export interface ArgentOwners {
  starkOwner: KeyPair;
  webauthnOwner: WebauthnOwner;
}

export interface ArgentWallet extends ArgentOwners {
  account: Account;
  accountContract: Contract;
}

export async function createOwners(email: string, rpId: string): Promise<ArgentOwners> {
  const starkOwner = randomKeyPair();
  console.log("creating webauthn key (attestation)...");
  const attestation = await createWebauthnAttestation(email, rpId);
  console.log("created webauthn public key X:", buf2hex(attestation.x));
  const webauthnOwner = new WebauthnOwner(attestation);
  return { starkOwner, webauthnOwner };
}

export async function declareAccount(provider: ProviderType): Promise<string> {
  const deployer = await loadDeployer(provider);
  console.log("deployer is", deployer.address);
  const { class_hash, transaction_hash } = await deployer.declareIfNot({ casm, contract: sierra });
  if (transaction_hash) {
    await provider.waitForTransaction(transaction_hash);
  }
  return class_hash;
}

export async function deployAccount(
  classHash: string,
  { starkOwner, webauthnOwner }: ArgentOwners,
  rpId: string,
  provider: ProviderType,
): Promise<ArgentWallet> {
  const rpIdHash = await sha256(new TextEncoder().encode(rpId));

  const constructorCalldata = CallData.compile({
    owner: webauthnSigner(location.origin, buf2hex(rpIdHash), buf2hex(webauthnOwner.attestation.x)),
    guardian: new CairoOption(CairoOptionVariant.None),
  });
  const addressSalt = 12n;
  const accountAddress = hash.calculateContractAddressFromHash(addressSalt, classHash, constructorCalldata, 0);

  await fundAccount(accountAddress, 1e15, provider);

  // can use either starkOwner or webauthnOwner as signer
  const account = new Account(provider, accountAddress, webauthnOwner, "1");

  console.log("deploying account to address", accountAddress);
  const response = await account.deploySelf({ classHash, constructorCalldata, addressSalt }, { maxFee: 1e15 });
  console.log("waiting for deployment tx", response.transaction_hash);
  await provider.waitForTransaction(response.transaction_hash);

  const accountContract = await loadContract(account.address, provider);
  accountContract.connect(account);
  console.log("deployed");

  return { account, accountContract, starkOwner, webauthnOwner };
}

export async function transferDust(account: Account, provider: ProviderType): Promise<string> {
  const ethContract = await provider.getEthContract(provider);
  ethContract.connect(account);
  const recipient = 69;
  const amount = uint256.bnToUint256(1);
  const response = await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee: 1e15 });
  return response.transaction_hash;
}
