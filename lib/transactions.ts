import {
  Call,
  InvocationsSignerDetails,
  RPC,
  V2InvocationsSignerDetails,
  V3InvocationsSignerDetails,
  hash,
  stark,
  transaction,
} from "starknet";

export function calculateTransactionHash(transactionDetail: InvocationsSignerDetails, calls: Call[]): string {
  const compiledCalldata = transaction.getExecuteCalldata(calls, transactionDetail.cairoVersion);
  if (Object.values(RPC.ETransactionVersion2).includes(transactionDetail.version as any)) {
    const transactionDetailV2 = transactionDetail as V2InvocationsSignerDetails;
    return hash.calculateInvokeTransactionHash({
      ...transactionDetailV2,
      senderAddress: transactionDetailV2.walletAddress,
      compiledCalldata,
    });
  } else if (Object.values(RPC.ETransactionVersion3).includes(transactionDetail.version as any)) {
    const transactionDetailV3 = transactionDetail as V3InvocationsSignerDetails;
    return hash.calculateInvokeTransactionHash({
      ...transactionDetailV3,
      senderAddress: transactionDetailV3.walletAddress,
      compiledCalldata,
      nonceDataAvailabilityMode: stark.intDAM(transactionDetailV3.nonceDataAvailabilityMode),
      feeDataAvailabilityMode: stark.intDAM(transactionDetailV3.feeDataAvailabilityMode),
    });
  } else {
    throw Error("unsupported transaction version");
  }
}
