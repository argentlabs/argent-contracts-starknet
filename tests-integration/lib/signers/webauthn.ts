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
import { KeyPair, fundAccount, provider } from "..";

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
    237, 31, 69, 96, 205, 230, 65, 107, 13, 190, 184, 174, 66, 238, 67, 104, 208, 149, 53, 243, 37, 232, 160, 102, 105,
    68, 66, 2, 247, 74, 66, 110,
  ]),
);
interface WebauthnAssertion {
  authenticatorData: Uint8Array;
  clientDataJson: Uint8Array;
  r: Uint8Array;
  s: Uint8Array;
  yParity: boolean;
}

class WebauthnOwner extends KeyPair {
  public get guid(): bigint {
    throw new Error("Not yet implemented");
  }

  public get signer(): CairoCustomEnum {
    return new CairoCustomEnum({
      Starknet: undefined,
      Secp256k1: undefined,
      Secp256r1: undefined,
      Eip191: undefined,
      Webauthn: {
        origin,
        rp_id_hash: uint256.bnToUint256(rpIdHash),
        pubkey: uint256.bnToUint256(pubkey),
      },
    });
  }

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
          Eip191: undefined,
          Webauthn: cairoAssertion,
        }),
      ],
    ]);
  }
}

export async function deployFixedWebauthnAccount(classHash: string): Promise<Account> {
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

async function signTransaction(messageHash: string): Promise<WebauthnAssertion> {
  const authenticatorData = new Uint8Array([
    73, 150, 13, 229, 136, 14, 140, 104, 116, 52, 23, 15, 100, 118, 96, 91, 143, 228, 174, 185, 162, 134, 50, 199, 153,
    92, 243, 186, 131, 29, 151, 99, 5, 0, 0, 0, 0,
  ]);
  const challenge = buf2base64url(hex2buf(normalizeTransactionHash(messageHash)));
  const clientData = { type: "webauthn.get", challenge, origin: "http://localhost:5173", crossOrigin: false };
  const clientDataJson = new TextEncoder().encode(JSON.stringify(clientData));

  if (messageHash == "0x217da84d7df587ccb09a1bdce589ba001df1d37bf002a19727ecd27d85756be") {
    return {
      authenticatorData,
      clientDataJson,
      r: new Uint8Array([
        159, 43, 94, 154, 88, 219, 249, 249, 167, 180, 144, 60, 244, 98, 103, 60, 199, 242, 76, 151, 183, 32, 55, 35,
        242, 66, 131, 176, 49, 108, 170, 88,
      ]),
      s: new Uint8Array([
        18, 78, 71, 251, 202, 16, 205, 131, 166, 2, 61, 46, 163, 190, 194, 20, 180, 132, 75, 25, 211, 39, 8, 171, 148,
        152, 66, 170, 142, 134, 157, 58,
      ]),
      yParity: false,
    };
  } else if (messageHash == "0x6e3005333b997788ea3d97bcf4169124bf16eb6b2439ef49039d5c78bd6e018") {
    return {
      authenticatorData,
      clientDataJson,
      r: new Uint8Array([
        55, 232, 189, 4, 168, 76, 186, 194, 91, 59, 202, 10, 32, 251, 180, 49, 23, 253, 142, 158, 209, 157, 186, 231,
        166, 139, 44, 159, 80, 159, 51, 173,
      ]),
      s: new Uint8Array([
        111, 20, 120, 103, 193, 223, 143, 131, 60, 67, 222, 150, 152, 171, 14, 45, 189, 29, 174, 193, 158, 235, 12, 201,
        96, 155, 152, 57, 192, 199, 200, 230,
      ]),
      yParity: false,
    };
  } else {
    throw new Error(`Unsupported message hash: ${messageHash}`);
  }
}
