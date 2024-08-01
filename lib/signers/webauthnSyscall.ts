import { concatBytes } from "@noble/curves/abstract/utils";
import { p256 as secp256r1 } from "@noble/curves/p256";
import { CairoCustomEnum, CallData, uint256 } from "starknet";
import { normalizeSecpR1Signature } from "..";
import { WebauthnOwner, WebauthnSignature, normalizeTransactionHash, sha256, toCharArray } from "./webauthn";

// There should be a common webauthn, interface to implement just the move parts
export class WebauthnOwnerSyscall extends WebauthnOwner {
  public async signHash(transactionHash: string): Promise<WebauthnSignature> {
    const flags = "0b00000101"; // present and verified
    const signCount = 0;
    const authenticatorData = concatBytes(sha256(this.rpId), new Uint8Array([Number(flags), 0, 0, 0, signCount]));

    const sha256Impl = 2;
    // Challenge can be anything
    const challenge = BigInt(`0x${normalizeTransactionHash(transactionHash)}`) + `0${sha256Impl}`;
    const crossOrigin = false;
    const extraJson = ""; //`,"extraField":"random data"}`;
    const clientData = JSON.stringify({ type: "webauthn.get", challenge, origin: this.origin, crossOrigin });
    const clientDataJson = extraJson ? clientData.replace(/}$/, extraJson) : clientData;
    const clientDataHash = sha256(new TextEncoder().encode(clientDataJson));
    const signedHash = sha256(concatBytes(authenticatorData, clientDataHash));

    const signature = normalizeSecpR1Signature(secp256r1.sign(signedHash, this.pk));

    return {
      cross_origin: crossOrigin,
      client_data_json_outro: CallData.compile(toCharArray(extraJson)),
      flags: Number(flags),
      sign_count: signCount,
      ec_signature: {
        r: uint256.bnToUint256(signature.r),
        s: uint256.bnToUint256(signature.s),
        y_parity: signature.yParity,
      },
      sha256_implementation: new CairoCustomEnum({
        Cairo0: undefined,
        Cairo1: undefined,
        Syscall: {},
      }),
    };
  }
}

export const randomWebauthnOwnerSyscall = () => new WebauthnOwnerSyscall();
