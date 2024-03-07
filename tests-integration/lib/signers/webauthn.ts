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
    192, 124, 237, 241, 226, 51, 92, 202, 34, 77, 132, 203, 43, 154, 106, 52, 77, 189, 35, 141, 70, 74, 180, 32, 83,
    247, 183, 175, 65, 250, 101, 106,
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

  if (messageHash == "0x6025c25480deefa8325ea72050c4f57929f192b9a9fb077282816889784ee45") {
    return {
      authenticatorData,
      clientDataJson,
      r: new Uint8Array([
        141, 93, 186, 67, 219, 144, 157, 219, 51, 172, 229, 71, 12, 235, 153, 163, 36, 208, 81, 180, 37, 115, 112, 148,
        23, 142, 136, 74, 85, 18, 218, 183,
      ]),
      s: new Uint8Array([
        25, 7, 151, 153, 217, 190, 121, 134, 222, 161, 197, 164, 26, 159, 75, 149, 162, 168, 195, 48, 92, 242, 208, 44,
        184, 110, 214, 186, 142, 18, 72, 41,
      ]),
      yParity: false,
    };
  } else if (messageHash == "0x23b620a9a761a6315d8da849eeed333a3a7fcda5d25ac56a404b877189a7a85") {
    return {
      authenticatorData,
      clientDataJson,
      r: new Uint8Array([
        233, 34, 142, 237, 241, 101, 17, 149, 67, 127, 32, 116, 94, 118, 24, 135, 185, 125, 29, 147, 103, 159, 226, 116,
        207, 212, 251, 53, 155, 166, 178, 22,
      ]),
      s: new Uint8Array([
        84, 251, 95, 64, 29, 237, 241, 32, 214, 139, 139, 154, 163, 251, 26, 238, 28, 254, 6, 89, 221, 195, 241, 46,
        241, 20, 156, 188, 163, 252, 59, 171,
      ]),
      yParity: true,
    };
  } else {
    throw new Error(`Unsupported message hash: ${messageHash}`);
  }
}
