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
  InvocationsSignerDetails,
  InvokeFunctionResponse,
  RPC,
  RawCalldata,
  Signature,
  TransactionReceipt,
  UniversalDetails,
  V2InvocationsSignerDetails,
  V3InvocationsSignerDetails,
  hash,
  num,
  shortString,
  stark,
  transaction,
  uint256,
} from "starknet";
import { manager } from "./manager";
import { ensureSuccess } from "./receipts";
import { LegacyArgentSigner, LegacyKeyPair, LegacyMultisigSigner, LegacyStarknetKeyPair } from "./signers/legacy";
import { ArgentSigner, KeyPair, RawSigner, randomStarknetKeyPair } from "./signers/signers";
import { ethAddress, strkAddress } from "./tokens";

export const VALID = BigInt(shortString.encodeShortString("VALID"));

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
    if (arg2 && !Array.isArray(arg2) && transactionDetail) {
      throw new Error("arg2 cannot be UniversalDetails when transactionDetail is non-null");
    }
    transactionDetail ||= {};
    const details = arg2 === undefined || Array.isArray(arg2) ? transactionDetail : arg2;
    const abi = Array.isArray(details) ? (details as Abi[]) : undefined;
    if (!transactionDetail.skipValidate) {
      transactionDetail.skipValidate = false;
    }
    if (transactionDetail.resourceBounds) {
      return super.execute(calls, abi, transactionDetail);
    }
    const estimate = await this.estimateFee(calls, transactionDetail);
    return super.execute(calls, abi, {
      ...transactionDetail,
      resourceBounds: {
        ...estimate.resourceBounds,
        l1_gas: {
          ...estimate.resourceBounds.l1_gas,
          max_amount: num.toHexString(num.addPercent(estimate.resourceBounds.l1_gas.max_amount, 30)),
        },
      },
    });
  }
}

export interface ArgentWallet {
  account: ArgentAccount;
  accountContract: Contract;
  owner: KeyPair;
}

export interface ArgentWalletWithGuardian extends ArgentWallet {
  guardian: KeyPair;
}

export interface LegacyArgentWallet {
  account: ArgentAccount;
  accountContract: Contract;
  owner: LegacyKeyPair;
  guardian: LegacyKeyPair;
}

export interface ArgentWalletWithGuardianAndBackup extends ArgentWalletWithGuardian {
  guardianBackup: KeyPair;
}

export const deployer = (() => {
  if (manager.isDevnet) {
    const devnetAddress = "0x64b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691";
    const devnetPrivateKey = "0x71d7bb07b9a64f6f78ac4c816aff4da9";
    return new Account(manager, devnetAddress, devnetPrivateKey, undefined, RPC.ETransactionVersion.V2);
  }
  const address = process.env.ADDRESS;
  const privateKey = process.env.PRIVATE_KEY;
  if (address && privateKey) {
    return new Account(manager, address, privateKey, undefined, RPC.ETransactionVersion.V2);
  }
  throw new Error("Missing deployer address or private key, please set ADDRESS and PRIVATE_KEY env variables.");
})();

export const deployerV3 = setDefaultTransactionVersionV3(deployer);

export function setDefaultTransactionVersion(account: ArgentAccount, newVersion: boolean): ArgentAccount {
  const newDefaultVersion = newVersion ? RPC.ETransactionVersion.V3 : RPC.ETransactionVersion.V2;
  if (account.transactionVersion === newDefaultVersion) {
    return account;
  }
  return new ArgentAccount(account, account.address, account.signer, account.cairoVersion, newDefaultVersion);
}

export function setDefaultTransactionVersionV3(account: ArgentAccount): ArgentAccount {
  return setDefaultTransactionVersion(account, true);
}

console.log("Deployer:", deployer.address);

