import { CairoCustomEnum, CallData, num, uint256, Uint256 } from "starknet";
import { p256 as secp256r1 } from "@noble/curves/p256";
import * as utils from "@noble/curves/abstract/utils";
import { RecoveredSignatureType } from "@noble/curves/abstract/weierstrass";
import { Wallet, Signature as EthersSignature } from "ethers";
import { KeyPair } from "../signers/signers";

export class EthKeyPair extends KeyPair {
  pk: string;

  constructor(pk?: string | bigint) {
    super();
    if (pk) {
      this.pk = "0x" + fixedLength(num.toHex(pk));
    } else {
      this.pk = Wallet.createRandom().privateKey;
    }
  }

  public get privateKey(): string {
    return this.pk;
  }

  public get publicKey() {
    return BigInt(new Wallet(this.pk).address);
  }

  public get signer(): CairoCustomEnum {
    return new CairoCustomEnum({
      Starknet: undefined,
      Secp256k1: { signer: this.publicKey },
      Secp256r1: undefined,
      Webauthn: undefined,
    });
  }

  public async signRaw(messageHash: string): Promise<string[]> {
    const eth_signer = new Wallet(this.pk);
    messageHash = "0x" + fixedLength(messageHash);
    const signature = EthersSignature.from(eth_signer.signingKey.sign(messageHash));

    return ethereumSignatureType(this.publicKey, signature);
  }
}

export class Secp256r1KeyPair extends KeyPair {
  pk: bigint;

  constructor(pk?: string | bigint) {
    super();
    this.pk = BigInt(pk ? `${pk}` : Wallet.createRandom().privateKey);
  }

  public get privateKey(): string {
    return this.pk.toString();
  }

  public get publicKey() {
    const publicKey = secp256r1.getPublicKey(this.pk).slice(1);
    return uint256.bnToUint256("0x" + utils.bytesToHex(publicKey));
  }

  public get signer() {
    return new CairoCustomEnum({
      Starknet: undefined,
      Secp256k1: undefined,
      Secp256r1: { signer: this.publicKey },
      Webauthn: undefined,
    });
  }

  public async signRaw(messageHash: string): Promise<string[]> {
    messageHash = fixedLength(messageHash);
    const sig = secp256r1.sign(messageHash, this.pk);

    return secp256r1SignatureType(this.publicKey, sig);
  }
}

function ethereumSignatureType(signer: bigint, signature: EthersSignature) {
  return CallData.compile([
    new CairoCustomEnum({
      Starknet: undefined,
      Secp256k1: {
        signer,
        r: uint256.bnToUint256(signature.r),
        s: uint256.bnToUint256(signature.s),
        y_parity: signature.yParity,
      },
      Secp256r1: undefined,
      Webauthn: undefined,
    }),
  ]);
}

function secp256r1SignatureType(signer: Uint256, signature: RecoveredSignatureType) {
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

function fixedLength(hexString: string): string {
  if (hexString.length < 66) {
    hexString = "0".repeat(66 - hexString.length) + hexString.slice(2);
  }
  return hexString;
}
