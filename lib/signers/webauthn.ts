import { concatBytes } from "@noble/curves/abstract/utils";
import { p256 as secp256r1 } from "@noble/curves/p256";
import { BinaryLike, createHash } from "crypto";
import {
  ArraySignatureType,
  BigNumberish,
  CairoCustomEnum,
  CallData,
  Uint256,
  hash,
  shortString,
  uint256,
} from "starknet";
import { KeyPair, SignerType, normalizeSecpR1Signature, signerTypeToCustomEnum } from "..";

const buf2hex = (buffer: ArrayBuffer, prefix = true) =>
  `${prefix ? "0x" : ""}${[...new Uint8Array(buffer)].map((x) => x.toString(16).padStart(2, "0")).join("")}`;

const normalizeTransactionHash = (transactionHash: string) => transactionHash.replace(/^0x/, "").padStart(64, "0");

const buf2base64url = (buffer: ArrayBuffer) =>
  buf2base64(buffer).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");

const buf2base64 = (buffer: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(buffer)));

const hex2buf = (hex: string) =>
  Uint8Array.from(
    hex
      .replace(/^0x/, "")
      .match(/.{1,2}/g)!
      .map((byte) => parseInt(byte, 16)),
  );

const toCharArray = (value: string) => CallData.compile(value.split("").map(shortString.encodeShortString));

interface WebauthnSigner {
  origin: BigNumberish[];
  rp_id_hash: Uint256;
  pubkey: Uint256;
}

interface WebauthnSignature {
  client_data_json_outro: BigNumberish[];
  flags: number;
  sign_count: number;
  ec_signature: { r: Uint256; s: Uint256; y_parity: boolean };
  sha256_implementation: CairoCustomEnum;
}

export class WebauthnOwner extends KeyPair {
  pk: Uint8Array;
  rpIdHash: Uint256;

  constructor(
    pk?: string,
    public rpId = "localhost",
    public origin = "http://localhost:5173",
    public useCairo0Sha256 = false,
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
    const flags = Number("0b00000101"); // present and verified
    const signCount = 0;
    const authenticatorData = concatBytes(sha256(this.rpId), new Uint8Array([flags, 0, 0, 0, signCount]));

    const sha256Impl = this.useCairo0Sha256 ? "0" : "1";
    const challenge = buf2base64url(hex2buf(`${normalizeTransactionHash(transactionHash)}0${sha256Impl}`));
    const clientData = JSON.stringify({ type: "webauthn.get", challenge, origin: this.origin });

    // const extraJson = "";
    const extraJson = `,"crossOrigin":false}`;
    // const extraJson = `,"crossOrigin":false,"extraField":"random data"}`;
    const clientDataJson = extraJson ? clientData.replace(/}$/, extraJson) : clientData;
    const clientDataHash = sha256(new TextEncoder().encode(clientDataJson));

    const signedHash = sha256(concatBytes(authenticatorData, clientDataHash));

    const signature = normalizeSecpR1Signature(secp256r1.sign(signedHash, this.pk));

    // console.log(`
    // let transaction_hash = ${transactionHash};
    // let pubkey = ${buf2hex(this.publicKey)};
    // let challenge = ${challenge};
    // let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    // let signature = WebauthnSignature {
    //     client_data_json_outro: ${extraJson ? `${JSON.stringify(extraJson)}.into_bytes()` : "array![]"}.span(),
    //     flags: ${flags},
    //     sign_count: ${signCount},
    //     ec_signature: Signature {
    //         r: 0x${signature.r.toString(16)},
    //         s: 0x${signature.s.toString(16)},
    //         y_parity: ${signature.yParity},
    //     },
    //     sha256_implementation: Sha256Implementation::Cairo${sha256Impl},
    // };`);

    return {
      client_data_json_outro: CallData.compile(toCharArray(extraJson)),
      flags,
      sign_count: signCount,
      ec_signature: {
        r: uint256.bnToUint256(signature.r),
        s: uint256.bnToUint256(signature.s),
        y_parity: signature.yParity,
      },
      sha256_implementation: new CairoCustomEnum({
        Cairo0: this.useCairo0Sha256 ? {} : undefined,
        Cairo1: this.useCairo0Sha256 ? undefined : {},
      }),
    };
  }
}

// LEGACY WEBAUTHN
type LegacyWebauthnSignature = {
  cross_origin: boolean;
} & WebauthnSignature;

// TODO ANSWER: Code of this is quite copy paste... Should I refactor or leave as is?
// Feel like it's better to leave as is to avoid cluttering the regular WebauthnOwner with more overhead
export class LegacyWebauthnOwner extends WebauthnOwner {
  public getPrivateKey(): string {
    return buf2hex(this.pk);
  }

  public async signHash(transactionHash: string): Promise<LegacyWebauthnSignature> {
    const flags = Number("0b00000101"); // present and verified
    const signCount = 0;
    const authenticatorData = concatBytes(sha256(this.rpId), new Uint8Array([flags, 0, 0, 0, signCount]));

    const sha256Impl = this.useCairo0Sha256 ? "0" : "1";
    const challenge = buf2base64url(hex2buf(`${normalizeTransactionHash(transactionHash)}0${sha256Impl}`));
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
      flags,
      sign_count: signCount,
      ec_signature: {
        r: uint256.bnToUint256(signature.r),
        s: uint256.bnToUint256(signature.s),
        y_parity: signature.yParity,
      },
      sha256_implementation: new CairoCustomEnum({
        Cairo0: this.useCairo0Sha256 ? {} : undefined,
        Cairo1: this.useCairo0Sha256 ? undefined : {},
      }),
    };
  }
}

function sha256(message: BinaryLike) {
  return createHash("sha256").update(message).digest();
}

export const randomWebauthnOwner = () => new WebauthnOwner(undefined, undefined, undefined, false);
export const randomWebauthnCairo0Owner = () => new WebauthnOwner(undefined, undefined, undefined, true);
export const randomWebauthnLegacyOwner = () => new LegacyWebauthnOwner(undefined, undefined, undefined, false);
export const randomWebauthnLegacyCairo0Owner = () => new LegacyWebauthnOwner(undefined, undefined, undefined, true);
