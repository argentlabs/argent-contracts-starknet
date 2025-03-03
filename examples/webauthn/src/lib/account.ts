import { Account, EstimateFee, EstimateFeeAction, Provider, UniversalDetails, num } from "starknet";
import { ArgentSigner } from "./signers";
import { WebauthnOwner, createEstimateWebauthnOwner } from "./webauthnOwner";

export class ArgentAccount extends Account {
  override async getSuggestedFee(action: EstimateFeeAction, details: UniversalDetails): Promise<EstimateFee> {
    let estimateFee: EstimateFee;
    if (this.signer instanceof ArgentSigner) {
      if (!details.skipValidate) {
        details.skipValidate = false;
      }
      const argentSigner = this.signer as ArgentSigner;
      let owner = argentSigner.owner;
      if (owner instanceof WebauthnOwner) {
        owner = createEstimateWebauthnOwner(owner);
      }
      let guardian = argentSigner.guardian;
      if (guardian && guardian instanceof WebauthnOwner) {
        guardian = createEstimateWebauthnOwner(guardian);
      }
      const estimateSigner = new ArgentSigner(owner, guardian);
      const estimateAccount = new Account(
        this as Provider,
        this.address,
        estimateSigner,
        this.cairoVersion,
        this.transactionVersion,
      );
      estimateFee = await estimateAccount.getSuggestedFee(action, details);
    } else {
      estimateFee = await super.getSuggestedFee(action, details);
    }

    const PERCENT = 1;
    return {
      ...estimateFee,
      suggestedMaxFee: num.toHexString(num.addPercent(estimateFee.suggestedMaxFee, PERCENT)),
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
