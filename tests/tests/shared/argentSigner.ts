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

export { ArgentSigner };
