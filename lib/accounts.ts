import { expect } from "chai";
import {
  Account,
  AllowArray,
  ArraySignatureType,
  CairoOption,
  CairoOptionVariant,
  CairoVersion,
  Call,
  CallData,
  Contract,
  ETransactionVersion,
  EstimateFeeResponseOverhead,
  InvocationsSignerDetails,
  InvokeFunctionResponse,
  ProviderInterface,
  ProviderOptions,
  RawCalldata,
  Signature,
  SignerInterface,
  TransactionReceipt,
  TypedDataRevision,
  UniversalDetails,
  defaultDeployer,
  hash,
  num,
  uint256,
} from "starknet";
import { manager } from "./manager";
import { getOutsideExecutionCall } from "./outsideExecution";
import { LegacyArgentSigner, LegacyKeyPair, LegacyMultisigSigner, LegacyStarknetKeyPair } from "./signers/legacy";
import { ArgentSigner, KeyPair, RawSigner, randomStarknetKeyPair } from "./signers/signers";
import { ethAddress, strkAddress } from "./tokens";

export class ArgentAccount extends Account {
  constructor(
    providerOrOptions: ProviderOptions | ProviderInterface,
    address: string,
    pkOrSigner: string | Uint8Array | SignerInterface,
    cairoVersion: CairoVersion = "1",
  ) {
    // TODO Update to use the new Account constructor
    // TODO Check where transacationVersion = 0x2 is used
    super({
      provider: providerOrOptions,
      address,
      signer: pkOrSigner,
      cairoVersion,
      transactionVersion: ETransactionVersion.V3,
    });
  }

  // override async getSuggestedFee(action: EstimateFeeAction, details: UniversalDetails): Promise<EstimateFee> {
  //   if (!details.skipValidate) {
  //     details.skipValidate = false;
  //   }
  //   if (this.signer instanceof ArgentSigner) {
  //     const { owner, guardian } = this.signer as ArgentSigner;
  //     const estimateSigner = new ArgentSigner(owner.estimateSigner, guardian?.estimateSigner);
  //     const estimateAccount = new Account(
  //       this as Provider,
  //       this.address,
  //       estimateSigner,
  //       this.cairoVersion,
  //       this.transactionVersion,
  //     );
  //     return await estimateAccount.getSuggestedFee(action, details);
  //   } else {
  //     return await super.getSuggestedFee(action, details);
  //   }
  // }
}

class ArgentWallet implements ArgentWallet {
  constructor(
    public readonly account: ArgentAccount,
    public readonly classHash: string,
    public readonly owners: KeyPair[],
    public readonly guardians: KeyPair[],
    public readonly salt: string,
    public readonly transactionHash: string,
    public readonly accountContract: Contract,
  ) {}

  public get owner(): KeyPair {
    if (this.owners.length > 1) throw new Error("Cannot get owner when there are multiple owners");
    return this.owners[0];
  }

  public get guardian(): KeyPair | undefined {
    if (this.guardians.length > 1) throw new Error("Cannot get guardian when there are multiple guardians");
    return this.guardians.at(0);
  }

  static async create(
    finalParams: DeployAccountParams & {
      account: ArgentAccount;
      classHash: string;
      owners: KeyPair[];
      guardians: KeyPair[];
      salt: string;
      transactionHash: string;
    },
  ): Promise<ArgentWallet> {
    const accountContract = await manager.loadContract(finalParams.account.address);
    accountContract.providerOrAccount = finalParams.account;

    return new ArgentWallet(
      finalParams.account,
      finalParams.classHash,
      finalParams.owners,
      finalParams.guardians,
      finalParams.salt,
      finalParams.transactionHash,
      accountContract,
    );
  }
}

interface LegacyArgentWallet {
  account: ArgentAccount;
  accountContract: Contract;
  owner: LegacyKeyPair;
  guardian?: LegacyKeyPair;
}

export const deployer = (() => {
  if (manager.isDevnet) {
    const devnetAddress = "0x64b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691";
    const devnetPrivateKey = "0x71d7bb07b9a64f6f78ac4c816aff4da9";
    return new Account({
      provider: manager,
      address: devnetAddress,
      signer: devnetPrivateKey,
      cairoVersion: "1",
      transactionVersion: ETransactionVersion.V3,
    });
  }
  const address = process.env.ADDRESS;
  const privateKey = process.env.PRIVATE_KEY;
  if (address && privateKey) {
    return new Account({
      provider: manager,
      address,
      signer: privateKey,
      cairoVersion: "1",
      transactionVersion: ETransactionVersion.V3,
    });
  }
  throw new Error("Missing deployer address or private key, please set ADDRESS and PRIVATE_KEY env variables.");
})();

