import {
  Account,
  ArraySignatureType,
  CairoCustomEnum,
  CairoOption,
  CairoOptionVariant,
  CallData,
  hash,
  num,
  uint256,
} from "starknet";
import { concatBytes } from "@noble/curves/abstract/utils";
import { SignatureType } from "@noble/curves/abstract/weierstrass";
import { p256 as secp256r1 } from "@noble/curves/p256";
import { KeyPair, SignerType, fundAccount, provider, signerTypeToCustomEnum } from "..";
import { BinaryLike, createHash } from "crypto";

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

// Constants
const rpIdHash = sha256("localhost");
const origin = "http://localhost:5173";

interface WebauthnAssertion {
  authenticatorData: Uint8Array;
  clientDataJson: Uint8Array;
  r: bigint;
  s: bigint;
  yParity: boolean;
}

class WebauthnOwner extends KeyPair {
  pk: Uint8Array;

  constructor(pk?: Uint8Array) {
    super();
    this.pk = pk ?? secp256r1.utils.randomPrivateKey();
  }

  public get publicKey() {
    return secp256r1.getPublicKey(this.pk).slice(1);
  }

  public get guid(): bigint {
    throw new Error("Not yet implemented");
  }

  public get signer(): CairoCustomEnum {
    return signerTypeToCustomEnum(SignerType.Webauthn, {
      origin,
      rp_id_hash: uint256.bnToUint256(buf2hex(rpIdHash)),
      pubkey: uint256.bnToUint256(buf2hex(this.publicKey)),
    });
  }

  public async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const { authenticatorData, clientDataJson, r, s, yParity } = await this.signHash(messageHash);
    const clientDataText = new TextDecoder().decode(clientDataJson.buffer);
    const clientData = JSON.parse(clientDataText);
    const clientDataOffset = (substring: string) => clientDataText.indexOf(substring) + substring.length;

    const cairoAssertion = {
      origin,
      rp_id_hash: uint256.bnToUint256(buf2hex(rpIdHash)),
      pubkey: uint256.bnToUint256(buf2hex(this.publicKey)),
      authenticator_data: CallData.compile(Array.from(authenticatorData)),
      client_data_json: CallData.compile(Array.from(clientDataJson)),
      signature: {
        r: uint256.bnToUint256(r),
        s: uint256.bnToUint256(s),
        y_parity: yParity,
      },
      type_offset: clientDataOffset('"type":"'),
      challenge_offset: clientDataOffset('"challenge":"'),
      challenge_length: clientData.challenge.length,
      origin_offset: clientDataOffset('"origin":"'),
      origin_length: clientData.origin.length,
    };

    return CallData.compile([[signerTypeToCustomEnum(SignerType.Webauthn, cairoAssertion)]]);
  }

  public async signHash(transactionHash: string): Promise<WebauthnAssertion> {
    const flags = new Uint8Array([0b0001 | 0b0100]); // present and verified
    const signCount = new Uint8Array(4); // [0_u8, 0_u8, 0_u8, 0_u8]
    const authenticatorData = concatBytes(rpIdHash, flags, signCount);

    const challenge = buf2base64url(hex2buf(normalizeTransactionHash(transactionHash)));
    const clientData = { type: "webauthn.get", challenge, origin: "http://localhost:5173", crossOrigin: false };
    const clientDataJson = new TextEncoder().encode(JSON.stringify(clientData));

    const message = concatBytes(authenticatorData, sha256(clientDataJson));
    const messageHash = sha256(message);

    const signature = secp256r1.sign(messageHash, this.pk);

    return { authenticatorData, clientDataJson, r: signature.r, s: signature.s, yParity: signature.recovery !== 0 };
  }
}

function sha256(message: BinaryLike) {
  return createHash("sha256").update(message).digest();
}

export async function deployWebauthnAccount(classHash: string): Promise<Account> {
  const owner = new WebauthnOwner();
  const constructorCalldata = CallData.compile({
    owner: owner.signer,
    guardian: new CairoOption(CairoOptionVariant.None),
  });
  const addressSalt = 12n;
  const accountAddress = hash.calculateContractAddressFromHash(addressSalt, classHash, constructorCalldata, 0);

  await fundAccount(accountAddress, 1e16, "ETH");

  const account = new Account(provider, accountAddress, owner, "1");
  const response = await account.deploySelf({ classHash, constructorCalldata, addressSalt }, { maxFee: 1e15 });
  await provider.waitForTransaction(response.transaction_hash);

  return account;
}
