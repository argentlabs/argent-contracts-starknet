import { Abi, Call, InvocationsSignerDetails, Signature, Signer, ec, hash, transaction } from "starknet";

class ArgentSigner extends Signer {
  protected guardianPk: string;

  constructor(ownerPk: string, guardianPk: string) {
    super(ownerPk);
    this.guardianPk = guardianPk;
  }

  public async signTransaction(
    transactions: Call[],
    transactionsDetail: InvocationsSignerDetails,
    abis?: Abi[],
  ): Promise<Signature> {
    if (abis && abis.length !== transactions.length) {
      throw new Error("ABI must be provided for each transaction or no transaction");
    }

    const calldata = transaction.getExecuteCalldata(transactions, transactionsDetail.cairoVersion);

    const msgHash = hash.calculateTransactionHash(
      transactionsDetail.walletAddress,
      transactionsDetail.version,
      calldata,
      transactionsDetail.maxFee,
      transactionsDetail.chainId,
      transactionsDetail.nonce,
    );

    const ownerSignature = await ec.starkCurve.sign(msgHash, this.pk);
    const guardianSignature = await ec.starkCurve.sign(msgHash, this.guardianPk);

    return [
      ownerSignature.r.toString(),
      ownerSignature.s.toString(),
      guardianSignature.r.toString(),
      guardianSignature.s.toString(),
    ];
  }
}

// This is a wrong signer as the argent account expects the signature length to always be 2 or 4
// This signer will make a signature of 6 length using signature from owner, guardian and guardian backup
class ArgentSigner3Signatures extends Signer {
  protected guardianPk: string;
  protected guardianBackupPk: string;

  constructor(ownerPk: string, guardianPk: string, guardianBackupPk: string) {
    super(ownerPk);
    this.guardianPk = guardianPk;
    this.guardianBackupPk = guardianBackupPk;
  }

  public async signTransaction(
    transactions: Call[],
    transactionsDetail: InvocationsSignerDetails,
    abis?: Abi[],
  ): Promise<Signature> {
    if (abis && abis.length !== transactions.length) {
      throw new Error("ABI must be provided for each transaction or no transaction");
    }

    const calldata = transaction.getExecuteCalldata(transactions, transactionsDetail.cairoVersion);

    const msgHash = hash.calculateTransactionHash(
      transactionsDetail.walletAddress,
      transactionsDetail.version,
      calldata,
      transactionsDetail.maxFee,
      transactionsDetail.chainId,
      transactionsDetail.nonce,
    );

    const ownerSignature = await ec.starkCurve.sign(msgHash, this.pk);
    const guardianSignature = await ec.starkCurve.sign(msgHash, this.guardianPk);
    const guardianBackupSignature = await ec.starkCurve.sign(msgHash, this.guardianBackupPk);

    return [
      ownerSignature.r.toString(),
      ownerSignature.s.toString(),
      guardianSignature.r.toString(),
      guardianSignature.s.toString(),
      guardianBackupSignature.r.toString(),
      guardianBackupSignature.s.toString(),
    ];
  }
}

// TODO should we try signer that will put guardian signature first?
// TODO try where signature is simply wrong

export { ArgentSigner, ArgentSigner3Signatures };
