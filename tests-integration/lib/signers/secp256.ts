import { CairoCustomEnum, CallData, uint256, Uint256 } from "starknet";
import { p256 as secp256r1 } from "@noble/curves/p256";
import * as utils from "@noble/curves/abstract/utils";
import { RecoveredSignatureType } from "@noble/curves/abstract/weierstrass";
import { Wallet, id, Signature as EthersSignature } from "ethers";
import { KeyPair } from "./signers";

export class EthKeyPair extends KeyPair {
  public get publicKey() {
    return BigInt(new Wallet(id(this.privateKey.toString())).address);
  }

  public get getSignerType() {
    return ethSigner(this.publicKey);
  }

  public signHash(messageHash: string) {
    const eth_signer = new Wallet(id(this.privateKey.toString()));
    if (messageHash.length < 66) {
      messageHash = "0x" + "0".repeat(66 - messageHash.length) + messageHash.slice(2);
    }
    const signature = EthersSignature.from(eth_signer.signingKey.sign(messageHash));
    return ethereumSignatureType(this.publicKey, signature);
  }
}

export class Secp256r1KeyPair extends KeyPair {
  public get publicKey() {
    const publicKey = secp256r1.getPublicKey(this.privateKey).slice(1);
    return uint256.bnToUint256("0x" + utils.bytesToHex(publicKey));
  }

  public get getSignerType() {
    return secp256r1Signer(this.publicKey);
  }

  public signHash(messageHash: string) {
    if (messageHash.length < 66) {
      messageHash = "0".repeat(66 - messageHash.length) + messageHash.slice(2);
    }
    const sig = secp256r1.sign(messageHash, this.privateKey);
    return secp256r1SignatureType(this.publicKey, sig);
  }
}

export function ethereumSignatureType(signer: bigint, signature: EthersSignature) {
  return CallData.compile([
    new CairoCustomEnum({
      Starknet: undefined,
      Secp256k1: {
        signer,
        r: uint256.bnToUint256(signature.r),
        s: uint256.bnToUint256(signature.s),
        y_parity: signature.yParity.toString(),
      },
      Secp256r1: undefined,
      Webauthn: undefined,
    }),
  ]);
}

export function secp256r1SignatureType(signer: Uint256, signature: RecoveredSignatureType) {
  return CallData.compile([
    new CairoCustomEnum({
      Starknet: undefined,
      Secp256k1: undefined,
      Secp256r1: {
        signer,
        r: uint256.bnToUint256(signature.r),
        s: uint256.bnToUint256(signature.s),
        y_parity: signature.recovery,
      },
      Webauthn: undefined,
    }),
  ]);
}

export function ethSigner(signer: bigint) {
  return new CairoCustomEnum({
    Starknet: undefined,
    Secp256k1: { signer },
    Secp256r1: undefined,
    Webauthn: undefined,
  });
}

export function secp256r1Signer(signer: Uint256) {
  return new CairoCustomEnum({
    Starknet: undefined,
    Secp256k1: undefined,
    Secp256r1: { signer },
    Webauthn: undefined,
  });
}

export const randomEthKeyPair = () => new EthKeyPair();
export const randomSecp256r1KeyPair = () => new Secp256r1KeyPair();
