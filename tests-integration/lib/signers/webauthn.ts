import {
  Account,
  ArraySignatureType,
  CairoCustomEnum,
  CallData,
  RpcProvider,
  hash,
  num,
  shortString,
  uint256,
} from "starknet";
import { KeyPair, RawSigner, randomKeyPair } from "./signers";
import { p256 } from "@noble/curves/p256";
import { concatBytes } from "@noble/curves/abstract/utils";
import { AsnParser } from "@peculiar/asn1-schema";
import { ECDSASigValue } from "@peculiar/asn1-ecc";
import { fundAccount } from "../accounts";
import { loadContract } from "../contracts";

interface WebauthnAssertion {
  authenticatorData: Uint8Array;
  clientDataJSON: Uint8Array;
  r: Uint8Array;
  s: Uint8Array;
  yParity: boolean;
}

interface WebauthnAttestation {
  email: string;
  rpId: string;
  credentialId: Uint8Array;
  x: Uint8Array;
  y: Uint8Array;
}

const buf2hex = (buffer: ArrayBuffer, prefix = true) =>
  `${prefix ? "0x" : ""}${[...new Uint8Array(buffer)].map((x) => x.toString(16).padStart(2, "0")).join("")}`;

const hex2buf = (hex: string) =>
  Uint8Array.from(
    hex
      .replace(/^0x/, "")
      .match(/.{1,2}/g)!
      .map((byte) => parseInt(byte, 16)),
  );

export const randomBytes = (length: number) =>
  new Uint8Array(Array.from({ length }, () => Math.floor(Math.random() * 40)));

export const createWebauthnAttestation = async (email: string, rpId: string): Promise<WebauthnAttestation> => {
  const credential = await navigator.credentials.create({
    publicKey: {
      rp: { id: rpId, name: "Argent" },
      user: { id: randomBytes(32), name: email, displayName: email },
      challenge: randomBytes(32),
      pubKeyCredParams: [
        { type: "public-key", alg: -7 }, // -7 means secp256r1 with SHA-256 (ES256). RS256 not supported on purpose.
      ],
      authenticatorSelection: {
        authenticatorAttachment: "platform",
        residentKey: "preferred",
        requireResidentKey: false,
        userVerification: "required",
      },
      attestation: "none",
      extensions: { credProps: true },
      timeout: 60000,
    },
  });

  if (!credential) {
    throw new Error("No credential");
  }

  const attestation = credential as PublicKeyCredential;
  const attestationResponse = attestation.response as AuthenticatorAttestationResponse;

  const credentialId = new Uint8Array(attestation.rawId);
  const publicKey = new Uint8Array(attestationResponse.getPublicKey()!);
  const x = publicKey.slice(-64, -32);
  const y = publicKey.slice(-32);

  return { email, rpId, credentialId, x, y };
};

export const buf2base64 = (buffer: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(buffer)));

export const buf2base64url = (buffer: ArrayBuffer) =>
  buf2base64(buffer).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");

const shouldRemoveLeadingZero = (bytes: Uint8Array): boolean => bytes[0] === 0x0 && (bytes[1] & (1 << 7)) !== 0;

const getMessageHash = async (authenticatorData: Uint8Array, clientDataJSON: Uint8Array) => {
  const clientDataHash = await sha256(clientDataJSON);
  const message = concatBytes(authenticatorData, clientDataHash);
  return sha256(message);
};

const normalizeTransactionHash = (transactionHash: string) => transactionHash.replace(/^0x/, "").padStart(64, "0");

const sha256 = async (message: BufferSource) => new Uint8Array(await crypto.subtle.digest("SHA-256", message));

function parseASN1Signature(asn1Signature: BufferSource) {
  const signature = AsnParser.parse(asn1Signature, ECDSASigValue);
  let r = new Uint8Array(signature.r);
  let s = new Uint8Array(signature.s);

  if (shouldRemoveLeadingZero(r)) {
    r = r.slice(1);
  }

  if (shouldRemoveLeadingZero(s)) {
    s = s.slice(1);
  }

  return { r, s };
}

function getYParity(messageHash: Uint8Array, { x }: WebauthnAttestation, r: Uint8Array, s: Uint8Array) {
  const publicKeyX = BigInt(buf2hex(x));
  const signature = new p256.Signature(BigInt(buf2hex(r)), BigInt(buf2hex(s)));

  const recoveredEven = signature.addRecoveryBit(0).recoverPublicKey(messageHash);
  if (publicKeyX === recoveredEven.x) {
    return false;
  }
  const recoveredOdd = signature.addRecoveryBit(1).recoverPublicKey(messageHash);
  if (publicKeyX === recoveredOdd.x) {
    return true;
  }
  throw new Error("Could not determine y_parity");
}

async function signTransaction(transactionHash: string, attestation: WebauthnAttestation): Promise<WebauthnAssertion> {
  const challenge = hex2buf(normalizeTransactionHash(transactionHash));

  const credential = await navigator.credentials.get({
    publicKey: {
      rpId: attestation.rpId,
      challenge,
      allowCredentials: [{ id: attestation.credentialId, type: "public-key", transports: ["internal"] }],
      userVerification: "required",
      timeout: 60000,
    },
  });
  if (!credential) {
    throw new Error("No credential");
  }

  const assertion = credential as PublicKeyCredential;
  const assertionResponse = assertion.response as AuthenticatorAssertionResponse;
  const authenticatorData = new Uint8Array(assertionResponse.authenticatorData);
  const clientDataJSON = new Uint8Array(assertionResponse.clientDataJSON);
  const { r, s } = parseASN1Signature(assertionResponse.signature);
  const messageHash = await getMessageHash(authenticatorData, clientDataJSON);
  const yParity = getYParity(messageHash, attestation, r, s);

  return { authenticatorData, clientDataJSON, r, s, yParity };
}
// export class WebauthnKeyPair extends KeyPair {
//   constructor(public attestation: WebauthnAttestation) {
//     super();
//   }

