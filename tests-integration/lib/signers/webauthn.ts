import { CairoCustomEnum, CallData, uint256 } from "starknet";
import { KeyPair } from "./signers";

export class WebauthnKeyPair extends KeyPair {
  public get publicKey() {
    throw new Error("Function not implemented.");
  }

  public get getSignerType() {
    throw new Error("Function not implemented.");
    return webauthnSigner(0n, 0n, 0n);
  }

  public signHash(messageHash: string) {
    throw new Error("Function not implemented.");
    return webauthnSignatureType();
  }
}

export function webauthnSignatureType() {
  return CallData.compile([
    new CairoCustomEnum({
      Starknet: undefined,
      Secp256k1: undefined,
      Secp256r1: undefined,
      Webauthn: {
        authenticator_data: [], //Span<u8>,
        client_data_json: [], //Span<u8>,
        signature: {
          r: uint256.bnToUint256(0n),
          s: uint256.bnToUint256(0n),
          y_parity: 0,
        },
        type_offset: 0, // usize,
        challenge_offset: 0, // usize,
        challenge_length: 0, //usize,
        origin_offset: 0, //usize,
        origin_length: 0, //usize,
      },
    }),
  ]);
}

export function webauthnSigner(origin: bigint, rp_id_hash: bigint, pubkey: bigint) {
  return new CairoCustomEnum({
    Starknet: undefined,
    Secp256k1: undefined,
    Secp256r1: undefined,
    Webauthn: { origin, rp_id_hash: uint256.bnToUint256(rp_id_hash), pubkey: uint256.bnToUint256(pubkey) },
  });
}

export const randomWebauthnKeyPair = () => new WebauthnKeyPair();
