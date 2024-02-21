import { randomBytes } from "./bytes";

export interface WebauthnAttestation {
  email: string;
  rpId: string;
  credentialId: Uint8Array;
  x: Uint8Array;
  y: Uint8Array;
}

export const createWebauthnAttestation = async (email: string, rpId: string): Promise<WebauthnAttestation> => {
  const id = new Uint8Array([
    25, 26, 23, 38, 13, 4, 10, 30, 36, 6, 24, 28, 12, 25, 3, 4, 28, 10, 32, 22, 2, 10, 16, 11, 23, 27, 5, 10, 2, 37, 19,
    36,
  ]); // randomBytes(32);
  const challenge = new Uint8Array([
    12, 2, 2, 20, 5, 22, 15, 6, 21, 22, 10, 33, 8, 12, 6, 15, 39, 22, 20, 4, 26, 36, 22, 29, 36, 4, 12, 34, 33, 25, 28,
    24,
  ]); //randomBytes(32);
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
  console.log("email");
  console.log(email);
  console.log(rpId);
  console.log(credentialId);
  console.log(x);
  console.log(y);
  // return {
  //   email: "axel@argent.xyz",
  //   rpId: "localhost",
  //   credentialId: new Uint8Array([
  //     80, 185, 68, 21, 129, 99, 225, 26, 64, 2, 221, 225, 176, 93, 107, 115, 217, 65, 90, 214, 74, 9, 33, 201, 75, 165,
  //     29, 244, 222, 30, 157, 4,
  //   ]),
  //   x: new Uint8Array([
  //     49, 134, 80, 121, 64, 151, 144, 208, 187, 46, 70, 210, 94, 67, 107, 22, 84, 163, 139, 254, 112, 68, 73, 48, 222,
  //     239, 184, 34, 169, 208, 128, 216,
  //   ]),
  //   y: new Uint8Array([
  //     14, 28, 68, 32, 241, 109, 20, 82, 73, 218, 107, 176, 210, 38, 43, 54, 4, 185, 121, 97, 199, 247, 162, 77, 188,
  //     198, 168, 89, 215, 172, 184, 199,
  //   ]),
  // };

  return {
    email,
    rpId: "localhost",
    credentialId,
    x,
    y,
  };
};
