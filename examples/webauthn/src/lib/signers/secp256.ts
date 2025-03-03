import * as utils from "@noble/curves/abstract/utils";
import { p256 as secp256r1 } from "@noble/curves/p256";
import { secp256k1 } from "@noble/curves/secp256k1";
import { Signature as EthersSignature, Wallet } from "ethers";
import { CairoCustomEnum, CallData, Uint256, hash, num, shortString, uint256 } from "starknet";
import { EstimateKeyPair, KeyPair, SignerType, signerTypeToCustomEnum } from "../signers/signers";

export type NormalizedSecpSignature = { r: bigint; s: bigint; yParity: boolean };

export function normalizeSecpR1Signature(signature: {
  r: bigint;
  s: bigint;
  recovery: number;
}): NormalizedSecpSignature {
  return normalizeSecpSignature(secp256r1, signature);
}

export function normalizeSecpSignature(
  curve: typeof secp256r1 | typeof secp256k1,
  signature: { r: bigint; s: bigint; recovery: number },
): NormalizedSecpSignature {
  let s = signature.s;
  let yParity = signature.recovery !== 0;
  if (s > curve.CURVE.n / 2n) {
    s = curve.CURVE.n - s;
    yParity = !yParity;
  }
  return { r: signature.r, s, yParity };
}