console.log("Deployer:", deployer.address);

export async function deployOldAccountWithProxy(
  owner = new LegacyStarknetKeyPair(),
  guardian = new LegacyStarknetKeyPair(),
  salt = num.toHex(randomStarknetKeyPair().privateKey),
): Promise<LegacyArgentWallet & { guardian: LegacyKeyPair }> {
  return { ...(await deployOldAccountWithProxyInner(owner, guardian, salt)), guardian };
}

export async function deployOldAccountWithProxyWithoutGuardian(): Promise<LegacyArgentWallet> {
  return await deployOldAccountWithProxyInner(new LegacyStarknetKeyPair());
}

async function deployOldAccountWithProxyInner(
  owner: LegacyKeyPair,
  guardian?: LegacyKeyPair,
  salt = num.toHex(randomStarknetKeyPair().privateKey),
): Promise<LegacyArgentWallet> {
  const proxyClassHash = await manager.declareFixtureContract("Proxy");
  const oldArgentAccountClassHash = await manager.declareFixtureContract("Account-0.2.3.1");
  // Ensuring that the OldArgentAccount class hash is the expected one of v2.3.1
  expect(oldArgentAccountClassHash).to.equal("0x33434ad846cdd5f23eb73ff09fe6fddd568284a0fb7d1be20ee482f044dabe2");

  const guardianPublicKey = guardian ? guardian.publicKey : 0;
  const constructorCalldata = CallData.compile({
    implementation: oldArgentAccountClassHash,
    selector: hash.getSelectorFromName("initialize"),
    calldata: CallData.compile({ owner: owner.publicKey, guardian: guardianPublicKey }),
  });

  const contractAddress = hash.calculateContractAddressFromHash(salt, proxyClassHash, constructorCalldata, 0);

  const account = new Account({ provider: manager, address: contractAddress, signer: owner });
  const keys = [owner];
  if (guardian) {
    keys.push(guardian);
  }
  account.signer = new LegacyMultisigSigner(keys);

  await fundAccount(account.address, 1e16, "ETH"); // 0.01 ETH

  const { transaction_hash } = await account.deployAccount({
    classHash: proxyClassHash,
    constructorCalldata,
    contractAddress,
    addressSalt: salt,
  });
  await manager.waitForTx(transaction_hash);

  const { abi } = await manager.getClass(oldArgentAccountClassHash);
  const accountContract = new Contract({ abi, address: account.address, providerOrAccount: account });

  accountContract.providerOrAccount = account;
  return { account, accountContract, owner, guardian };
}

