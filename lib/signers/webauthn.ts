import { concatBytes } from "@noble/curves/abstract/utils";
import { p256 as secp256r1 } from "@noble/curves/p256";
import { BinaryLike, createHash } from "crypto";
import { ArraySignatureType, CairoCustomEnum, CallData, RawArgs, Uint256, hash, shortString, uint256 } from "starknet";
import { KeyPair, SignerType, signerTypeToCustomEnum } from "..";

// Bytes fn
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

interface WebauthnAssertion {
  authenticator_data: AuthenticatorData;
  cross_origin: boolean;
  client_data_json_outro: number[];
  sha256_implementation: CairoCustomEnum;
  signature: { r: Uint256; s: Uint256; y_parity: boolean; };
}

interface AuthenticatorData {
  rp_id_hash: Uint256;
  flags: number;
  sign_count: number;
}

export class WebauthnOwner extends KeyPair {
  pk: Uint8Array;
  rpIdHash: Uint256;

  constructor(pk?: string, public rpId = "localhost", public origin = "http://localhost:5173") {
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
    return signerTypeToCustomEnum(SignerType.Webauthn, {
      origin: toCharArray(this.origin),
      rp_id_hash: this.rpIdHash,
      pubkey: uint256.bnToUint256(buf2hex(this.publicKey)),
    });
  }

  public async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const webauthnSigner = this.signer.variant.Webauthn;
    const webauthnAssertion = await this.signHash(messageHash);
    return CallData.compile([signerTypeToCustomEnum(SignerType.Webauthn, { webauthnSigner, webauthnAssertion })]);
  }

  public async signHash(transactionHash: string): Promise<WebauthnAssertion> {
    const flags = 0b0101; // present and verified
    const authenticator_data = { rp_id_hash: this.rpIdHash, flags, sign_count: 0 };
    const authenticatorBytes = concatBytes(sha256(this.rpId), new Uint8Array([flags]), new Uint8Array(4));

    const challenge = buf2base64url(hex2buf(normalizeTransactionHash(transactionHash) + "00"));
    const clientData = { type: "webauthn.get", challenge, origin: this.origin, crossOrigin: false };
    const clientDataJson = new TextEncoder().encode(JSON.stringify(clientData));

    const message = concatBytes(authenticatorBytes, sha256(clientDataJson));
    const messageHash = sha256(message);

    const { r, s, recovery } = secp256r1.sign(messageHash, this.pk);

    return {
      authenticator_data,
      cross_origin: false,
      client_data_json_outro: [],
      sha256_implementation: new CairoCustomEnum({ Cairo0: {}, Cairo1: undefined }),
      signature: {
        r: uint256.bnToUint256(r),
        s: uint256.bnToUint256(s),
        y_parity: recovery !== 0,
      },
    }
  }
}

function sha256(message: BinaryLike) {
  return createHash("sha256").update(message).digest();
}

export const randomWebauthnOwner = () => new WebauthnOwner();
