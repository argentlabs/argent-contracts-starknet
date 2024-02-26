import { randomBytes } from "./bytes";

export interface WebauthnAttestation {
  email: string;
  rpId: string;
  credentialId: Uint8Array;
  x: Uint8Array;
  y: Uint8Array;
}

export const createWebauthnAttestation = async (email: string, rpId: string): Promise<WebauthnAttestation> => {
  const id = randomBytes(32);
  const challenge = randomBytes(32);
  const credential = await navigator.credentials.create({
    publicKey: {
      rp: { id: rpId, name: "Argent" },
      user: { id, name: email, displayName: email },
      challenge,
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
  // console.log("email");
  // console.log(email);
  // console.log(rpId);
  // console.log(credentialId);
  // console.log(x);
  // console.log(y);
  return {
    email,
    rpId: "localhost",
    credentialId,
    x,
    y,
  };
};
