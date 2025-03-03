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
import { EstimateKeyPair, KeyPair, SignerType, normalizeSecpR1Signature, signerTypeToCustomEnum } from "..";

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

function numberToBytes(input: number): [number, number, number, number] {
  const bytes = new Array(4).fill(0);

  if (input < 0 || input > 0xffffffff) {
    throw new Error("Input number must be between 0 and 2^32 - 1.");
  }

  for (let i = 3; i >= 0; i--) {
    bytes[i] = input & 0xff; // Extract the least significant byte
    input = input >> 8; // Shift right to process the next byte
  }

  return bytes as [number, number, number, number];
}

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
}

export class WebauthnOwner extends KeyPair {
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
    return this.guid;
  }

  public get signerType(): SignerType {
    return SignerType.Webauthn;
  }

  public get signer(): CairoCustomEnum {
    const signer: WebauthnSigner = {
      origin: toCharArray(this.origin),
      rp_id_hash: this.rpIdHash,
      pubkey: uint256.bnToUint256(buf2hex(this.publicKey)),
    };
    return signerTypeToCustomEnum(this.signerType, signer);
  }

  public get estimateSigner(): KeyPair {
    return new EstimateWebauthnOwner(this.publicKey, this.rpId, this.origin);
  }

  public async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const webauthnSigner = this.signer.variant.Webauthn;
    const webauthnSignature = await this.signHash(messageHash);
    return CallData.compile([signerTypeToCustomEnum(this.signerType, { webauthnSigner, webauthnSignature })]);
  }

  public async signHash(transactionHash: string): Promise<WebauthnSignature> {
    const flags = Number("0b00000101"); // present and verified
    const signCount = 1;
    const authenticatorData = concatBytes(sha256(this.rpId), new Uint8Array([flags, ...numberToBytes(signCount)]));

    const challenge = buf2base64url(hex2buf(normalizeTransactionHash(transactionHash)));

    const clientData = JSON.stringify(this.getClientData(challenge));

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
    // };`);

    const signatureObj: WebauthnSignature = {
      client_data_json_outro: CallData.compile(toCharArray(extraJson)),
      flags,
      sign_count: signCount,
      ec_signature: {
        r: uint256.bnToUint256(signature.r),
        s: uint256.bnToUint256(signature.s),
        y_parity: signature.yParity,
      },
    };
    return signatureObj;
  }

  getClientData(challenge: string): any {
    return { type: "webauthn.get", challenge, origin: this.origin };
  }
}

export class EstimateWebauthnOwner extends EstimateKeyPair {
  rpIdHash: Uint256;

  constructor(
    public publicKey: ArrayBuffer,
    public rpId = "localhost",
    public origin = "http://localhost:5173",
  ) {
    super();
    this.rpIdHash = uint256.bnToUint256(buf2hex(sha256(rpId)));
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

  public get signerType(): SignerType {
    return SignerType.Webauthn;
  }

  public override async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const webauthnSigner = this.signer.variant.Webauthn;
    const webauthnSignature = {
      client_data_outro: CallData.compile(Array.from(new TextEncoder().encode(',"crossOrigin":false}'))),
      flags: 0b00011101,
      sign_count: 0,
      ec_signature: {
        r: uint256.bnToUint256("0xc303f24e2f6970f0cd1521c1ff6c661337e4a397a9d4b1bed732f14ddcb828cb"),
        s: uint256.bnToUint256("0x61d2ef1fa3c30486656361c783ae91316e9e78301fbf4f173057ea868487d387"),
        y_parity: false,
      },
    };
    return CallData.compile([
      signerTypeToCustomEnum(SignerType.Webauthn, {
        webauthnSigner,
        webauthnSignature,
      }),
    ]);
  }
}

// LEGACY WEBAUTHN
type LegacyWebauthnSignature = {
  cross_origin: boolean;
} & WebauthnSignature & {
    sha256_implementation: CairoCustomEnum;
  };

export class LegacyWebauthnOwner extends WebauthnOwner {
  crossOrigin = false;

  public getPrivateKey(): string {
    return buf2hex(this.pk);
  }

  getClientData(challenge: string): any {
    return { ...super.getClientData(challenge), crossOrigin: this.crossOrigin };
  }

  public override get estimateSigner(): KeyPair {
    return new EstimateLegacyWebauthnOwner(this.publicKey, this.rpId, this.origin);
  }

  public async signHash(transactionHash: string): Promise<LegacyWebauthnSignature> {
    const webauthnSignature = await super.signHash(`${normalizeTransactionHash(transactionHash)}01`);
    return {
      cross_origin: this.crossOrigin,
      ...webauthnSignature,
      sha256_implementation: new CairoCustomEnum({
        Cairo0: undefined,
        Cairo1: {},
      }),
    };
  }
}

export class EstimateLegacyWebauthnOwner extends EstimateWebauthnOwner {
  public override async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const webauthnSigner = this.signer.variant.Webauthn;
    const webauthnSignature = {
      cross_origin: false,
      client_data_outro: CallData.compile(Array.from(new TextEncoder().encode(',"crossOrigin":false}'))),
      flags: 0b00011101,
      sign_count: 0,
      ec_signature: {
        r: uint256.bnToUint256("0xc303f24e2f6970f0cd1521c1ff6c661337e4a397a9d4b1bed732f14ddcb828cb"),
        s: uint256.bnToUint256("0x61d2ef1fa3c30486656361c783ae91316e9e78301fbf4f173057ea868487d387"),
        y_parity: false,
      },
      sha256_implementation: new CairoCustomEnum({
        Cairo0: undefined,
        Cairo1: {},
      }),
    };
    return CallData.compile([
      signerTypeToCustomEnum(SignerType.Webauthn, {
        webauthnSigner,
        webauthnSignature,
      }),
    ]);
  }
}

function sha256(message: BinaryLike) {
  return createHash("sha256").update(message).digest();
}

export const randomWebauthnOwner = () => new WebauthnOwner(undefined, undefined, undefined);
export const randomWebauthnLegacyOwner = () => new LegacyWebauthnOwner(undefined, undefined, undefined);