async function deployAccountInner(params: DeployAccountParams): Promise<ArgentWallet> {
  if (params.guardian && params.guardians) throw new Error("Cannot deploy with guardian and guardians both defined");
  if (params.owner && params.owners) throw new Error("Cannot deploy with owner and owners both defined");

  const owners = params.owner ? [params.owner] : params.owners;
  const guardians = params.guardian ? [params.guardian] : params.guardians;
  const finalParams = {
    ...params,
    classHash: params.classHash ?? (await manager.declareLocalContract("ArgentAccount")),
    salt: params.salt ?? num.toHex(randomStarknetKeyPair().privateKey),
    owners: owners ?? [randomStarknetKeyPair()],
    guardians: guardians ?? [],
    selfDeploy: params.selfDeploy ?? false,
  };
  const guardian =
    finalParams.guardians.length > 0
      ? finalParams.guardians[0].signerAsOption
      : new CairoOption(CairoOptionVariant.None);
  const owner = finalParams.owners[0];
  const constructorCalldata = CallData.compile({ owner: owner.signer, guardian });

  const { classHash, salt } = finalParams;
  const contractAddress = hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);
  const fundingCall = fundAccountCall(contractAddress, finalParams.fundingAmount ?? 5e18, "STRK"); // 1 ETH
  const calls = fundingCall ? [fundingCall] : [];

  const signer = new ArgentSigner(owner, finalParams.guardians.at(0));
  const account = new ArgentAccount(manager, contractAddress, signer, "1");

  let transactionHash;
  if (finalParams.selfDeploy) {
    await manager.ensureSuccess(deployer.execute(calls));
    const { transaction_hash } = await account.deploySelf({ classHash, constructorCalldata, addressSalt: salt });
    transactionHash = transaction_hash;

    const accountContract = await manager.loadContract(account.address);
    accountContract.providerOrAccount = account;
    if (finalParams.owners.length > 1) {
      const calldata = CallData.compile([
        {
          owners_guids_to_remove: [],
          owners_to_add: finalParams.owners.slice(1).map((owner) => owner.signer),
          owner_alive_signature: new CairoOption(CairoOptionVariant.None),
        },
      ]);

      await accountContract.invoke("change_owners", calldata);
    }
    if (finalParams.guardians.length > 1) {
      const calldata = CallData.compile([
        {
          guardian_guids_to_remove: [],
          guardians_to_add: finalParams.guardians.slice(1).map((guardian) => guardian.signer),
        },
      ]);
      await accountContract.invoke("change_guardians", calldata);
    }
  } else {
    const udcCalls = defaultDeployer.buildDeployerCall(
      { classHash, salt, constructorCalldata, unique: false },
      contractAddress,
    );
    const finalCalls = [...calls, ...udcCalls.calls];
    if (finalParams.owners.length > 1) {
      const outsideCall = {
        caller: deployer.address,
        nonce: randomStarknetKeyPair().publicKey,
        execute_after: 0,
        execute_before: 9999999999,
        calls: [
          {
            to: contractAddress,
            selector: hash.getSelectorFromName("change_owners"),
            calldata: CallData.compile({
              owners_guids_to_remove: [],
              owners_to_add: finalParams.owners.slice(1).map((owner) => owner.signer),
              owner_alive_signature: new CairoOption(CairoOptionVariant.None),
            }),
          },
        ],
      };
      finalCalls.push(await getOutsideExecutionCall(outsideCall, contractAddress, signer, TypedDataRevision.ACTIVE));
    }
    if (finalParams.guardians.length > 1) {
      const outsideCall = {
        caller: deployer.address,
        nonce: randomStarknetKeyPair().publicKey,
        execute_after: 0,
        execute_before: 9999999999,
        calls: [
          {
            to: contractAddress,
            selector: hash.getSelectorFromName("change_guardians"),
            calldata: CallData.compile({
              guardians_guids_to_remove: [],
              guardians_to_add: finalParams.guardians.slice(1).map((guardian) => guardian.signer),
            }),
          },
        ],
      };
      finalCalls.push(await getOutsideExecutionCall(outsideCall, contractAddress, signer, TypedDataRevision.ACTIVE));
    }
    const { transaction_hash } = await deployer.execute(finalCalls);
    transactionHash = transaction_hash;
  }

  await manager.waitForTransaction(transactionHash);
  return await ArgentWallet.create({ ...finalParams, account, transactionHash });
}

type DeployAccountParams = {
  classHash?: string;
  owners?: KeyPair[];
  owner?: KeyPair;
  guardians?: KeyPair[];
  guardian?: KeyPair;
  salt?: string;
  fundingAmount?: number | bigint;
  selfDeploy?: boolean;
};

export async function deployAccount(params: DeployAccountParams = {}): Promise<ArgentWallet & { guardian: KeyPair }> {
  if (!params.guardian && !params.guardians) {
    params.guardians = [randomStarknetKeyPair()];
  }
  const deployedAccount = await deployAccountInner(params);
  return deployedAccount as ArgentWallet & { guardian: KeyPair };
}

export async function deployAccountWithoutGuardians(
  params: Omit<DeployAccountParams, "guardian" | "guardians"> = {},
): Promise<Omit<ArgentWallet, "guardian" | "guardians">> {
  return await deployAccountInner(params);
}

export async function deployLegacyAccount(
  classHash: string,
  transactionVersion = ETransactionVersion.V3,
): Promise<LegacyArgentWallet> {
  const guardian = new LegacyStarknetKeyPair();
  return deployLegacyAccountInner(classHash, guardian, transactionVersion);
}

export async function deployLegacyAccountWithoutGuardian(
  classHash: string,
  transactionVersion = ETransactionVersion.V3,
): Promise<LegacyArgentWallet> {
  return deployLegacyAccountInner(classHash, undefined, transactionVersion);
}

