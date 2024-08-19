import { randomBytes } from "./bytes";

export interface WebauthnAttestation {
  email: string;
  origin: string;
  rpId: string;
  credentialId: Uint8Array;
  pubKey: Uint8Array;
}

export const createWebauthnAttestation = async (
  email: string,
  rpId: string,
  origin: string,
): Promise<WebauthnAttestation> => {
  const id = randomBytes(32);
  const challenge = randomBytes(32);
  const credential = await navigator.credentials.create({
    publicKey: {
      rp: { id: rpId, name: "Argent" },
      user: { id, name: email, displayName: email },
      challenge,
      // -7 means secp256r1 with SHA-256 (ES256). RS256 not supported on purpose.
      pubKeyCredParams: [{ type: "public-key", alg: -7 }],
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
  return { email, rpId, origin, credentialId, pubKey: x };
};

export const requestSignature = async (
  attestation: WebauthnAttestation,
  challenge: Uint8Array,
): Promise<AuthenticatorAssertionResponse> => {
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
  return assertion.response as AuthenticatorAssertionResponse;
};
