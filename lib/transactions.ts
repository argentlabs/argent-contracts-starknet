import {
  Call,
  ETransactionVersion,
  InvocationsSignerDetails,
  V3InvocationsSignerDetails,
  hash,
  stark,
  transaction,
} from "starknet";

export function calculateTransactionHash(transactionDetail: InvocationsSignerDetails, calls: Call[]): string {
  if (transactionDetail.version !== ETransactionVersion.V3) {
    throw new Error("unsupported transaction version");
  }

  const compiledCalldata = transaction.getExecuteCalldata(calls, transactionDetail.cairoVersion);
  const transactionDetailV3 = transactionDetail as V3InvocationsSignerDetails;
  return hash.calculateInvokeTransactionHash({
    ...transactionDetailV3,
    senderAddress: transactionDetailV3.walletAddress,
    compiledCalldata,
    nonceDataAvailabilityMode: stark.intDAM(transactionDetailV3.nonceDataAvailabilityMode),
    feeDataAvailabilityMode: stark.intDAM(transactionDetailV3.feeDataAvailabilityMode),
  });
}
