import { randomBytes } from "./bytes";

export interface WebauthnAttestation {
  email: string;
  rpId: string;
  credentialId: Uint8Array;
  x: Uint8Array;
  y: Uint8Array;
}

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