async function deployLegacyAccountInner(
  classHash: string,
  guardian?: LegacyStarknetKeyPair,
  transactionVersion = ETransactionVersion.V3,
): Promise<LegacyArgentWallet> {
  const owner = new LegacyStarknetKeyPair();
  const salt = num.toHex(owner.privateKey);
  const constructorCalldata = CallData.compile({ owner: owner.publicKey, guardian: guardian?.publicKey || 0 });
  const contractAddress = hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);
  if (transactionVersion === ETransactionVersion.V3) {
    await fundAccount(contractAddress, 1e18, "STRK");
  } else {
    await fundAccount(contractAddress, 1e15, "ETH");
  }

  const account = new Account({
    provider: manager,
    address: contractAddress,
    signer: owner,
    cairoVersion: "1",
    transactionVersion: ETransactionVersion.V3,
  });
  account.signer = new LegacyArgentSigner(owner, guardian);

  const { transaction_hash } = await account.deploySelf({
    classHash,
    constructorCalldata,
    addressSalt: salt,
  });
  await manager.waitForTx(transaction_hash);

  const accountContract = await manager.loadContract(account.address);
  accountContract.providerOrAccount = account;
  return { account, accountContract, owner, guardian };
}

export async function upgradeAccount(
  accountToUpgrade: Account,
  newClassHash: string,
  calldata: RawCalldata = [],
): Promise<TransactionReceipt> {
  return await manager.ensureSuccess(
    accountToUpgrade.execute({
      contractAddress: accountToUpgrade.address,
      entrypoint: "upgrade",
      calldata: CallData.compile({ implementation: newClassHash, calldata }),
    }),
  );
}

export async function executeWithCustomSig(
  account: ArgentAccount,
  transactions: AllowArray<Call>,
  signature: ArraySignatureType,
  transactionsDetail: UniversalDetails = {},
): Promise<InvokeFunctionResponse> {
  const signer = new (class extends RawSigner {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    public async signRaw(_messageHash: string): Promise<string[]> {
      return signature;
    }
  })();
  const newAccount = new ArgentAccount(manager, account.address, signer, account.cairoVersion);

  return await newAccount.execute(transactions, transactionsDetail);
}

export async function estimateWithCustomSig(
  account: ArgentAccount,
  transactions: AllowArray<Call>,
  signature: ArraySignatureType,
): Promise<EstimateFeeResponseOverhead> {
  const signer = new (class extends RawSigner {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    public async signRaw(_messageHash: string): Promise<string[]> {
      return signature;
    }
  })();
  const newAccount = new ArgentAccount(manager, account.address, signer, account.cairoVersion);
  // If the transaction fails, the estimation will fail and an error will be thrown
  return await newAccount.estimateInvokeFee(transactions);
}

class ShouldNotExecuteError extends Error {}

export async function getSignerDetails(account: ArgentAccount, calls: Call[]): Promise<InvocationsSignerDetails> {
  const newAccount = new ArgentAccount(manager, account.address, account.signer, account.cairoVersion);
  const customSigner = new (class extends RawSigner {
    public signerDetails?: InvocationsSignerDetails;
    public async signTransaction(_calls: Call[], signerDetails: InvocationsSignerDetails): Promise<Signature> {
      this.signerDetails = signerDetails;
      throw new ShouldNotExecuteError();
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    public async signRaw(_messageHash: string): Promise<string[]> {
      throw Error("Not implemented");
    }
  })();
  newAccount.signer = customSigner;
  try {
    // Hardcoding skipValidate to skip estimation
    await newAccount.execute(calls, { skipValidate: true });
    throw Error("Execution didn't fail");
  } catch (error) {
    if (!(error instanceof ShouldNotExecuteError)) {
      throw error;
    }
    return customSigner.signerDetails!;
  }
}

export async function fundAccount(recipient: string, amount: number | bigint, token: "ETH" | "STRK") {
  const call = fundAccountCall(recipient, amount, token);
  const response = await deployer.execute(call ? [call] : []);
  await manager.waitForTx(response.transaction_hash);
}

export function fundAccountCall(recipient: string, amount: number | bigint, token: "ETH" | "STRK"): Call | undefined {
  if (amount <= 0n) {
    return;
  }
  const contractAddress = { ETH: ethAddress, STRK: strkAddress }[token];
  if (!contractAddress) {
    throw new Error(`Unsupported token ${token}`);
  }
  const calldata = CallData.compile([recipient, uint256.bnToUint256(amount)]);
  return { contractAddress, calldata, entrypoint: "transfer" };
}
