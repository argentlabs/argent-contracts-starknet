import { expect } from "chai";
import {
  Abi,
  Account,
  AllowArray,
  ArraySignatureType,
  CairoOption,
  CairoOptionVariant,
  Call,
  CallData,
  Contract,
  DeployAccountContractPayload,
  DeployContractResponse,
  EstimateFee,
  InvocationsSignerDetails,
  InvokeFunctionResponse,
  RPC,
  RawCalldata,
  Signature,
  TransactionReceipt,
  TypedDataRevision,
  UniversalDetails,
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
  // Increase the gas limit by 30% to avoid failures due to gas estimation being too low with tx v3 and transactions the use escaping
  override async deployAccount(
    payload: DeployAccountContractPayload,
    details?: UniversalDetails,
  ): Promise<DeployContractResponse> {
    details ||= {};
    if (!details.skipValidate) {
      details.skipValidate = false;
    }
    return super.deployAccount(payload, details);
  }

  override async execute(
    calls: AllowArray<Call>,
    arg2?: Abi[] | UniversalDetails,
    transactionDetail: UniversalDetails = {},
  ): Promise<InvokeFunctionResponse> {
    const isArg2UniversalDetails = arg2 && !Array.isArray(arg2);
    if (isArg2UniversalDetails && !(Object.keys(transactionDetail).length === 0)) {
      throw new Error("arg2 cannot be UniversalDetails when transactionDetail is non-null");
    }
    const detail = isArg2UniversalDetails ? (arg2 as UniversalDetails) : transactionDetail;
    const abi = Array.isArray(arg2) ? (arg2 as Abi[]) : undefined;
    if (!detail.skipValidate) {
      detail.skipValidate = false;
    }
    return super.execute(calls, abi, detail);
  }
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
    accountContract.connect(finalParams.account);

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
    return new Account(manager, devnetAddress, devnetPrivateKey, "1", RPC.ETransactionVersion.V3);
  }
  const address = process.env.ADDRESS;
  const privateKey = process.env.PRIVATE_KEY;
  if (address && privateKey) {
    return new Account(manager, address, privateKey, "1", RPC.ETransactionVersion.V3);
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

  const account = new Account(manager, contractAddress, owner);
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
  const accountContract = await manager.loadContract(account.address);
  accountContract.connect(account);
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
    useTxV3: params.useTxV3 ?? true,
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
  const fundingCall = finalParams.useTxV3
    ? fundAccountCall(contractAddress, finalParams.fundingAmount ?? 5e18, "STRK") // 5 STRK
    : fundAccountCall(contractAddress, finalParams.fundingAmount ?? 1e18, "ETH"); // 1 ETH
  const calls = fundingCall ? [fundingCall] : [];

  const transactionVersion = finalParams.useTxV3 ? RPC.ETransactionVersion.V3 : RPC.ETransactionVersion.V2;
  const signer = new ArgentSigner(owner, finalParams.guardians.at(0));
  const account = new ArgentAccount(manager, contractAddress, signer, "1", transactionVersion);

  let transactionHash;
  if (finalParams.selfDeploy) {
    const response = await deployer.execute(calls);
    await manager.waitForTx(response.transaction_hash);
    const { transaction_hash } = await account.deploySelf({ classHash, constructorCalldata, addressSalt: salt });
    transactionHash = transaction_hash;

    const accountContract = await manager.loadContract(account.address);
    accountContract.connect(account);
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
    const udcCalls = deployer.buildUDCContractPayload({ classHash, salt, constructorCalldata, unique: false });
    const finalCalls = [...calls, ...udcCalls];
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
    // if devnet, hardcode resource bounds
    const details = manager.isDevnet
      ? {
          resourceBounds: {
            l1_gas: { max_amount: "0x30000", max_price_per_unit: "0x300000000000" },
            l2_gas: { max_amount: "0x0", max_price_per_unit: "0x0" },
          },
        }
      : {};
    const { transaction_hash } = await deployer.execute(finalCalls, undefined, details);
    transactionHash = transaction_hash;
  }

  if (!manager.isDevnet) {
    await manager.waitForTransaction(transactionHash);
  }
  return await ArgentWallet.create({ ...finalParams, account, transactionHash });
}

type DeployAccountParams = {
  useTxV3?: boolean;
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
  transactionVersion = RPC.ETransactionVersion.V3,
): Promise<LegacyArgentWallet> {
  const guardian = new LegacyStarknetKeyPair();
  return deployLegacyAccountInner(classHash, guardian, transactionVersion);
}

export async function deployLegacyAccountWithoutGuardian(
  classHash: string,
  transactionVersion = RPC.ETransactionVersion.V3,
): Promise<LegacyArgentWallet> {
  return deployLegacyAccountInner(classHash, undefined, transactionVersion);
}

async function deployLegacyAccountInner(
  classHash: string,
  guardian?: LegacyStarknetKeyPair,
  transactionVersion = RPC.ETransactionVersion.V3,
): Promise<LegacyArgentWallet> {
  const owner = new LegacyStarknetKeyPair();
  const salt = num.toHex(owner.privateKey);
  const constructorCalldata = CallData.compile({ owner: owner.publicKey, guardian: guardian?.publicKey || 0 });
  const contractAddress = hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);
  if (transactionVersion === RPC.ETransactionVersion.V3) {
    await fundAccount(contractAddress, 1e18, "STRK");
  } else {
    await fundAccount(contractAddress, 1e15, "ETH");
  }

  const account = new Account(manager, contractAddress, owner, "1", transactionVersion);
  account.signer = new LegacyArgentSigner(owner, guardian);

  const { transaction_hash } = await account.deploySelf({
    classHash,
    constructorCalldata,
    addressSalt: salt,
  });
  await manager.waitForTx(transaction_hash);

  const accountContract = await manager.loadContract(account.address);
  accountContract.connect(account);
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
    public async signRaw(_messageHash: string): Promise<string[]> {
      return signature;
    }
  })();
  const newAccount = new ArgentAccount(
    manager,
    account.address,
    signer,
    account.cairoVersion,
    account.transactionVersion,
  );

  return await newAccount.execute(transactions, undefined, transactionsDetail);
}

export async function estimateWithCustomSig(
  account: ArgentAccount,
  transactions: AllowArray<Call>,
  signature: ArraySignatureType,
): Promise<EstimateFee> {
  const signer = new (class extends RawSigner {
    public async signRaw(_messageHash: string): Promise<string[]> {
      return signature;
    }
  })();
  const newAccount = new ArgentAccount(
    manager,
    account.address,
    signer,
    account.cairoVersion,
    account.transactionVersion,
  );
  // If the transaction fails, the estimation will fail and an error will be thrown
  return await newAccount.estimateFee(transactions);
}

export async function getSignerDetails(account: ArgentAccount, calls: Call[]): Promise<InvocationsSignerDetails> {
  const newAccount = new ArgentAccount(
    manager,
    account.address,
    account.signer,
    account.cairoVersion,
    account.transactionVersion,
  );
  const customSigner = new (class extends RawSigner {
    public signerDetails?: InvocationsSignerDetails;
    public async signTransaction(_calls: Call[], signerDetails: InvocationsSignerDetails): Promise<Signature> {
      this.signerDetails = signerDetails;
      throw Error("Should not execute");
    }
    public async signRaw(_messageHash: string): Promise<string[]> {
      throw Error("Not implemented");
    }
  })();
  newAccount.signer = customSigner;
  try {
    // Hardcoding skipValidate to skip estimation
    await newAccount.execute(calls, undefined, { skipValidate: true });
    throw Error("Should not execute");
  } catch (customError) {
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
