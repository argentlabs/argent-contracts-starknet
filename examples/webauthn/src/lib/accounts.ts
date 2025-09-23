import {
  Account,
  CairoVersion,
  EstimateFee,
  EstimateFeeAction,
  Provider,
  ProviderInterface,
  ProviderOptions,
  SignerInterface,
  UniversalDetails,
  num,
} from "starknet";
import { ArgentSigner } from "./signers/signers";

export class ArgentAccount extends Account {
  constructor(
    providerOrOptions: ProviderOptions | ProviderInterface,
    address: string,
    pkOrSigner: string | Uint8Array | SignerInterface,
    cairoVersion: CairoVersion = "1",
    transactionVersion: "0x2" | "0x3" = "0x3",
  ) {
    super(providerOrOptions, address, pkOrSigner, cairoVersion, transactionVersion);
  }

  override async getSuggestedFee(action: EstimateFeeAction, details: UniversalDetails): Promise<EstimateFee> {
    if (!details.skipValidate) {
      details.skipValidate = false;
    }
    if (this.signer instanceof ArgentSigner) {
      const { owner, guardian } = this.signer as ArgentSigner;
      const estimateSigner = new ArgentSigner(owner.estimateSigner, guardian?.estimateSigner);
      const estimateAccount = new Account(
        this as Provider,
        this.address,
        estimateSigner,
        this.cairoVersion,
        this.transactionVersion,
      );
      return await estimateAccount.getSuggestedFee(action, details);
    } else {
      // TODO: make accurate estimates work with sessions and legacy signers
      const estimateFee = await super.getSuggestedFee(action, details);
      const PERCENT = 30;
      console.log("estimateFee");
      console.log(estimateFee);
      return {
        ...estimateFee,
        suggestedMaxFee: num.addPercent(estimateFee.suggestedMaxFee, PERCENT),
        resourceBounds: {
          ...estimateFee.resourceBounds,
          l1_gas: {
            ...estimateFee.resourceBounds.l1_gas,
            max_amount: num.toHexString(num.addPercent(estimateFee.resourceBounds.l1_gas.max_amount, PERCENT)),
          },
        },
      };
    }
  }
}