export async function deployOldAccount(
  owner = new LegacyStarknetKeyPair(),
  guardian = new LegacyStarknetKeyPair(),
  salt = num.toHex(randomStarknetKeyPair().privateKey),
): Promise<LegacyArgentWallet> {
  const proxyClassHash = await manager.declareFixtureContract("Proxy");
  const oldArgentAccountClassHash = await manager.declareFixtureContract("OldArgentAccount");

  const constructorCalldata = CallData.compile({
    implementation: oldArgentAccountClassHash,
    selector: hash.getSelectorFromName("initialize"),
    calldata: CallData.compile({ owner: owner.publicKey, guardian: guardian.publicKey }),
  });

  const contractAddress = hash.calculateContractAddressFromHash(salt, proxyClassHash, constructorCalldata, 0);

  const account = new Account(manager, contractAddress, owner);
  account.signer = new LegacyMultisigSigner([owner, guardian]);

  await fundAccount(account.address, 1e16, "ETH"); // 0.01 ETH

  const { transaction_hash } = await account.deployAccount({
    classHash: proxyClassHash,
    constructorCalldata,
    contractAddress,
    addressSalt: salt,
  });
  await manager.waitForTransaction(transaction_hash);
  const accountContract = await manager.loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, owner, guardian };
}

async function deployAccountInner(params: DeployAccountParams): Promise<
  DeployAccountParams & {
    account: ArgentAccount;
    classHash: string;
    owner: KeyPair;
    guardian?: KeyPair;
    salt: string;
    transactionHash: string;
  }
> {
  const finalParams = {
    ...params,
    classHash: params.classHash ?? (await manager.declareLocalContract("ArgentAccount")),
    salt: params.salt ?? num.toHex(randomStarknetKeyPair().privateKey),
    owner: params.owner ?? randomStarknetKeyPair(),
    useTxV3: params.useTxV3 ?? false,
    selfDeploy: params.selfDeploy ?? false,
  };
  const guardian = finalParams.guardian
    ? finalParams.guardian.signerAsOption
    : new CairoOption(CairoOptionVariant.None);
  const constructorCalldata = CallData.compile({ owner: finalParams.owner.signer, guardian });

  const { classHash, salt } = finalParams;
  const contractAddress = hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);
  const fundingCall = finalParams.useTxV3
    ? await fundAccountCall(contractAddress, finalParams.fundingAmount ?? 1e16, "STRK") // 0.01 STRK
    : await fundAccountCall(contractAddress, finalParams.fundingAmount ?? 1e18, "ETH"); // 1 ETH
  const calls = fundingCall ? [fundingCall] : [];

  const transactionVersion = finalParams.useTxV3 ? RPC.ETransactionVersion.V3 : RPC.ETransactionVersion.V2;
  const signer = new ArgentSigner(finalParams.owner, finalParams.guardian);
  const account = new ArgentAccount(manager, contractAddress, signer, "1", transactionVersion);

  let transactionHash;
  if (finalParams.selfDeploy) {
    const response = await deployer.execute(calls);
    await manager.waitForTransaction(response.transaction_hash);
    const { transaction_hash } = await account.deploySelf({ classHash, constructorCalldata, addressSalt: salt });
    transactionHash = transaction_hash;
  } else {
    const udcCalls = deployer.buildUDCContractPayload({ classHash, salt, constructorCalldata, unique: false });
    const { transaction_hash } = await deployer.execute([...calls, ...udcCalls]);
    transactionHash = transaction_hash;
  }

  await manager.waitForTransaction(transactionHash);
  return { ...finalParams, account, transactionHash };
}

export type DeployAccountParams = {
  useTxV3?: boolean;
  classHash?: string;
  owner?: KeyPair;
  guardian?: KeyPair;
  salt?: string;
  fundingAmount?: number | bigint;
  selfDeploy?: boolean;
};

export async function deployAccount(
  params: DeployAccountParams = {},
): Promise<ArgentWalletWithGuardian & { transactionHash: string }> {
  params.guardian ||= randomStarknetKeyPair();
  const { account, owner, transactionHash } = await deployAccountInner(params);
  const accountContract = await manager.loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, owner, guardian: params.guardian, transactionHash };
}

export async function deployAccountWithoutGuardian(
  params: Omit<DeployAccountParams, "guardian"> = {},
): Promise<ArgentWallet & { transactionHash: string }> {
  const { account, owner, transactionHash } = await deployAccountInner(params);
  const accountContract = await manager.loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, owner, transactionHash };
}

