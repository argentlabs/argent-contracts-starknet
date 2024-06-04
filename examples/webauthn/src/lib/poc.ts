import { Account, CairoOption, CairoOptionVariant, CallData, Contract, hash, uint256 } from "starknet";
import casm from "./argent_ArgentAccount.compiled_contract_class.json";
import sierra from "./argent_ArgentAccount.contract_class.json";
import { buf2hex } from "./bytes";
import { ArgentSigner } from "./signers";
import { fundAccount, getEthContract, loadContract, loadDeployer, type ProviderType } from "./starknet";
import { createWebauthnAttestation, requestSignature } from "./webauthnAttestation";
import { WebauthnOwner } from "./webauthnOwner";

export async function createOwner(email: string, rpId: string, origin: string): Promise<WebauthnOwner> {
  console.log("creating webauthn key (attestation)...");
  const attestation = await createWebauthnAttestation(email, rpId, origin);
  console.log("created webauthn public key:", buf2hex(attestation.pubKey));
  return new WebauthnOwner(attestation, requestSignature);
}

export async function declareAccount(provider: ProviderType): Promise<string> {
  const deployer = await loadDeployer(provider);
  console.log("deployer is", deployer.address);
  const { class_hash, transaction_hash } = await deployer.declareIfNot({ casm, contract: sierra }, { maxFee: 1e17 });
  if (transaction_hash) {
    await provider.waitForTransaction(transaction_hash);
  }
  return class_hash;
}

export async function deployAccount(
  classHash: string,
  webauthnOwner: WebauthnOwner,
  provider: ProviderType,
): Promise<{ account: Account; accountContract: Contract; webauthnOwner: WebauthnOwner }> {
  const constructorCalldata = CallData.compile({
    owner: webauthnOwner.signer,
    guardian: new CairoOption(CairoOptionVariant.None),
  });
  const addressSalt = 12n;
  const accountAddress = hash.calculateContractAddressFromHash(addressSalt, classHash, constructorCalldata, 0);

  await fundAccount(accountAddress, 1e15, provider);

  const account = new Account(provider, accountAddress, new ArgentSigner(webauthnOwner), "1");

  console.log("deploying account to address", accountAddress);
  const response = await account.deploySelf({ classHash, constructorCalldata, addressSalt }, { maxFee: 1e15 });
  console.log("waiting for deployment tx", response.transaction_hash);
  await provider.waitForTransaction(response.transaction_hash);

  const accountContract = await loadContract(account.address, provider);
  accountContract.connect(account);
  console.log("deployed");

  return { account, accountContract, webauthnOwner };
}

export async function transferDust(account: Account, provider: ProviderType): Promise<string> {
  const ethContract = await getEthContract(provider);
  ethContract.connect(account);
  const recipient = 69;
  const amount = uint256.bnToUint256(1);
  const response = await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee: 1e15 });
  return response.transaction_hash;
}
