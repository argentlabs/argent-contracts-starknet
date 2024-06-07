import { Account, CairoOption, CairoOptionVariant, CallData, hash, uint256 } from "starknet";
import accountCasm from "./argent_ArgentAccount.compiled_contract_class.json";
import accountSierra from "./argent_ArgentAccount.contract_class.json";
import { buf2hex } from "./bytes";
import { ArgentSigner } from "./signers";
import { fundAccount, getEthContract, loadDeployer, type ProviderType } from "./starknet";
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

  // Assert sha256 class hash is declared
  try {
    await provider.getClass(0x04dacc042b398d6f385a87e7dd65d2bcb3270bb71c4b34857b3c658c7f52cf6dn);
  } catch (e) {
    throw new Error(
      "Sha256 class hash not declared, please run `scarb run profile` at the repo root folder to declare it",
      e,
    );
  }

  const { class_hash: accountClassHash, transaction_hash: accountTransactionHash } = await deployer.declareIfNot(
    { casm: accountCasm, contract: accountSierra },
    { maxFee: 1e17 },
  );

  if (accountTransactionHash) {
    const res = await provider.waitForTransaction(accountTransactionHash);
    console.log("account declare transaction", accountTransactionHash, "completed", res);
  }
  console.log("account classHash", accountClassHash);

  return accountClassHash;
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

  await fundAccount(accountAddress, 1e15, provider);

  const account = new Account(provider, accountAddress, new ArgentSigner(webauthnOwner), "1");

  console.log("deploying account to address", accountAddress);
  const response = await account.deploySelf({ classHash, constructorCalldata, addressSalt }, { maxFee: 1e15 });
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
  const response = await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee: 1e15 });
  return response.transaction_hash;
}