export async function deployAccountWithGuardianBackup(
  params: DeployAccountParams & { guardianBackup?: KeyPair } = {},
): Promise<ArgentWalletWithGuardianAndBackup> {
  const guardianBackup = params.guardianBackup ?? randomStarknetKeyPair();

  const wallet = (await deployAccount(params)) as ArgentWalletWithGuardianAndBackup & { transactionHash: string };
  await wallet.accountContract.change_guardian_backup(guardianBackup.compiledSignerAsOption);

  wallet.account.signer = new ArgentSigner(wallet.owner, guardianBackup);
  wallet.guardianBackup = guardianBackup;
  wallet.accountContract.connect(wallet.account);
  return wallet;
}

export async function deployLegacyAccount(classHash: string) {
  const owner = new LegacyStarknetKeyPair();
  const guardian = new LegacyStarknetKeyPair();
  const salt = num.toHex(owner.privateKey);
  const constructorCalldata = CallData.compile({ owner: owner.publicKey, guardian: guardian.publicKey });
  const contractAddress = hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);
  await fundAccount(contractAddress, 1e15, "ETH"); // 0.001 ETH
  const account = new Account(manager, contractAddress, owner, "1");
  account.signer = new LegacyArgentSigner(owner, guardian);

  const { transaction_hash } = await account.deploySelf({
    classHash,
    constructorCalldata,
    addressSalt: salt,
  });
  await manager.waitForTransaction(transaction_hash);

  const accountContract = await manager.loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, owner, guardian };
}

export async function upgradeAccount(
  accountToUpgrade: Account,
  newClassHash: string,
  calldata: RawCalldata = [],
): Promise<TransactionReceipt> {
  const { transaction_hash } = await accountToUpgrade.execute(
    {
      contractAddress: accountToUpgrade.address,
      entrypoint: "upgrade",
      calldata: CallData.compile({ implementation: newClassHash, calldata }),
    },
    undefined,
    { maxFee: 1e14 },
  );
  return await ensureSuccess(transaction_hash);
}

export async function executeWithCustomSig(
  account: ArgentAccount,
  transactions: AllowArray<Call>,
  signature: ArraySignatureType,
  transactionsDetail: UniversalDetails = {},
): Promise<InvokeFunctionResponse> {
  const signer = new (class extends RawSigner {
    public async signRaw(messageHash: string): Promise<string[]> {
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
    public async signTransaction(calls: Call[], signerDetails: InvocationsSignerDetails): Promise<Signature> {
      this.signerDetails = signerDetails;
      throw Error("Should not execute");
    }
    public async signRaw(messageHash: string): Promise<string[]> {
      throw Error("Not implemented");
    }
  })();
  newAccount.signer = customSigner;
  try {
    await newAccount.execute(calls, undefined);
    throw Error("Should not execute");
  } catch (customError) {
    return customSigner.signerDetails!;
  }
}

export function calculateTransactionHash(transactionDetail: InvocationsSignerDetails, calls: Call[]): string {
  const compiledCalldata = transaction.getExecuteCalldata(calls, transactionDetail.cairoVersion);
  let transactionHash;
  if (Object.values(RPC.ETransactionVersion2).includes(transactionDetail.version as any)) {
    const transactionDetailV2 = transactionDetail as V2InvocationsSignerDetails;
    transactionHash = hash.calculateInvokeTransactionHash({
      ...transactionDetailV2,
      senderAddress: transactionDetailV2.walletAddress,
      compiledCalldata,
    });
  } else if (Object.values(RPC.ETransactionVersion3).includes(transactionDetail.version as any)) {
    const transactionDetailV3 = transactionDetail as V3InvocationsSignerDetails;
    transactionHash = hash.calculateInvokeTransactionHash({
      ...transactionDetailV3,
      senderAddress: transactionDetailV3.walletAddress,
      compiledCalldata,
      nonceDataAvailabilityMode: stark.intDAM(transactionDetailV3.nonceDataAvailabilityMode),
      feeDataAvailabilityMode: stark.intDAM(transactionDetailV3.feeDataAvailabilityMode),
    });
  } else {
    throw Error("unsupported transaction version");
  }
  return transactionHash;
}

export async function fundAccount(recipient: string, amount: number | bigint, token: "ETH" | "STRK") {
  const call = await fundAccountCall(recipient, amount, token);
  const response = await deployer.execute(call ? [call] : []);
  await manager.waitForTransaction(response.transaction_hash);
}

export async function fundAccountCall(
  recipient: string,
  amount: number | bigint,
  token: "ETH" | "STRK",
): Promise<Call | undefined> {
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
