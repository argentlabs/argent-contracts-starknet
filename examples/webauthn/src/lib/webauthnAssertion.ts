import { concatBytes } from "@noble/curves/abstract/utils";
import { p256 } from "@noble/curves/p256";
import { ECDSASigValue } from "@peculiar/asn1-ecc";
import { AsnParser } from "@peculiar/asn1-schema";

import { buf2base64url, buf2hex, hex2buf } from "./bytes";
import { normalizeTransactionHash } from "./starknet";
import type { WebauthnAttestation } from "./webauthnAttestation";

export interface WebauthnAssertion {
  authenticatorData: Uint8Array;
  clientDataJSON: Uint8Array;
  r: Uint8Array;
  s: Uint8Array;
  yParity: boolean;
}

export const signTransaction = async (
  transactionHash: string,
  attestation: WebauthnAttestation,
): Promise<WebauthnAssertion> => {
  const challenge = hex2buf(normalizeTransactionHash(transactionHash) + "00");

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
};

/**
 * In WebAuthn, EC2 signatures are wrapped in ASN.1 structure so we need to peel r and s apart.
 *
 * See https://www.w3.org/TR/webauthn-2/#sctn-signature-attestation-types
 */
export const parseASN1Signature = (asn1Signature: BufferSource) => {
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
};

const shouldRemoveLeadingZero = (bytes: Uint8Array): boolean => bytes[0] === 0x0 && (bytes[1] & (1 << 7)) !== 0;

export const sha256 = async (message: BufferSource) => new Uint8Array(await crypto.subtle.digest("SHA-256", message));

const getMessageHash = async (authenticatorData: Uint8Array, clientDataJSON: Uint8Array) => {
  const clientDataHash = await sha256(clientDataJSON);
  const message = concatBytes(authenticatorData, clientDataHash);
  return sha256(message);
};

const getYParity = (messageHash: Uint8Array, { x }: WebauthnAttestation, r: Uint8Array, s: Uint8Array) => {
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
};

export const estimateAssertion = async (
  transactionHash: string,
  { rpId }: WebauthnAttestation,
): Promise<WebauthnAssertion> => {
  const rpIdHash = await sha256(new TextEncoder().encode(rpId));
  const flags = new Uint8Array([0b0001 | 0b0100]); // present and verified
  const signCount = new Uint8Array(4);
  const authenticatorData = concatBytes(rpIdHash, flags, signCount);
  const clientData = {
    type: "webauthn.get",
    challenge: buf2base64url(hex2buf(normalizeTransactionHash(transactionHash))),
    origin: document.location.origin,
    crossOrigin: false,
  };
  const clientDataJSON = new TextEncoder().encode(JSON.stringify(clientData));
  return {
    authenticatorData,
    clientDataJSON,
    r: new Uint8Array(32).fill(42),
    s: new Uint8Array(32).fill(69),
    yParity: false,
  };
};
