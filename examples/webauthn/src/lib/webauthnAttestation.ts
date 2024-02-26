import { randomBytes } from "./bytes";

export interface WebauthnAttestation {
  email: string;
  rpId: string;
  credentialId: Uint8Array;
  x: Uint8Array;
  y: Uint8Array;
}

export const createWebauthnAttestation = async (email: string, rpId: string): Promise<WebauthnAttestation> => {
  // const id = new Uint8Array([
  //   25, 26, 23, 38, 13, 4, 10, 30, 36, 6, 24, 28, 12, 25, 3, 4, 28, 10, 32, 22, 2, 10, 16, 11, 23, 27, 5, 10, 2, 37, 19,
  //   36,
  // ]); // randomBytes(32);
  // const challenge = new Uint8Array([
  //   12, 2, 2, 20, 5, 22, 15, 6, 21, 22, 10, 33, 8, 12, 6, 15, 39, 22, 20, 4, 26, 36, 22, 29, 36, 4, 12, 34, 33, 25, 28,
  //   24,
  // ]); //randomBytes(32);
  // const credential = await navigator.credentials.create({
  //   publicKey: {
  //     rp: { id: rpId, name: "Argent" },
  //     user: { id, name: email, displayName: email },
  //     challenge,
  //     pubKeyCredParams: [
  //       { type: "public-key", alg: -7 }, // -7 means secp256r1 with SHA-256 (ES256). RS256 not supported on purpose.
  //     ],
  //     authenticatorSelection: {
  //       authenticatorAttachment: "platform",
  //       residentKey: "preferred",
  //       requireResidentKey: false,
  //       userVerification: "required",
  //     },
  //     attestation: "none",
  //     extensions: { credProps: true },
  //     timeout: 60000,
  //   },
  // });

  // if (!credential) {
  //   throw new Error("No credential");
  // }

  // const attestation = credential as PublicKeyCredential;
  // const attestationResponse = attestation.response as AuthenticatorAttestationResponse;

  // const credentialId = new Uint8Array(attestation.rawId);
  // const publicKey = new Uint8Array(attestationResponse.getPublicKey()!);
  // const x = publicKey.slice(-64, -32);
  // const y = publicKey.slice(-32);
  // console.log("email");
  // console.log(email);
  // console.log(rpId);
  // console.log(credentialId);
  // console.log(x);
  // console.log(y);
  // return {
  //   email,
  //   rpId: "localhost",
  //   credentialId,
  //   x,
  //   y,
  // }; 0x68fcea2b1be829a13219a54426df7debf2fb6d5c39171a310c0652602f4cd58 0x24d0db008d772f1f753465250b704eac1250ed9c63981757173c2a5f9ebf390
  return {
    email: "axel@argent.xyz",
    rpId: "localhost",
    credentialId: new Uint8Array([
      192, 249, 188, 136, 177, 247, 200, 17, 50, 91, 146, 20, 183, 251, 82, 196, 18, 98, 13, 24, 51, 16, 14, 114, 178,
      211, 111, 67, 103, 51, 8, 248,
    ]),
    x: new Uint8Array([
      46, 159, 209, 182, 176, 149, 169, 127, 113, 209, 4, 16, 168, 36, 95, 120, 80, 91, 75, 116, 255, 147, 226, 134,
      140, 165, 174, 224, 46, 166, 106, 155,
    ]),
    y: new Uint8Array([
      119, 151, 21, 18, 129, 196, 15, 139, 136, 127, 133, 106, 135, 185, 122, 183, 196, 5, 55, 132, 101, 85, 114, 130,
      152, 255, 19, 103, 155, 236, 95, 103,
    ]),
  };
};
