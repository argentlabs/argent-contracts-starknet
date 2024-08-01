import { concatBytes } from "@noble/curves/abstract/utils";
import { p256 as secp256r1 } from "@noble/curves/p256";
import {
  ArraySignatureType,
  CairoCustomEnum,
  CallData,
  Uint256,
  hash,
  shortString,
  uint256,
} from "starknet";
import { KeyPair, SignerType, normalizeSecpR1Signature, signerTypeToCustomEnum } from "..";
import { buf2hex, hex2buf, normalizeTransactionHash, sha256, toCharArray, WebauthnSignature, WebauthnSigner } from "./webauthn";

export class WebauthnOwnerSyscall extends KeyPair {
  pk: Uint8Array;
  rpIdHash: Uint256;

  constructor(
    pk?: string,
    public rpId = "localhost",
    public origin = "http://localhost:5173",
  ) {
    super();
    this.pk = pk ? hex2buf(normalizeTransactionHash(pk)) : secp256r1.utils.randomPrivateKey();
    this.rpIdHash = uint256.bnToUint256(buf2hex(sha256(rpId)));
  }

  public get publicKey() {
    return secp256r1.getPublicKey(this.pk).slice(1);
  }

  public get guid(): bigint {
    const rpIdHashAsU256 = this.rpIdHash;
    const publicKeyAsU256 = uint256.bnToUint256(buf2hex(this.publicKey));
    const originBytes = toCharArray(this.origin);
    const elements = [
      shortString.encodeShortString("Webauthn Signer"),
      originBytes.length,
      ...originBytes,
      rpIdHashAsU256.low,
      rpIdHashAsU256.high,
      publicKeyAsU256.low,
      publicKeyAsU256.high,
    ];
    return BigInt(hash.computePoseidonHashOnElements(elements));
  }

  public get storedValue(): bigint {
    throw new Error("Not implemented yet");
  }

  public get signer(): CairoCustomEnum {
    const signer: WebauthnSigner = {
      origin: toCharArray(this.origin),
      rp_id_hash: this.rpIdHash,
      pubkey: uint256.bnToUint256(buf2hex(this.publicKey)),
    };
    return signerTypeToCustomEnum(SignerType.Webauthn, signer);
  }

  public async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const webauthnSigner = this.signer.variant.Webauthn;
    const webauthnSignature = await this.signHash(messageHash);
    return CallData.compile([signerTypeToCustomEnum(SignerType.Webauthn, { webauthnSigner, webauthnSignature })]);
  }

  public async signHash(transactionHash: string): Promise<WebauthnSignature> {
    const flags = "0b00000101"; // present and verified
    const signCount = 0;
    const authenticatorData = concatBytes(
      sha256(this.rpId),
      new Uint8Array([Number(flags), 0, 0, 0, signCount]),
    );

    const sha256Impl = 2;
    // TODO Challenge can be anything
    const challenge = BigInt(`0x${normalizeTransactionHash(transactionHash)}`) + `0${sha256Impl}`;
    const crossOrigin = false;
    const extraJson = ""; // = `,"extraField":"random data"}`;
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
        Syscall: sha256Impl == 2 ? {} : undefined,
      }),
    };
  }
}

export const randomWebauthnOwnerSyscall = () => new WebauthnOwnerSyscall();
