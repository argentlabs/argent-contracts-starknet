import { CallData, uint256, type ArraySignatureType, CairoCustomEnum } from "starknet";

import { buf2hex } from "./bytes";
import { RawSigner } from "./starknet";
import { estimateAssertion, signTransaction, type WebauthnAssertion } from "./webauthnAssertion";
import type { WebauthnAttestation } from "./webauthnAttestation";
import { rpIdHash } from "./argent";

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
      origin: location.origin,
      rp_id_hash: uint256.bnToUint256(BigInt(buf2hex(rpIdHash))),
      pubkey: uint256.bnToUint256(BigInt(buf2hex(this.attestation.x))),
      authenticator_data: CallData.compile(Array.from(authenticatorData)),
      client_data_json: CallData.compile(Array.from(clientDataJSON)),
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
    return CallData.compile([
      [
        new CairoCustomEnum({
          Starknet: undefined,
          Secp256k1: undefined,
          Secp256r1: undefined,
          Webauthn: cairoAssertion,
        }),
      ],
    ]);
  }
}

export function webauthnSigner(origin: string, rp_id_hash: string, pubkey: string) {
  return new CairoCustomEnum({
    Starknet: undefined,
    Secp256k1: undefined,
    Secp256r1: undefined,
    Webauthn: {
      origin,
      rp_id_hash: uint256.bnToUint256(BigInt(rp_id_hash)),
      pubkey: uint256.bnToUint256(BigInt(pubkey)),
    },
  });
}