//   public get publicKey() {
//     throw new Error("Function not implemented.");
//   }

//   public get signerType() {
//     throw new Error("Function not implemented.");
//     return webauthnSigner(0n, 0n, 0n);
//   }

//   public async signHash(messageHash: string) {
//     console.log("WebauthnOwner signing transaction hash:", messageHash);
//     const assertion = await signTransaction(messageHash, this.attestation);
//     console.log("WebauthnOwner signed, assertion is:", assertion);
//     return webauthnSignatureType(assertion);
//   }
// }

export class WebauthnOwner extends RawSigner {
  constructor(public attestation: WebauthnAttestation) {
    super();
  }

  public async signRaw(messageHash: string): Promise<ArraySignatureType> {
    console.log("WebauthnOwner signing transaction hash:", messageHash);
    const assertion = await signTransaction(messageHash, this.attestation);
    console.log("WebauthnOwner signed, assertion is:", assertion);
    const signature = this.compileAssertion(assertion);
    return signature;
  }

  public compileAssertion({ authenticatorData, clientDataJSON, r, s, yParity }: WebauthnAssertion): ArraySignatureType {
    const clientDataText = new TextDecoder().decode(clientDataJSON.buffer);
    const clientData = JSON.parse(clientDataText);
    const clientDataOffset = (substring: string) => clientDataText.indexOf(substring) + substring.length;
    console.log("client data", clientData);

    const cairoAssertion = {
      authenticator_data: Array.from(authenticatorData),
      client_data_json: Array.from(clientDataJSON),
      signature: {
        r: uint256.bnToUint256(buf2hex(r)),
        s: uint256.bnToUint256(buf2hex(s)),
        y_parity: yParity,
      },
      type_offset: clientDataOffset('"type":"'),
      challenge_offset: clientDataOffset('"challenge":"'),
      challenge_length: clientData.challenge.length,
      origin_offset: clientDataOffset('"origin":"'),
      origin_length: clientData.origin.length,
    };

    console.log("serialized assertion:", cairoAssertion);
    return CallData.compile(cairoAssertion);
  }
}

export function webauthnSignatureType({ authenticatorData, clientDataJSON, r, s, yParity }: WebauthnAssertion) {
  const clientDataText = new TextDecoder().decode(clientDataJSON.buffer);
  const clientData = JSON.parse(clientDataText);
  const clientDataOffset = (substring: string) => clientDataText.indexOf(substring) + substring.length;
  console.log("client data", clientData);

  return CallData.compile([
    new CairoCustomEnum({
      Starknet: undefined,
      Secp256k1: undefined,
      Secp256r1: undefined,
      Webauthn: {
        authenticator_data: Array.from(authenticatorData),
        client_data_json: Array.from(clientDataJSON),
        signature: {
          r: uint256.bnToUint256(buf2hex(r)),
          s: uint256.bnToUint256(buf2hex(s)),
          y_parity: yParity,
        },
        type_offset: clientDataOffset('"type":"'),
        challenge_offset: clientDataOffset('"challenge":"'),
        challenge_length: clientData.challenge.length,
        origin_offset: clientDataOffset('"origin":"'),
        origin_length: clientData.origin.length,
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

// export const randomWebauthnKeyPair = () => new WebauthnKeyPair();

export async function deployWebauthnAccount(
  classHash: string,
  webauthnOwner: WebauthnOwner,
  starkOwner: KeyPair,
  rpId: string,
  provider: RpcProvider,
): Promise<any> {
  if (location.origin.length > 30) {
    throw new Error("origin must be less than 30 characters");
  }
  const rpIdHash = await sha256(new TextEncoder().encode(rpId));
  const constructorCalldata = CallData.compile({
    owner: starkOwner.publicKey,
    webauthn_owner: uint256.bnToUint256(buf2hex(webauthnOwner.attestation.x)),
    origin: shortString.encodeShortString(location.origin),
    rp_id_hash: uint256.bnToUint256(buf2hex(rpIdHash)),
  });

  const addressSalt = num.toHex(randomKeyPair().privateKey);
  const accountAddress = hash.calculateContractAddressFromHash(addressSalt, classHash, constructorCalldata, 0);

  await fundAccount(accountAddress, 1e14, "ETH");

  // can use either starkOwner or webauthnOwner as signer
  const account = new Account(provider, accountAddress, webauthnOwner, "1");

  console.log("deploying account to address", accountAddress);
  const response = await account.deploySelf({ classHash, constructorCalldata, addressSalt });
  console.log("waiting for deployment tx", response.transaction_hash);
  await provider.waitForTransaction(response.transaction_hash);

  const accountContract = await loadContract(account.address);
  accountContract.connect(account);
  console.log("deployed");

  return { account, accountContract, starkOwner, webauthnOwner };
}
