import {
  Account,
  ArraySignatureType,
  CairoCustomEnum,
  CairoOption,
  CairoOptionVariant,
  CallData,
  hash,
  uint256,
} from "starknet";
import { RawSigner, fundAccount, provider } from "..";

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
const rpIdHash: string = buf2hex(
  new Uint8Array([
    73, 150, 13, 229, 136, 14, 140, 104, 116, 52, 23, 15, 100, 118, 96, 91, 143, 228, 174, 185, 162, 134, 50, 199, 153,
    92, 243, 186, 131, 29, 151, 99,
  ]),
);

const origin = "http://localhost:5173";
const pubkey = buf2hex(
  new Uint8Array([
    121, 231, 224, 51, 127, 167, 96, 95, 57, 249, 250, 53, 136, 126, 36, 208, 37, 216, 34, 127, 163, 34, 170, 150, 151,
    6, 246, 46, 5, 253, 205, 68,
  ]),
);

interface WebauthnAssertion {
  authenticatorData: Uint8Array;
  clientDataJson: Uint8Array;
  r: Uint8Array;
  s: Uint8Array;
  yParity: boolean;
}

export async function deployFixedWebauthnAccount(classHash: string): Promise<Account> {
  const constructorCalldata = CallData.compile({
    owner: webauthnSigner(origin, rpIdHash, pubkey),
    guardian: new CairoOption(CairoOptionVariant.None),
  });
  const addressSalt = 12n;
  const accountAddress = hash.calculateContractAddressFromHash(addressSalt, classHash, constructorCalldata, 0);

  await fundAccount(accountAddress, 1e16, "ETH");

  const account = new Account(provider, accountAddress, webauthnOwner, "1");
  const response = await account.deploySelf({ classHash, constructorCalldata, addressSalt }, { maxFee: 1e15 });
  await provider.waitForTransaction(response.transaction_hash);

  return account;
}

class WebauthnOwner extends RawSigner {
  public async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const { authenticatorData, clientDataJson, r, s, yParity } = await signTransaction(messageHash);
    const clientDataText = new TextDecoder().decode(clientDataJson.buffer);
    const clientData = JSON.parse(clientDataText);
    const clientDataOffset = (substring: string) => clientDataText.indexOf(substring) + substring.length;

    const cairoAssertion = {
      origin,
      rp_id_hash: uint256.bnToUint256(rpIdHash),
      pubkey: uint256.bnToUint256(pubkey),
      authenticator_data: CallData.compile(Array.from(authenticatorData)),
      client_data_json: CallData.compile(Array.from(clientDataJson)),
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

    return CallData.compile([
      [
        new CairoCustomEnum({
          Starknet: undefined,
          Secp256k1: undefined,
          Secp256r1: undefined,
          Webauthn: cairoAssertion,
        }),
      ],
    ]);
  }
}

const webauthnOwner = new WebauthnOwner();

function webauthnSigner(origin: string, rp_id_hash: string, pubkey: string) {
  return new CairoCustomEnum({
    Starknet: undefined,
    Secp256k1: undefined,
    Secp256r1: undefined,
    Webauthn: {
      origin,
      rp_id_hash: uint256.bnToUint256(rp_id_hash),
      pubkey: uint256.bnToUint256(pubkey),
    },
  });
}

async function signTransaction(messageHash: string): Promise<WebauthnAssertion> {
  const authenticatorData = new Uint8Array([
    73, 150, 13, 229, 136, 14, 140, 104, 116, 52, 23, 15, 100, 118, 96, 91, 143, 228, 174, 185, 162, 134, 50, 199, 153,
    92, 243, 186, 131, 29, 151, 99, 5, 0, 0, 0, 0,
  ]);
  const challenge = buf2base64url(hex2buf(normalizeTransactionHash(messageHash)));
  const clientData = { type: "webauthn.get", challenge, origin: "http://localhost:5173", crossOrigin: false };
  const clientDataJson = new TextEncoder().encode(JSON.stringify(clientData));

  if (messageHash == "0x4f008e37038b77515c972e58eefe8cb8350317df3d38c4aa04533185fabf69a") {
    return {
      authenticatorData,
      clientDataJson,
      r: new Uint8Array([
        82, 203, 168, 180, 232, 205, 247, 215, 126, 231, 223, 31, 52, 174, 42, 225, 114, 101, 138, 67, 18, 146, 215,
        198, 206, 222, 15, 25, 63, 232, 152, 214,
      ]),
      s: new Uint8Array([
        18, 213, 61, 109, 112, 236, 28, 178, 151, 232, 114, 21, 142, 5, 126, 51, 112, 216, 193, 20, 187, 29, 197, 72,
        158, 79, 64, 235, 122, 109, 152, 229,
      ]),
      yParity: true,
    };
  } else if (messageHash == "0x155341f0085195175c65999b0885998d847f21127076321d8c5c84f20d80ff2") {
    return {
      authenticatorData,
      clientDataJson,
      r: new Uint8Array([
        133, 59, 200, 93, 139, 18, 54, 216, 236, 147, 133, 213, 201, 65, 181, 124, 155, 158, 131, 184, 20, 220, 115, 58,
        162, 235, 232, 92, 11, 21, 250, 113,
      ]),
      s: new Uint8Array([
        237, 136, 79, 80, 48, 31, 134, 89, 110, 36, 236, 44, 251, 253, 156, 75, 42, 188, 126, 241, 22, 179, 254, 238,
        131, 184, 71, 97, 30, 206, 9, 188,
      ]),
      yParity: true,
    };
  } else {
    throw new Error(`Unsupported message hash: ${messageHash}`);
  }
}
