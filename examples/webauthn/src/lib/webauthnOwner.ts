import { CallData, uint256, type ArraySignatureType } from "starknet";

import { buf2hex } from "./bytes";
import { RawSigner } from "./starknet";
import { estimateAssertion, signTransaction, type WebauthnAssertion } from "./webauthnAssertion";
import type { WebauthnAttestation } from "./webauthnAttestation";

export class WebauthnOwner extends RawSigner {
  constructor(public attestation: WebauthnAttestation) {
    super();
  }

  public async signRaw(messageHash: string, isEstimation: boolean): Promise<ArraySignatureType> {
    console.log("WebauthnOwner signing transaction hash:", messageHash);
    const assertion = isEstimation
      ? await estimateAssertion(messageHash, this.attestation)
      : await signTransaction(messageHash, this.attestation);
    console.log("WebauthnOwner signed, assertion is:", assertion);
    const signature = this.compileAssertion(assertion);
    return signature;
  }

  public compileAssertion({ authenticatorData, clientDataJSON, r, s, yParity }: WebauthnAssertion): ArraySignatureType {
    const clientDataText = new TextDecoder().decode(clientDataJSON.buffer);
    const clientData = JSON.parse(clientDataText);
    const clientDataOffset = (substring: string) => clientDataText.indexOf(substring) + substring.length;
    console.log("client data", clientData);

    const cairoAssertion = {
      authenticator_data: Array.from(authenticatorData),
      client_data_json: Array.from(clientDataJSON),
      signature: {
        r: uint256.bnToUint256(buf2hex(r)),
        s: uint256.bnToUint256(buf2hex(s)),
        y_parity: yParity,
      },
      type_offset: clientDataOffset('"type":"'),
      challenge_offset: clientDataOffset('"challenge":"'),
      challenge_length: clientData.challenge.length,
      origin_offset: clientDataOffset('"origin":"'),
      origin_length: clientData.origin.length,
    };

    console.log("serialized assertion:", cairoAssertion);
    return CallData.compile(cairoAssertion);
  }
}
