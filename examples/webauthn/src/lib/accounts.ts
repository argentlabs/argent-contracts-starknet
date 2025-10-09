import {
  Account,
  type AccountOptions,
  type EstimateFeeBulk,
  type Invocations,
  Provider,
  type UniversalDetails,
} from "starknet";
import { ArgentSigner } from "$lib/signers/signers";

export class ArgentAccount extends Account {
  override async estimateFeeBulk(invocations: Invocations, details?: UniversalDetails): Promise<EstimateFeeBulk> {
    details = details ?? {};
    details.skipValidate = details.skipValidate ?? false;

    if (this.signer instanceof ArgentSigner) {
      const { owner, guardian } = this.signer as ArgentSigner;
      const estimateSigner = new ArgentSigner(owner.estimateSigner, guardian?.estimateSigner);
      const estimateAccount = new Account({
        ...this,
        provider: this as Provider,
        signer: estimateSigner,
      });
      return await estimateAccount.estimateFeeBulk(invocations, details);
    } else {
      return await super.estimateFeeBulk(invocations, details);
    }
  }
}
