import {
  Abi,
  Account,
  AllowArray,
  Call,
  DeployAccountContractPayload,
  DeployContractResponse,
  InvokeFunctionResponse,
  Provider,
  UniversalDetails,
  num,
} from "starknet";
import { ArgentSigner } from "./signers";
import { WebauthnOwner, createEstimateWebauthnOwner } from "./webauthnOwner";

export class ArgentAccount extends Account {
  // Increase the gas limit by 30% to avoid failures due to gas estimation being too low with tx v3 and transactions the use escaping
  // In the case of Webauthn it also mocks the estimation of fees to ensure that the user do not have to sign twice
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
    if (detail.resourceBounds) {
      return super.execute(calls, abi, detail);
    }
    // use a mock webauthn signer to avoid signing twice
    let estimateAccount = this;
    if (this.signer instanceof ArgentSigner) {
      console.log("replace by estimate account");
      const argentSigner = this.signer as ArgentSigner;
      let owner = argentSigner.owner;
      if (owner instanceof WebauthnOwner) {
        console.log("replace owner by estimate webauthn");
        owner = createEstimateWebauthnOwner(owner);
      }
      let guardian = argentSigner.guardian;
      if (guardian && guardian instanceof WebauthnOwner) {
        guardian = createEstimateWebauthnOwner(guardian);
      }
      const estimateSigner = new ArgentSigner(owner, guardian);
      estimateAccount = new Account(
        this as Provider,
        this.address,
        estimateSigner,
        this.cairoVersion,
        this.transactionVersion,
      );
    }
    const estimate = await estimateAccount.estimateFee(calls, detail);
    return super.execute(calls, abi, {
      ...detail,
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
